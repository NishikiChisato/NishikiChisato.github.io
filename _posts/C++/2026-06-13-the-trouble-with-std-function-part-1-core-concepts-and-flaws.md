---
layout: post
title: "The Trouble with std::function - Part 1: Core Concepts and Flaws"
date: 2026-06-13 14:31:00 +0800
lang: en
ref: the-trouble-with-std-function
permalink: /en/posts/the-trouble-with-std-function/
categories:
  - C++
tags:
  - C++
  - std::function
  - C++11
---

# Introduction

After reading a lot of material about `std::function`, I wanted to briefly summarize it. This article will briefly outline the problems that exist with `std::function`. Even though many of the problems with `std::function` have been resolved today in C++23 and even C++26, the process is still worth reviewing. This article will focus heavily on the proposal [N4159](https://wg21.link/n4159), clarifying the problems with `std::function` as I understand them.

# Definitions

Before we begin our discussion, we need to clarify some definitions:
- A [function object type](https://eel.is/c++draft/function.objects#general-1.sentence-1) is an object type that can be the type of the postfix-expression in a function call.
- A [function object](https://eel.is/c++draft/function.objects#general-1.sentence-2) is an object of a function object type.
- A [callable type](https://eel.is/c++draft/function.objects#func.def-3) is a function object type or a pointer to member.
- A [callable object](https://eel.is/c++draft/function.objects#func.def-4) is an object of a callable type.
- The [std::function](https://eel.is/c++draft/function.objects#func.wrap.func.general-1) class template provides polymorphic wrappers that generalize the notion of a function pointer. Wrappers can store, copy, and call arbitrary callable objects, given a call signature.

In addition, we can subdivide the callable type into:
- lvalue-callable: is a non-const lvalue of that type
- rvalue-callable: is a non-const rvalue of that type
- callable contains lvalue-callable and rvalue-callable
- const-callable contains const lvalue-callable and const rvalue-callable

# The trouble with std::function

## Const-correctness

Since `std::function` is a product of the C++98 era, it worked perfectly well before C++11. However, C++11 introduced `lambda`. We can pass a `lambda` to a `std::function`, and the biggest difference between this `lambda` and a traditional function is that it can store state internally. This led to a series of new problems. The problems with `std::function` discussed in this article also focus mainly on this scenario, that is, the problems caused by passing a `function object` to `std::function`.

If we look at the [operator()](https://eel.is/c++draft/function.objects#lib:function,invocation) function of `std::function`, we will find that this function is declared as `const`. This means that this function must not modify the internal state of a `std::function`.

Intuitively, our understanding of value types modified by `const` is generally deep const, meaning that as long as this object is `const`, we cannot modify its state. However, the `const` of composite types has two semantics: deep const and shallow const. The former is used to indicate that we cannot modify the object pointed to by this object through this object; the latter indicates that we cannot modify the object itself:

```cpp
// deep const
const int v1 = 1;

// deep const
const int* ptr1 = nullptr;

// shallow const
int* const ptr2 = nullptr;
```

When we pass a `function object` to an `std::function`, regardless of whether this `function object` is nominally a member of that `std::function`, intuitively it should be understood as its member. This `function object` will follow the copying of the `std::function` to copy, move to move, and destroy to destroy.

Therefore, when we call a non-const `std::function`, we believe it can freely modify the internal state of that `function object`, but once we call a `const` `std::function`, we expect it should not modify the internal state of the `function object`.

This is where the contradiction lies. `std::function` only provides one `operator()` function, and this function is also declared as `const`; it does not provide a non-const `operator()` function at all. This means that when a non-const `std::function` is called, since we expect it to modify the internal state of the `function object`, and since it can only call the `const` `operator()` function, it must modify the internal state in a `const` context:

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

In the above code, the constness of `std::function` itself will not have any effect on the result of the call. Regardless of whether it is `const` or not, it can call a `function object` that can modify its own internal state.

Besides this, there is another problem. [res.on.data.race](https://eel.is/c++draft/res.on.data.races#2) has this passage:

> A C++ standard library function shall not directly or indirectly access objects accessible
> by threads other than the current thread unless the objects are accessed directly or indirectly
> via the function's arguments, including this.

The intuitive understanding is that the standard library should not access a non-const object directly or indirectly in a multi-threaded context. In other words, if the object is `const`, then even in a multi-threaded context, the standard library can freely access the object directly or indirectly.

And since even a `const` `std::function` will essentially modify its own internal state, this rule of the standard does not work for `std::function`.

In other words, if I access a `const` `std::function` in a multi-threaded context, it will inevitably cause a data race problem.

## Shallow const

There are some classes in C++ that have shallow const. Since shallow const is a semantic property possessed by references, these classes themselves are often used as references, namely pointers, smart pointers, iterators, and references:
- They have shallow copy semantics: for copies of these objects, the resulting objects all point to the same underlying object.
- They have shallow const semantics: these objects cannot modify the underlying object they reference, but modifications to the underlying object are unrestricted.

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

But these two properties cannot be applied to `std::function`. The `operator()` of `std::function` has the property of shallow const, because it can freely modify the state of the `function object`, but it cannot call other `function objects`.

However, `std::function` provides a `target()` function, which can directly access the memory block of the object passed to `std::function`. In other words, we can use this function to modify the `function object` stored in `std::function`:

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

We initially created two objects, `obj1` and `obj2`. If we know the type of the object stored inside `std::function`, then we can get the address of this object directly through the `target()` function. If the `std::function` itself is non-const, then we can use this `target()` function to modify the address inside it (refer to the example below). In the above example, we declared the `std::function` as const because we need to observe the const semantics of `target()`.

Actually, `std::function` provides two overloads, and the overload with const has deep const semantics, meaning I cannot modify the memory block obtained through `target()`.

This design is very fragmented, which is also the cause of many problems. For a `const std::function`, the const of its `operator()` function behaves as shallow const, while its `target()` function behaves as deep const. And the behaviors of these two functions are exactly opposite, that is, the role of `operator()` is to operate on the internal members of `std::function`, while the role of `target()` is to acquire the internal members of `std::function`.

If our `std::function` is declared as non-const, then we can modify its internal members through this `target()` function:

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

Even if we don't use a `function object`, this `target()` will have the same problem when facing a free function:

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

`std::function` itself supports copy. Its copy-ctor's [Postconditions](https://eel.is/c++draft/function.objects#func.wrap.func.con-3) requires its `target()` to be copyable. Therefore, `std::function` cannot be used with a move-only `function object`, that is:

```cpp
int main() {
  auto ptr = std::make_unique<int>(1);
  auto fn = [ptr = std::move(ptr)]() { return static_cast<bool>(ptr); };
  // std::function<int()> func(fn); // compile error
  return 0;
}
```

At first glance, this might seem like a feature of `std::function`. But in fact, this goes against the definition of `std::function` in the standard. `std::function` requires being able to call any callable object. Obviously, the move-only `function object` here is a callable object, and it should rightfully be callable by `std::function`. However, this point is actually not fatal, and we can also treat it as a feature. As stated in [N4159](https://wg21.link/n4159):

> std::function’s lack of support for non­copyable and non­lvalue­callable function objects could
> plausibly be treated as a feature request, but the const­correctness issue is an outright defect

## Non-lvalue-callable function objects

If we look at the definition of the `operator()` function of `std::function` in the standard:

> [func.wrap.func.inv](https://eel.is/c++draft/function.objects#lib:function,invocation)
> R operator()(ArgTypes... args) const;
> Returns: INVOKE<R>(f, std::forward<ArgTypes>(args)...), where f is the target object of *this.
> Throws: bad_function_call if !*this; otherwise, any exception thrown by the target object.

The `INVOKE<R>(f, std::forward<ArgTypes>(args)...)` here explicitly requires `f` to be an lvalue. If this were written as `INVOKE<R>(std::forward<F>(f), std::forward<ArgTypes>(args)...)`, then it would mean that `f` could be either an lvalue or an rvalue.

Therefore, if the `operator()` function of a `function object` is rvalue-reference qualified, `std::function` has no way to call it:

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

I carefully looked through LLVM's implementation of `std::function` and found a very interesting little detail:

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

It can be seen that in the call to `__is_invocable_r`, `_Fp` is written as an lvalue, which restricts us from using an rvalue to call this constructor.

We can write a simple test code to try passing different reference qualifiers to `std::is_invocable_r`:

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

The result is obvious. If `operator()` is lvalue-reference-qualified, we cannot call `INVOKE(std::move(f), ...)`; and if it is rvalue-reference-qualified, we also cannot call `INVOKE(f, ...)`.

# Summary

This article has briefly outlined some of the problems with `std::function`. The proposal also explores spaces for fixes, which is also quite interesting, and I will briefly summarize it later. In addition, alternatives to `std::function` have also been added to C++23/C++26, and the related proposals are really worth reading in detail. I'll leave these tasks for tomorrow's me.

Regarding the implementation of `std::function` in LLVM, I personally feel that it is written quite elegantly. Although `std::function` itself has many problems, these problems lie in the fact that it was not designed in C++11 and later, and historical legacy problems are inevitable. However, this does not prevent us from learning its implementation details.
