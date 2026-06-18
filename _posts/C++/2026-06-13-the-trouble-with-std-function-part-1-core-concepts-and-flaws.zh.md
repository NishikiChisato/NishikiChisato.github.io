---
layout: post
title: "std::function 缺陷剖析 - Part 1：核心概念与遗留问题"
date: 2026-06-13 14:31:00 +0800
lang: zh
ref: the-trouble-with-std-function
hidden: true
sitemap: false
---

# Introduction

在阅读了许多关于 std::function 的资料之后，我想简单将其整理一下。本文将会简单梳理 std::function 存在的问题。尽管在 C++23 乃至 C++26 的今天，std::function 的诸多问题已经得到了解决，但这个过程依然值得回顾。本文将会着重聚焦于 [N4159](https://wg21.link/n4159) 这篇 Proposal，将 std::function 的问题按照我的理解尽数阐明。

# Definitions

在开始我们的讨论之前，我们需要先明确一些定义：
- A [function object type](https://eel.is/c++draft/function.objects#general-1.sentence-1) is an object type that can be the type of the postfix-expression in a function call.
- A [function object](https://eel.is/c++draft/function.objects#general-1.sentence-2) is an object of a function object type.
- A [callable type](https://eel.is/c++draft/function.objects#func.def-3) is a function object type or a pointer to member.
- A [callable object](https://eel.is/c++draft/function.objects#func.def-4) is an object of a callable type.
- The [std::function](https://eel.is/c++draft/function.objects#func.wrap.func.general-1) class template provides polymorphic wrappers that generalize the notion of a function pointer. Wrappers can store, copy, and call arbitrary callable objects, given a call signature.

此外，我们可以对 callable type 进行细分，即：
- lvalue-callable: is a non-const lvalue of that type
- rvalue-callable: is a non-const rvalue of that type
- callable contains lvalue-callable and rvalue-callable
- const-callable contains const lvalue-callable and const rvalue-callable

# The trouble with std::function

## Const-correctness

由于 std::function 是 C++98 时代的产物，因此在 C++11 之前，它都工作的非常好。但是 C++11 引入了 lambda。我们可以将 lambda 传递给一个 std::function，并且这个 lambda 与传统的函数最大的不同点在于，它内部可以存储状态。这就导致了一系列新的问题。本文讨论的 std::function 的问题也主要聚焦在这种场景，即传递一个 function object 给 std::function 所引发的问题。

如果我们去看 std::function 的 [operator()](https://eel.is/c++draft/function.objects#lib:function,invocation) 函数，我们会发现这个函数被声明为 const。这意味着这个函数必然不会去修改一个 std::function 内部的状态。

直觉上来说，我们对于被 const 修饰的值类型(value type)的理解一般都是 deep const，即只要这个对象是 const 的，那么我们就不能去修改它的状态。而复合类型的 const 则有两种语义，deep const 和 shallow const。前者用于表示我们不能通过这个对象去修改该对象指向的对象；后者表示我们不能修改该对象本身：

```cpp
// deep const
const int v1 = 1;

// deep const
const int* ptr1 = nullptr;

// shallow const
int* const ptr2 = nullptr;
```

当我们将一个 function object 传给一个 std::function 时，无论名义上这个 function object 是不是该 std::function 的成员，它直觉上理解都应该是它的成员。这个 function object 会跟随着 std::function 的拷贝而拷贝，移动而移动，销毁而销毁。

因此，当我们调用一个 non-const std::function 时，我们认为它可以自由去修改该 function object 的内部状态，但一旦我们调用的是一个 const std::function 时，我们期望它不应该去修改 function object 的内部状态。

这里便是矛盾的地方。std::function 只提供了一个 operator() 函数，并且这个函数还被声明成了 const，它根本没有提供 non-const 的 operator() 函数。这意味着，当 non-const std::function 调用时，由于我们期望它会修改 function object 的内部状态，而由于它只能调用 const operator() 函数，因此它必然是在一个 const 的上下文当中去修改了内部的状态：

```cpp
int main() {
  int val{1};
  std::function<int()> f1 = [val]() mutable { return ++val; };
  const std::function<int()> f2 = [val]() mutable { return ++val; };
  std::println("f1={}", f1());
  std::println("f2={}", f2());
  return 0;
}
```

在上面的代码当中，std::function 本身的 constness 不会对调用的结果其任何作用。无论它是否是 const，它都可以去调用一个能够修改自身内部状态的 function object。

除此之外，还有一个问题。[res.on.data.race](https://eel.is/c++draft/res.on.data.races#2) 有这样一段：

> A C++ standard library function shall not directly or indirectly access objects accessible
> by threads other than the current thread unless the objects are accessed directly or indirectly
> via the function's arguments, including this.

直观理解便是，标准库不应该在多线程的上下文中以直接或者间接的方式去访问一个 non-const 对象。换句话说，如果对象是 const 的，那么哪怕是在多线程的上下文中，标准库也可以随意通过直接或者间接的方式去访问该对象。

而由于哪怕是 const std::function，它本质上也会去修改自身内部的状态，因此标准的这一条在 std::function 身上并不奏效。

换句话说，如果我在多线程的上下文当中访问 const std::function，必然将会造成 data race 的问题。


## Shallow const

C++ 当中有一些类具有 shallow const，由于 shallow const 是 reference 所具有的语义，因此这些类往往本身也用来充当 reference，即 pointers, smart pointers, iterators 和 reference：
- 它们具有 shallow copy 语义：对于这些对象的拷贝，得到的结果都指向相同的底层对象。
- 它们具有 shallow const 语义：这些对象无法修改它们所引用的底层对象，但对于底层对象的修改则不受限制。

```cpp
int main() {
  auto sp1 = std::make_shared<int>(1);
  auto sp2 = sp1;
  // sp1 and sp2 point to the same data

  auto up1 = std::make_unique<int>(1);
  auto up2 = std::move(up1);
  // up2 points to the data originally pointed by up1

  int val{};
  auto r1 = std::ref(val);
  auto r2 = r1;
  // r1 and r2 both point to the same data
  return 0;
}
```

但这两个性质并没办法适用于 std::function。std::function 的 `operator()` 具有 shallow const 的属性，因为它可以随意修改 function object 的状态，但它却没办法去调用其他的 function object。

但是，std::function 提供了一个 `target()` 函数，这个函数能够直接访问传入给 std::function 的对象的内存块。换句话说，我们可以通过这个函数，去修改 std::function 所保存的 function object：

```cpp
struct Functor {
  Functor(int v = 0) : val{v}{}
  int operator()() { return val++; }
  int val{};
};

int main() {
  Functor obj1{1};
  Functor obj2{10};
  const std::function<int()> f1(obj1);
  f1();
  auto* ptr = f1.target<Functor>();
  if (ptr) {
    std::println("val={}", ptr->val);
  }
  f1();
  ptr = f1.target<Functor>();
  if (ptr) {
    std::println("val={}", ptr->val);
  }
  return 0;
}
```

我们一开始创建了两个对象 `obj1` 和 `obj2`。如果我们知道 std::function 内部所保存的对象的类型的话，那么我们可以直接通过 `target()` 函数来拿到这个对象的地址。如果 std::function 本身是 non-const 的话，那么我们可以通过这个 `target()` 函数去修改它内部的地址（参考下面的例子）。在上面的这个例子当中，我们将 std::function 声明成了 const，因为我们需要观察 `target()` 的 const 语义。

实际上 std::function 提供了两个重载，而带有 const 的重载具有的是 deep const 的语义，即我无法去修改通过 `target()` 拿到的这块内存地址。

这种设计十分的割裂，也是众多问题产生的原因。对于一个 const std::function 而言，它的 `operator()` 函数的 const 表现为 shallow const，而它的 `target()` 函数表现为 deep const。而这两个函数的行为又恰好互相相反，即 `operator()` 的作用是操作 std::function 的内部成员，而 `target()` 的作用是获取 std::function 的内部成员。

如果我们的 std::function 声明为 non-const，那么我们可以通过这个 `target()` 函数去修改它的内部成员：

```cpp
struct Functor {
  Functor(int v = 0) : val{v}{}
  int operator()() { return val++; }
  int val{};
};

int main() {
  Functor obj1{1};
  Functor obj2{10};
  std::function<int()> f1(obj1);
  f1();
  auto* ptr = f1.target<Functor>();
  if (ptr) {
    std::println("val={}", ptr->val);
    *ptr = obj2;
  }
  f1();
  ptr = f1.target<Functor>();
  if (ptr) {
    std::println("val={}", ptr->val);
  }
  return 0;
}
```

哪怕我们不用 function object，这个 `target()` 在面对 free function 的时候也会有同样的问题：

```cpp
static void func1() {
  std::println("func1");
}

static void func2() {
  std::println("func2");
}

int main() {
  std::function<void()> f1(func1);
  f1();
  auto* ptr = f1.target<void(*)()>();
  if (ptr) {
    *ptr = func2;
  }
  f1();
  return 0;
}
```

## Non-copyable function objects

std::function 本身是支持 copy 的，它的 copy-ctor 的 [Postconditions](https://eel.is/c++draft/function.objects#func.wrap.func.con-3) 要求它的 `target()` 必须是 copyable。因此，std::function 没办法去跟 move-only 的 function object 搭配使用，即：

```cpp
int main() {
  auto ptr = std::make_unique<int>(1);
  auto fn = [ptr = std::move(ptr)]() { return static_cast<bool>(ptr); };
  // std::function<int()> func(fn); // compile error
  return 0;
}
```

乍一看，这似乎可以当成是 std::function 的 feature。但实际上，这跟标准当中对于 std::function 的定义是相违背的。std::function 要求能够调用任意的 callable object。显然这里的 move-only function object 是 callable object，它理所应当能够被 std::function 调用才是。不过这一点实际上并不致命，我们也可以当成是一个 feature。正如 [N4159](https://wg21.link/n4159) 当中所说的那样：

> std::function’s lack of support for non­copyable and non­lvalue­callable function objects could
> plausibly be treated as a feature request, but the const­correctness issue is an outright defect

## Non-lvalue-callable function objects

如果我们去看 std::function 的 `operator()` 函数在标准里面的定义：

> [func.wrap.func.inv](https://eel.is/c++draft/function.objects#lib:function,invocation)
> R operator()(ArgTypes... args) const;
> Returns: INVOKE<R>(f, std::forward<ArgTypes>(args)...), where f is the target object of *this.
> Throws: bad_function_call if !*this; otherwise, any exception thrown by the target object.

这里的 INVOKE<R>(f, std::forward<ArgTypes>(args)...) 明确要求 `f` 必须是一个 lvalue。而如果这里写成 INVOKE<R>(std::forward<F>(f), std::forward<ArgTypes>(args)...)，那么才说明 `f` 既可以是 lvalue 也可以是 rvalue。

因此，如果一个 function object 的 `operator()` 函数具有 rvalue­reference qualified，std::function 是没办法调用的：

```cpp
struct FuncWithoutQualified {
  void operator()() {}
};
struct FuncWithLValueQualified {
  void operator()() & {}
};
struct FuncWithRValueQualified {
  void operator()() && {}
};
int main() {
  FuncWithoutQualified obj1;
  FuncWithLValueQualified obj2;
  FuncWithRValueQualified obj3;

  std::function<void()> f1(obj1);
  std::function<void()> f2(obj2);
  // std::function<void()> f3(obj3); // compile error
  // std::function<void()&&> f4(obj3); // compile error
  return 0;
}
```

### Implementation details

我仔细翻了一下 LLVM 关于 std::function 的实现，发现了一个十分有趣的小细节：

```cpp
template <class _Rp, class... _ArgTypes>
class function<_Rp(_ArgTypes...)> {
  // ...

  template <class _Fp>
  using _EnableIfLValueCallable _LIBCPP_NODEBUG = __enable_if_t<
      _And<_IsNotSame<__remove_cvref_t<_Fp>, function>, __is_invocable_r<_Rp, _Fp&, _ArgTypes...>>::value>;

public:
  // ...
  template <class _Fp, class = _EnableIfLValueCallable<_Fp>>
  _LIBCPP_HIDE_FROM_ABI function(_Fp);

  // ...
}
```

可以看到，在 `__is_invocable_r` 的调用中，`_Fp` 是写成 lvalue 的，这里就限制了我们必然没办法用一个 rvalue 去调用这一个构造函数。

我们可以写一段简单的测试代码，尝试给 `std::is_invocable_r` 传入不同的 reference qualified：

```cpp
template <bool IsLvalue, class R, class... Args>
struct TestValueQualified {
  template <class T>
  using RawType = std::remove_cvref_t<T>;
  template <class T>
  using InvokeType = std::conditional_t<IsLvalue, RawType<T>&, RawType<T>&&>;
  template <class T>
  using IsValidCallable =
      std::enable_if_t<not std::is_same_v<RawType<T>, TestValueQualified> and
                       std::is_invocable_r_v<R, InvokeType<T>, Args...>>;

  template <class T, class = IsValidCallable<T>>
  TestValueQualified(T&&) {
    std::println("Test");
  }
};

struct FuncWithoutQualified {
  void operator()() {}
};
struct FuncWithLValueQualified {
  void operator()() & {}
};
struct FuncWithRValueQualified {
  void operator()() && {}
};

int main() {
  FuncWithoutQualified obj1;
  FuncWithLValueQualified obj2;
  FuncWithRValueQualified obj3;

  TestValueQualified<true, void> f1{obj1};
  TestValueQualified<true, void> f2{obj2};
  // TestValueQualified<true, void> f3{obj3}; // compile error
  TestValueQualified<false, void> f4{obj1};
  // TestValueQualified<false, void> f5{obj2}; // compile error
  TestValueQualified<false, void> f6{obj3};
  return 0;
}
```

结果显而易见，如果 `operator()` 具有 lvalue-reference-qualified，我们是没办法调用 `INVOKE(std::move(f), ...)` 的；而如果它具有 rvalue-reference-qualified，我们也同样没有办法调用 `INVOKE(f, ...)`。

# Summary

本文简单梳理了 std::function 的一些问题。Proposal 当中还有关于修复空间的探索，这一部分也相当有趣，之后我再简单梳理一下。另外，关于 std::function 的替代，也已经加入了 C++23/C++26，相关的 Proposal 也实在值得详细阅读。这些工作就交给明天的我吧。

关于 LLVM 当中 std::function 的实现，我个人倒是觉得写的相当的优雅。尽管 std::function 本身有许多问题，但这些问题在于它并不是 C++11 以及之后设计的，历史遗留问题必不可少，然而这并不妨碍我们学习它的实现细节。

