---
layout: post
title: "How much slower are C++ virtual functions, really?"
lang: en
ref: cxx-virtual-function-overhead
permalink: /en/posts/how-much-slower-are-c-virtual-functions-really/
date: 2026-05-18 22:54 +0800
categories:
  - CXX-Language
tags:
  - C++
  - Benchmark
  - Virtual Function
---

When I was reading [this article](https://isocpp.org/wiki/faq/strange-inheritance#final-classes), I suddenly became very curious about how much overhead virtual functions in C++ actually introduce to performance. For a long time, I've known that using virtual functions incurs some overhead—primarily due to table lookups—but I didn't know exactly *how much* slower they are.

The original text mentions:

> In today’s usual implementations, calling a virtual function entails fetching the “vptr” (i.e. the pointer to the virtual table) from the object, indexing into it via a constant, and calling the function indirectly via the pointer to function found at that location. A regular call is most often a direct call to a literal address. Although a virtual call seems to be a lot more work, the right way to judge costs is in comparison to the work actually carried by the function. If that work is significant, the cost of the call itself is negligible by comparison and often cannot be measured. If, however, the function body is simple (i.e. an accessor or a forward), the cost of a virtual call can be measurable and sometimes significant.

In other words, if the virtual function itself is relatively heavy, this overhead is not noticeable; but the reverse is not true.

As [this answer](https://isocpp.org/wiki/faq/virtual-functions#dyn-binding2) puts it, a virtual function call essentially involves two fetches and one call. I wanted to see exactly how much overhead these three steps take.

The test code is shown below. We used the [Google Benchmark](https://github.com/google/benchmark) framework for testing.

```cpp
#include <benchmark/benchmark.h>

class NonVirtual {
 public:
  void Inc() { benchmark::DoNotOptimize(count_++); }
  void HeavyInc(std::size_t cnt) {
    for (int i = 0; i < cnt; i++) {
      benchmark::DoNotOptimize(count_++);
    }
  }

 private:
  std::size_t count_ = 0;
};

class VirtualBase {
 public:
  virtual ~VirtualBase() = default;
  virtual void Inc() = 0;
  virtual void HeavyInc(std::size_t cnt) = 0;
};

class Virtual final : public VirtualBase {
 public:
  void Inc() override { benchmark::DoNotOptimize(count_++); }
  void HeavyInc(std::size_t cnt) override {
    for (int i = 0; i < cnt; i ++) {
      benchmark::DoNotOptimize(count_++);
    }
  }

 private:
  std::size_t count_ = 0;
};

__attribute__((noinline)) std::unique_ptr<VirtualBase> MakeVirtual() {
  return std::make_unique<Virtual>();
}

static void BM_NonVirtual(benchmark::State& state) {
  auto ptr = std::make_unique<NonVirtual>();
  for (auto _ : state) {
    ptr->Inc();
  }
}

static void BM_Virtual(benchmark::State& state) {
  std::unique_ptr<VirtualBase> ptr = MakeVirtual();
  for (auto _ : state) {
    ptr->Inc();
  }
}

static void BM_NonVirtualHeavy(benchmark::State& state) {
  auto ptr = std::make_unique<NonVirtual>();
  std::size_t cnt = state.range();
  for (auto _ : state) {
    ptr->HeavyInc(cnt);
  }
}

static void BM_VirtualHeavy(benchmark::State& state) {
  std::unique_ptr<VirtualBase> ptr = MakeVirtual();
  std::size_t cnt = state.range();
  for (auto _ : state) {
    ptr->HeavyInc(cnt);
  }
}


BENCHMARK(BM_NonVirtual);
BENCHMARK(BM_Virtual);
BENCHMARK(BM_NonVirtualHeavy)->RangeMultiplier(8)->Range(8, 4096);
BENCHMARK(BM_VirtualHeavy)->RangeMultiplier(8)->Range(8, 4096);
BENCHMARK_MAIN();
```

The code is relatively simple. We designed two classes: one invokes functions directly, while the other invokes them through virtual functions. For the invoked functions, we designed two types: one represents a trivial operation, and the other represents a more complex operation.

The general results are as follows:

Test environment: `Macbook Air M4`

```fish
Unable to determine clock rate from sysctl: hw.cpufrequency: No such file or directory
This does not affect benchmark measurements, only the metadata output.
***WARNING*** Failed to set thread affinity. Estimated CPU frequency may be incorrect.
2026-05-18T23:05:44+08:00
Running ./build/benchmark_vptr
Run on (10 X 24 MHz CPU s)
CPU Caches:
  L1 Data 64 KiB
  L1 Instruction 128 KiB
  L2 Unified 4096 KiB (x10)
Load Average: 1.69, 1.72, 1.81
------------------------------------------------------------------
Benchmark                        Time             CPU   Iterations
------------------------------------------------------------------
BM_NonVirtual                0.519 ns        0.519 ns   1353206132
BM_Virtual                    1.89 ns         1.89 ns    371275969
BM_NonVirtualHeavy/8          4.02 ns         4.02 ns    174480919
BM_NonVirtualHeavy/64         32.1 ns         32.1 ns     21831814
BM_NonVirtualHeavy/512         259 ns          259 ns      2720095
BM_NonVirtualHeavy/4096       2062 ns         2060 ns       340616
BM_VirtualHeavy/8             5.57 ns         5.57 ns    120442540
BM_VirtualHeavy/64            33.6 ns         33.6 ns     20614488
BM_VirtualHeavy/512            259 ns          259 ns      2675984
BM_VirtualHeavy/4096          2054 ns         2054 ns       338637
```

As we can see, for lighter operations, the time taken by calls involving a `vptr` is about three times that of calls without a `vptr`. However, for heavier operations, the difference becomes completely negligible.