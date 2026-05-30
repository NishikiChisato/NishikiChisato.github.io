---
layout: post
title: Address of overloaded function
date: 2026-05-24 09:41 +0800
---

# The coincidence: The address of overloaded function

让我们从一个最为平常的场景开始说起。假如你写了一个函数，并且你想要将这个函数绑定到 `std::function` 用作某种 callback function 亦或是其他的行为，很自然地，我们会写出如下代码：

```cpp
static void func() {}

int main() {
  std::function<void()> f1 = &func;
  std::function<void()> f2 = func;
  return 0;
}
```

无论是哪一种写法，都是将 `func` 这个函数的地址赋值给 `std::function<void()>` 对象。我们只需要将 `std::function<void()>` 当成一个可以接受所有返回值为 `void`，参数列表为空的函数地址就行了

这段代码可以过编译，行为也如预期。我们既可以通过 `func()` 来直接调用，也可以通过 `f1` 和 `f2` 这两个变量来间接调用 `func`。无论我们是直接将一个函数赋值给 `std::function` 亦或是取其地址再赋值，在这个场景下并没有什么区别。在往后的讨论中，我们采取 `&func` 而不是 `func` 来进行讨论

TODO: 这里或许可以添加一下关于 `func` 和 `&func` 的区别，得找找标准草案才行

随着开发的进行，我们很有可能会出现需要为 `func` 提供另外一个重载的需求。换句话说，我们会添加如下的代码：

```cpp
static void func() {}
static void func(int) {}

int main() {
  std::function<void()> f1 = func;
  return 0;
}
```

麻烦的事情来了，一旦我们新增了一个函数，原有的代码直接就报错了。如果要修复原有的代码，我们必须使用 `static_cast`，即：

```cpp
static void func() {}
static void func(int) {}

int main() {
  std::function<void()> f1 = static_cast<void(*)()>(&func);
  return 0;
}
```

手动对所有的 `std::function<void()> f1 = func` 修改成 `std::function<void()> f1 = static_cast<void(*)()>(&func)`。如果模式相对固定，并且数量不多，我们可以采取 [sed](https://www.gnu.org/software/sed/manual/sed.html) 亦或是 [nvim](https://neovim.io/) 内置的 [pattern searches](https://neovim.io/doc/user/pattern/#pattern-searches) 来进行替换。但这依然是一个相当耗时的工作

因此出于工程亦或是现实上的考量，我们往往倾向于不去添加这个重载函数，而是另外使用一个新的名字。尽管如此，这依然是一个值得深究的问题，即：
- 为什么 `std::function<void()> f1 = &func` 会报错，它难道不应该去匹配 `void func()` 这个重载么
  - 该如何理解 `std::function<void()>`
- 假如我是一个库的设计者，我提供了一个通用的结构能够存储所有的函数地址，我能否有办法让使用者用一种更加简单的方式去指定自己想要传入的函数
  - 由于重载函数的判断依据是参数列表不同，我们能否只让使用者指定参数就能够得到预期的重载函数的地址呢？

# What exactly happens when handling an overloaded function?

当我们写下 `func` 或者 `&func` 时，这里的函数名本质上代表的是一个重载集(overload set)，而编译器需要依靠这个重载集出现的上下文当中的目标类型(target type) 来确定重载决议到哪个函数[^ref-over1]。而这里的目标类型，如果不存在的话，则会根据上下文来自动推导出来[^ref-over1.s3]

我们上面所采用的 `static_cast` 的做法，实际上是显示提供了一个目标类型[^ref-over1.6]。因此我们可以初步得出一个结论是，如果目标类型（包含推导出来的）能够匹配多个重载集当中的函数的话，那么代码应该不能过编译

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


[^ref-over1]: https://eel.is/c++draft/over.over#1
[^ref-over1.s3]: https://eel.is/c++draft/over.over#1.sentence-3
[^ref-over1.6]: https://eel.is/c++draft/over.over#1.6
