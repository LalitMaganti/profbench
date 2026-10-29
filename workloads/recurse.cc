// Copyright 2026 The Profbench Authors.
// SPDX-License-Identifier: Apache-2.0

// Deep call stacks: each iteration recurses `depth` frames and does all its
// work at the leaf. Stresses unwinding, whose cost grows with stack depth.

#include "workloads/common.h"

namespace {

__attribute__((noinline)) uint64_t Descend(int64_t depth, uint64_t work) {
  if (depth == 0) return pb::Spin(work);
  uint64_t r = Descend(depth - 1, work);
  asm volatile("" : "+r"(r));
  return r + 1;
}

}  // namespace

int main(int argc, char** argv) {
  pb::Args args(argc, argv);
  const int64_t threads = args.Get("threads", 4);
  const int64_t iterations = args.Get("iterations", 2000);
  const int64_t depth = args.Get("depth", 64);
  const int64_t work = args.Get("work", 500000);
  args.Finish();

  pb::RunWorkers(static_cast<int>(threads), [&](int) {
    uint64_t acc = 0;
    for (int64_t i = 0; i < iterations; i++) acc += Descend(depth, work);
    asm volatile("" ::"r"(acc));
  });
  return 0;
}
