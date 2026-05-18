---
layout: post
title: "C++ 的虚函数到底有多慢？"
lang: zh
sitemap: false
ref: cxx-virtual-function-overhead
permalink: /zh/posts/how-much-slower-are-c-virtual-functions-really/
hidden: true
date: 2026-05-18 22:54 +0800
---

我在读到[这篇文章](https://isocpp.org/wiki/faq/strange-inheritance#final-classes)的时候，突然就非常的好奇，想知道 virtual function in C++ 到底会给性能带来多大的开销。一直以来，我知道使用虚函数会带来开销——这种开销主要是查表——但我并不知道这到底会慢多少。

原文提到：

> In today’s usual implementations, calling a virtual function entails fetching the “vptr” (i.e. the pointer to the virtual table) from the object, indexing into it via a constant, and calling the function indirectly via the pointer to function found at that location. A regular call is most often a direct call to a literal address. Although a virtual call seems to be a lot more work, the right way to judge costs is in comparison to the work actually carried by the function. If that work is significant, the cost of the call itself is negligible by comparison and often cannot be measured. If, however, the function body is simple (i.e. an accessor or a forward), the cost of a virtual call can be measurable and sometimes significant.

也就是说，如果 virtual function 本身比较重，那么这种开销并不明显；但反过来则不是这样。

正如[这篇回答](https://isocpp.org/wiki/faq/virtual-functions#dyn-binding2)说的那样，virtual function 的调用本质上是两次 fetch 和一次 call。我想试着看看，这三步的开销到底有多大。

测试代码的话如下所示，我们采用 [Google Benchmark](https://github.com/google/benchmark) 框架来做测试

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

这个代码相对简单，我们设计了两个类，一个是直接调用函数，而另外一个则是通过虚函数来调用。对于被调用的函数，我们设计了两种，一种用于代表微不足道的操作，而另一种这代表较为复杂的操作。

大体的结果如下：

测试环境为：`Macbook Air M4`

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

可以看到，对于较轻的操作而言，涉及到 vptr 的调用的时间是没有涉及到 vptr 的调用时间的三倍；而对于较重的操作来说，差距则可以直接忽略