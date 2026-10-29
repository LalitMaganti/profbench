// Copyright 2026 The Profbench Authors.
// SPDX-License-Identifier: Apache-2.0

// Shared workload support: argument parsing, the start/end signal to the
// harness, and worker threads with a known entry point. Workloads print
// nothing; the harness does all measurement.

#ifndef WORKLOADS_COMMON_H_
#define WORKLOADS_COMMON_H_

#include <pthread.h>
#include <sys/prctl.h>
#include <unistd.h>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <string>
#include <utility>
#include <vector>

namespace pb {

// Parses --key=value arguments. Every argument must be read with Get();
// Finish() rejects any that were not, so typos fail loudly.
class Args {
 public:
  Args(int argc, char** argv) {
    for (int i = 1; i < argc; i++) {
      const char* eq = strchr(argv[i], '=');
      if (strncmp(argv[i], "--", 2) != 0 || !eq) Fail("expected --key=value, got", argv[i]);
      const size_t len = static_cast<size_t>(eq - argv[i]) - 2;
      values_.push_back({std::string(argv[i] + 2, len), std::string(eq + 1), false});
    }
  }

  int64_t Get(const char* key, int64_t fallback) {
    for (auto& v : values_) {
      if (v.key != key) continue;
      v.used = true;
      char* end = nullptr;
      int64_t n = strtoll(v.value.c_str(), &end, 10);
      if (v.value.empty() || *end != '\0' || n < 0) Fail("expected a non-negative integer for", key);
      return n;
    }
    return fallback;
  }

  void Finish() const {
    for (const auto& v : values_) {
      if (!v.used) Fail("unknown argument", v.key.c_str());
    }
  }

 private:
  struct Value {
    std::string key;
    std::string value;
    bool used;
  };

  [[noreturn]] static void Fail(const char* what, const char* arg) {
    fprintf(stderr, "error: %s %s\n", what, arg);
    exit(2);
  }

  std::vector<Value> values_;
};

// Tells the harness where the measured work begins and ends, by writing one
// byte to the descriptor in PB_SYNC_FD. Without it, a workload runs normally.
inline void Signal(char c) {
  static const int fd = [] {
    const char* s = getenv("PB_SYNC_FD");
    return s ? atoi(s) : -1;
  }();
  if (fd >= 0 && write(fd, &c, 1) != 1) {
    perror("PB_SYNC_FD");
    exit(1);
  }
}

// Thread names let profilers' output be attributed to workload threads.
inline void SetThreadName(const char* name) {
  prctl(PR_SET_NAME, name, 0, 0, 0);
}

// Arithmetic busy work the compiler cannot elide.
__attribute__((noinline)) inline uint64_t Spin(uint64_t n) {
  uint64_t x = n;
  for (uint64_t i = 0; i < n; i++) {
    x = x * 6364136223846793005ULL + 1442695040888963407ULL;
    asm volatile("" : "+r"(x));
  }
  return x;
}

struct Worker {
  std::function<void(int)> fn;
  int index;
  pthread_barrier_t* start;
};

}  // namespace pb

// The entry point of every worker thread, so that fully unwound stacks can be
// recognised by reaching it.
extern "C" __attribute__((noinline)) inline void* pb_thread_entry(void* arg) {
  auto* w = static_cast<pb::Worker*>(arg);
  pb::SetThreadName("pb-work");
  pthread_barrier_wait(w->start);
  w->fn(w->index);
  return nullptr;
}

namespace pb {

// Runs fn(i) on `threads` worker threads. All setup happens before the start
// signal and all threads are joined before the end signal.
inline void RunWorkers(int threads, std::function<void(int)> fn) {
  SetThreadName("pb-main");
  pthread_barrier_t start;
  pthread_barrier_init(&start, nullptr, threads + 1);
  std::vector<Worker> workers;
  workers.reserve(threads);
  std::vector<pthread_t> ids(threads);
  for (int i = 0; i < threads; i++) {
    workers.push_back({fn, i, &start});
    if (pthread_create(&ids[i], nullptr, pb_thread_entry, &workers[i]) != 0) {
      perror("pthread_create");
      exit(1);
    }
  }
  Signal('S');
  pthread_barrier_wait(&start);
  for (pthread_t id : ids) pthread_join(id, nullptr);
  Signal('E');
  pthread_barrier_destroy(&start);
}

}  // namespace pb

#endif  // WORKLOADS_COMMON_H_
