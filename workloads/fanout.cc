// Copyright 2026 The Profbench Authors.
// SPDX-License-Identifier: Apache-2.0

// Many different stacks: 256 distinct functions, each called along fixed-seed
// pseudo-random paths 8 to 16 deep. Stresses symbolization, deduplication and
// aggregation. Every function does the same work per visit, so with the seed
// fixed each function's share of the total work is known.

#include <array>

#include "workloads/common.h"

namespace {

constexpr int kNodes = 256;
constexpr int kMinDepth = 8;
constexpr int kMaxDepth = 16;

using NodeFn = uint64_t (*)(const uint8_t* path, int remaining, uint64_t work);
extern const std::array<NodeFn, kNodes> kNodeTable;

template <int I>
__attribute__((noinline)) uint64_t Node(const uint8_t* path, int remaining, uint64_t work) {
  // Distinct per instantiation, so the linker cannot fold identical bodies.
  asm volatile("" ::"i"(I));
  uint64_t r = pb::Spin(work);
  if (remaining > 0) r += kNodeTable[path[0]](path + 1, remaining - 1, work);
  asm volatile("" : "+r"(r));
  return r;
}

template <int... I>
constexpr std::array<NodeFn, kNodes> MakeTable(std::integer_sequence<int, I...>) {
  return {&Node<I>...};
}

const std::array<NodeFn, kNodes> kNodeTable = MakeTable(std::make_integer_sequence<int, kNodes>());

// xorshift64*, seeded per thread so every run visits the same paths.
uint64_t Next(uint64_t& state) {
  state ^= state >> 12;
  state ^= state << 25;
  state ^= state >> 27;
  return state * 2685821657736338717ULL;
}

}  // namespace

int main(int argc, char** argv) {
  pb::Args args(argc, argv);
  const int64_t threads = args.Get("threads", 4);
  const int64_t iterations = args.Get("iterations", 200000);
  const int64_t work = args.Get("work", 400);
  const int64_t seed = args.Get("seed", 1);
  args.Finish();

  // Paths are generated before the start signal so only the calls are measured.
  // Each path is a length byte followed by that many node indices.
  std::vector<std::vector<uint8_t>> paths(threads);
  for (int64_t t = 0; t < threads; t++) {
    uint64_t state = static_cast<uint64_t>(seed) * 0x9E3779B97F4A7C15ULL + static_cast<uint64_t>(t) + 1;
    auto& p = paths[t];
    for (int64_t i = 0; i < iterations; i++) {
      const int len = kMinDepth + static_cast<int>(Next(state) % (kMaxDepth - kMinDepth + 1));
      p.push_back(static_cast<uint8_t>(len));
      for (int d = 0; d < len; d++) p.push_back(static_cast<uint8_t>(Next(state) % kNodes));
    }
  }

  pb::RunWorkers(static_cast<int>(threads), [&](int t) {
    const uint8_t* p = paths[t].data();
    uint64_t acc = 0;
    for (int64_t i = 0; i < iterations; i++) {
      const int len = *p++;
      acc += kNodeTable[p[0]](p + 1, len - 1, work);
      p += len;
    }
    asm volatile("" ::"r"(acc));
  });
  return 0;
}
