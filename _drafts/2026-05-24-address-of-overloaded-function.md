---
layout: post
title: Address of overloaded function
date: 2026-05-24 09:41 +0800
---

# 引入

最近在阅读 [sigslot](https://github.com/palacaze/sigslot) 代码的时候，我注意到了一个问题，那就是要如何去拿到指定的 overloaded member function 的地址。

本质上，我们希望去实现一个事件监听类型的库，即我们希望一个 `signal` 对象可以提供三种操作：
- connect: 将我们指定的函数绑定到这个对象身上
  - 这种函数可以大体分为两类，一类是可以直接调用的，例如: free function/static member function/lamdba；另一类是需要在对象身上调用的，例如: pointer to member function
- disconnect: 将我们指定的函数从这个对象身上解绑
  - 我们可以通过 `connect` 操作所返回的对象来实现解绑
  - 我们也可以通过手动传入一个函数（对于可以直接调用的函数），亦或是传入一个函数以及这个函数所涉及到的对象（对于成员函数）
- fire: 调用这个对象身上所有绑定的函数

除了这些基本操作以外，我们还要求生命周期的自动管理，即当绑定到这个 `signal` 对象身上的函数所涉及到的对象 `target` 被销毁时，这个 `signal` 对象会自动删去对应的函数，否则这个函数调用在一个已经删除的对象身上是极度危险的。而反过来也同理，我们同样要求 `target` 会记录它绑定到了哪些 `signal` 对象，当这些 `signal` 对象被销毁时，`target` 也必须要更新自己的内部记录。

换句话说，`signal` 对象需要去跟踪不同的 `target` 对象，这保证了每次函数调用的合法性；而每个 `target` 对象则需要去记录自己在哪些 `signal` 身上绑定了函数，用于在 `target` 销毁时能够找到这些 `signal`，只有这样这些 `signal` 对象才能够删去对应的函数。

我们的重点在于，如何将不同类型的函数以一种统一的形式存储起来

很自然地，我们会想到用 `std::function` 来表示一个通用的可调用的函数，普通函数可以直接对类型相同的 `std::function` 对象进行赋值，而成员函数则可以通过 lamdba 的封装来实现这一点。这种做法可以表示几乎所有函数，比较麻烦的是 overloaded function，但我们依然有办法表示：

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

这种做法比较繁琐，要么让用户麻烦一些，采取 `static_cast` 的形式去手动指定，亦或是使用 lamdba 来做一个 wrapper。

然而，我们一般不会采取 `std::function` 的方案。一个很重要的原因在于，我们很难对一个指定的函数做 `disconnect` 的操作，一旦我们将用户传入的函数的地址套上 `std::function` 的外衣，除了通过 `connect` 操作返回的对象以外，我们完全没有办法再次删除它，因为 `std::function` 的[compare function](https://en.cppreference.com/cpp/utility/functional/function/operator_cmp)只支持跟 `std::nullptr_t` 进行比较

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
  auto p2 = overload<>(&Foo::foo); // compile err
  return 0;
}
```

这段代码我最开始看到 `overload<>(&Foo::foo)` 的时候在想，我没有指定 template argument，那第一个 [pack](https://en.cppreference.com/cpp/language/pack) 难道就不应该是 `void` 么，那应该去匹配不带参数的版本才对呀。

这似乎是最为直观的想法，但实际上模板的参数推导并不是这么工作的......

# Deducing template arguments from function call

在 [over.over](https://eel.is/c++draft/over.over) 里详细说明了对 overloaded function 的处理流程：

> [over.over#1](https://eel.is/c++draft/over.over#1)
> An expression that designates an overload set S and that appears without arguments is resolved to a function, a pointer to function, or a pointer to member function for a specific function that is chosen from a set of functions selected from S determined based on the target type required in the context (if any), as described below. The target can be

如果用上面的例子来说，`Foo::foo` 就是一个 overload set，而前面的 `&` 操作符则是可选的。这个 overload set 对应了多个函数，我们需要依据 `target` 才能确定这个 overload set 是 resolve 到哪个函数

当我们用一个 pointer to function 去接受这个 overload set 的时候，这个 pointer 的类型就是这里的 `target type`。而我们上面采取 `static_cast` 去手动指定我们想要哪个函数的方式，也是其中一种 [target](https://eel.is/c++draft/over.over#1.6)

然而问题在于，我们这里是采取用一个函数模板来接受这个 overload set，我们还需要看看模板参数的推导流程才能知道这里发什么了什么。

# The deduction from function call

[temp.deduct.call](https://eel.is/c++draft/temp.deduct.call) 这一章详细描述了函数调用时的 template argument 的推导。我们的关注点在 [temp.deduct.call#6](https://eel.is/c++draft/temp.deduct.call#6) 这里，在我们上面的例子当中，overload set 里面并没有 template function，因此这不是 non-deduced context；我们的关注点在于 [temp.deduct.call#6.2](https://eel.is/c++draft/temp.deduct.call#6.2)

> [temp.deduct.call#6.2](https://eel.is/c++draft/temp.deduct.call#6.2)
> If the argument is an overload set (not containing function templates), trial argument deduction is attempted using each of the members of the set whose associated constraints ([temp.constr.constr](https://eel.is/c++draft/temp.constr.constr)) are satisfied. If all successful deductions yield the same deduced A, that deduced A is the result of deduction; otherwise, the parameter is treated as a non-deduced context.

在上面的例子 `overload<>(&Foo::foo)` 当中，当我们用 overload set 当中的每个成员去尝试做 argument dudection 的时候，我们所推导出来的 argument 并不唯一：

对于 `void Foo::foo(int)` 而言，推导出来的两个模板参数分别为 `Args = int, C = Foo`，而对于 `void Foo::foo()` 而言，推导出来的两个模板参数分别为 `Args = {}, C = Foo`。由于这里的 template argument 并不涉及 non-deduced context，因此这两个 deduction 都是成功的，但是它们得出了两个不同的结果，因此这里的 template parameter 被认为是 non-deduced context

> 如果函数的声明语句为 `void func(int lhs, int rhs)`，而该函数的调用的表达式为 `func(val1, val2)`。那么调用表达式当中的 `val1` 和 `val2` 是 `argument`，而声明语句当中的 `lhs` 和 `rhs` 则是 `parameter`
{: .prompt-tip }

`overload<>(&Foo::foo)` 推导失败的原因在于，尽管第一个 template parameter 是一个 pack，但不手动指定 template parameter 并不代表这这里的 pack 就代表着 empty，而是代表所有的 template arguments 都需要由编译器来推导。

TODO: 这个推导我不是很满意，得再多找找资料才行


