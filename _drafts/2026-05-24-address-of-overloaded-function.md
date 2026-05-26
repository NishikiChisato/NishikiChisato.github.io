---
layout: post
title: 重载函数的地址是什么东西
date: 2026-05-24 09:41 +0800
---

# 引入

最近在阅读 [sigslot](https://github.com/palacaze/sigslot) 代码的时候，我注意到了一个问题，那就是要如何去拿到指定的 overloaded member function 的地址。

本质上，我们希望去实现一个 event listen 类型的库，即我们希望一个对象可以提供三种操作：
- connect: 将我们指定的函数绑定到这个对象身上
- disconnect: 将我们指定的函数从这个对象身上解绑
- fire: 调用这个对象身上所有绑定的函数

我们的重点在于，如何将不同类型的函数以一种统一的形式存储起来

很自然地，我们会想到用 `std::function` 来表示一个 generic function，而如果是 overloaded function，那么配合 lamdba 也可以将其解决，即：

```cpp
struct Foo {
  void foo() {}
  void foo(int v) {}
};

int main() {
  Foo obj;
  // std::function + static_cast
  std::function<void(Foo*)> func1 = static_cast<void(Foo::*)()>(&Foo::foo);
  std::function<void(Foo*, int)> func2 = static_cast<void(Foo::*)(int)>(&Foo::foo);

  // lamdba
  std::function<void()> func3 = [&obj]() {obj.foo();};
  std::function<void(int)> func4 = [&obj](int v) {obj.foo(v);};
  return 0;
}
```

然而，我们一般不会采取 `std::function` 的方案。

一个很重要的原因在于，我们很难对一个指定的函数做 `disconnect` 的操作，一旦我们将用户传入的函数的地址套上 `std::function` 的外衣，我们完全没有办法再次删除它，因为 `std::function` 的[compare function](https://en.cppreference.com/cpp/utility/functional/function/operator_cmp)只支持跟 `std::nullptr_t` 进行比较

而另外一个比较恶心的问题则是，我们无法去对生命周期进行管理。如果一个对象被销毁，他们我们需要自动删去所有涉及到它的成员函数，而 `std::function` 并没有提供这样的接口。

尽管你可以通过 `std::function::target` 这个函数去访问内部存储的类型，但这仅仅只是函数的类型，并且我们还需要在编译期就知道这个类型，无法在运行时自动拿到。

退一步来说，就算我们在运行时拿到了这个函数的地址，我们依然无法知道这个函数所涉及到的对象的地址，也就没有办法确定这个函数是在哪个对象身上调用的。

[sigslot](https://github.com/palacaze/sigslot) 所给出的 [solution](https://github.com/palacaze/sigslot#coping-with-overloaded-functions) 是额外写一个函数，将 overloaded member function 的地址给拿出来，这样就可以跟 free function 一样来处理了。

但作者给出的实现有些问题，以下代码是无法编译的：

```cpp
struct Foo {
  void foo() {}
  void foo(int v) {}
};

template <typename... Args, typename C>
constexpr auto overload(void (C::*ptr)(Args...)) {
    return ptr;
}

template <typename... Args>
constexpr auto overload(void (*ptr)(Args...)) {
    return ptr;
}

int main() {
  auto p1 = overload<int>(&Foo::foo);
  // auto p2 = overload<>(&Foo::foo); // compile err
  return 0;
}
```

最开始我看到 `overload<>(&Foo::foo)` 的时候在想，我没有指定 template argument，那第一个 [pack](https://en.cppreference.com/cpp/language/pack) 难道就不应该是 `void` 么，那应该去匹配不带参数的版本才对呀。

这似乎是最为直观的想法，但实际上模板的参数推导并不是这么工作的......

# How does template argument deduction work

