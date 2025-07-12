---
layout: post
title: "[C++ Primer] Part I: The Basics"
categories: ["C++ Primer"]
tags: ["C++"]
---

<!--toc:start-->
- [Compound Type](#compound-type)
  - [Reference and Pointer](#reference-and-pointer)
    - [Reference & Pointer and const](#reference-pointer-and-const)
      - [Reference](#reference)
      - [Pointer](#pointer)
  - [The auto Type Specifier](#the-auto-type-specifier)
  - [Summary](#summary)
  - [The decltype Specifier](#the-decltype-specifier)
- [TODO](#todo)
<!--toc:end-->

> This posts just a quick reference for the part of this book
{: .prompt-info }

## Compound Type

C++ has several compound type, two of which is reference and pointer, we will cover in this section.

A declarations is a **base type** followed by a list of **declarators**. Each declarator names a variable and gives the variable a type that is related to the base type.

### Reference and Pointer

When we define a reference, instead of coping the initializer's value, we **bind** the reference to its initializer. Once initialized, a reference remains bound to its initializer. There is no way to rebind a reference to refer to different object. Because there is no way to rebind a reference, references must be initialized.

There are two exceptions that we will cover in the next section, the type of a reference and the object to which the reference refers must match exactly. Similarly, there are two exceptions that we will cover in the next section, the type of a pointer and the object to which the pointer refers must match exactly. These two exceptions are the same thing.

```cpp
// reference
int ival = 1;
double dval = 0.1;
int &ri = ival;
// int &ri2 = dval; // error
double &rd = dval;

// pointer
int ival = 1;
double dval = 0.1;
int *ri = &ival;
// int *ri2 = &dval; // error
double *rd = &dval;
```

#### Reference & Pointer and const

##### Reference

The first exception is that we can initialize a *reference to const* from any expression that can be converted to the type of the reference. In particular, we can bind a *reference to const* to a nonconst object, a literal, or more general expression:

```cpp
int ival = 1;
const int &ri1 = ival;
const int &ri2 = 2;
const int &ri3 = ival * 2;
// int &ri4 = ival * 2; // error
```

Let's we consider what happens when we bind a reference to a object with different type.

```cpp
double dval = 3.14;
const int &ri = dval;
```

Here `ri` refers to an `int`. Operations on `ri` will be integer operations, but `dval` is a floating-point value, not a integer. To ensure the object to which `ri` refers is an integer, the compiler transforms this code into something like:

```cpp
const int tmp = dval; // create a temporary object from double to int
const int &ri = tmp;  // bind to this temporary object
```

In this case, `ri` bound to a **temporary object**. A temporary object is an unnamed object created by compiler when it needs a place to store a result from evaluating an expression. So, for nonconst object, a literal, or general expression, the compiler will create a temporary object and bind it to *reference to const*.

> From C++ Primer:
> Now consider what could happen if this initialization were allowed but ri was not const. If ri weren’t const, we could assign to ri. Doing so would change the object to which ri is bound. That object is a temporary, not dval. The programmer who made ri refer to dval would probably expect that assigning to ri would change dval. After all, why assign to ri unless the intent is to change the object to which ri is bound? Because binding a reference to a temporary is almost surely not what the programmer intended, the language makes it illegal.
{: .prompt-info }

It's important to realize that a *reference to const* only restricts what we can do through that reference(we only can read from that reference, but not change it), but says nothing about the whether the underlying object itself is *const*. The underlying object might be nonconst, it also might be const.

```cpp
int ival = 1;
const int cival = 2;
const int &ri1 = ival;
const int &ri2 = cival;
int &ri3 = ival;
// int &ri4 = cival; // error
```

##### Pointer

Like a *reference to const*, a *pointer to const* says nothing about whether the object to which the pointer points is const. Defining a pointer as a *pointer to const* only affect what we can do with that pointer, instead of the object to which the pointer points.

Unlike references, pointers are objects. Hence, as with any other object type, we can have a pointer that is itself *const*. A *const pointer* must be initialized, and once initialized, its value may not be changed.

It's important to realize that whether we can change the object to which pointer points depends entirly on the type of that object, instead of pointer itself. For example, if the underlying object is a const object, we can't change it through either *const pointer* or *pointer to const* (although the latter itself cannot). if the underlying object is a nonconst object, we can change it through either *const pointer* or object itself.

Let's we talk about top-level const and low-level const. The reason why we introduce these two terms is that there are two indenpendent questions about whether a pointer is const and whether the object to which pointer points is const.

We use the term *top-level const* to indicate that the pointer itself is a const, while the object to which pointer points is a const, we use the term *low-level* to indicate it. More generally, top-level const indicates that an object itself is const, and it can appear in any object, while low-level const appears in the base type of compound type such as pointer and reference.

For these two terms, we have:

- For any object(including pointer, excluding reference), const is top-level
- For pointer, const appears in modifier is top-level, const appears in base type is low-level
- For reference, const in reference always low-level

The distinction between low-level and top-level matters when we copy an object. When we copy an object, top-level const can be ignored:

```cpp
int i = 1;        // top-level const
const int ci = 2; // top-level const
const int *pi = &ci;  // low-level const
const int *const cpi = pi;  // right-most is top-level const, left-most is low-level const

i = ci;     // ok
pi = cpi;   // ok
```

On the other hand, low-level is never ignored. When we copy an object, both objects must have the same low-level const qualification or there must be a conversion between the type of the two objects.

```cpp
int i = 1;                  // top-level const
const int ci = 2;           // top-level const
const int *pi = &ci;        // low-level const
const int *const cpi = pi;  // right-most is top-level const, left-most is low-level const
const int &cri = i;         // low-level const

i = ci;     // ok
pi = cpi;   // ok

// int *p = pi;     // error: pi has low-level const but p doesn't
// int &ri = cri;   // error: can't bind an ordinary reference(doesn't have low-level const) to low-level const
```

### The auto Type Specifier

There are two rules for type-deduction for `auto` specifier. First, when we use reference, we are really use the object to which the reference refers. In particular, when we use a reference as an initializer in `auto`, the initializer is corresponding object. The compiler use the **object's type for auto's type deduction**. Second, `auto` ordinarily ignores top-level const, but low-level const are kept.

```cpp
#include <iostream>
#include <string>
#include <cxxabi.h>
#include <memory>
#include <typeinfo>

template <typename T>
std::string type_name() {
    typedef typename std::remove_reference<T>::type TR;
    std::unique_ptr<char, void(*)(void*)> own(
        abi::__cxa_demangle(typeid(TR).name(), nullptr, nullptr, nullptr),
        std::free
    );
    std::string r = own != nullptr ? own.get() : typeid(TR).name();
    if (std::is_const<TR>::value)
        r += " const";
    if (std::is_volatile<TR>::value)
        r += " volatile";
    if (std::is_lvalue_reference<T>::value)
        r += "&";
    else if (std::is_rvalue_reference<T>::value)
        r += "&&";
    return r;
}

int main() {
  int i = 1;      // top-level const
  int &ri = i;    // top-level const
  auto a = ri;    // a is int

  const int ci = 1, &rci = ci;
  auto b = ci;    // b is int(top-level const is ignored)
  auto c = rci;   // c is int(rci is reference to ci(despite it's reference to const), which is top-level const)
  auto d = &i;    // d is int*
  auto e = &ci;  // e is const int*(& of a const object is low-level const)

  std::cout << type_name<decltype(a)>() << std::endl;
  std::cout << type_name<decltype(b)>() << std::endl;
  std::cout << type_name<decltype(c)>() << std::endl;
  std::cout << type_name<decltype(d)>() << std::endl;
  std::cout << type_name<decltype(e)>() << std::endl;

  return 0;
}
```

So, if we want the deducted type to have top-level const, we should explicitly specify:

```cpp
const auto f = ci;  // deducted type of ci is int, f has type const int
```

We can also specify that we want a reference or a pointer to auto-deducted type, the **normal initialization** rules still apply:

For reference:

```cpp
int main() {
  int i = 1;      // top-level const
  int &ri = i;    // top-level const

  const int ci = 1, &rci = ci;
  auto &a = i;    // a is int &
  auto &b = ri;   // b is int &
  auto &c = ci;   // deducted type of ci is const int(if c doesn't have &, the top-level const is ignored), so c is const int &
  auto &d = rci;  // similarly, d is const int &

  const auto &ca = i;   // const auto is base type, and &ca is declarators, so ca is reference to const, the type of it is const int &
  const auto &cb = ri;  // similarly, cb is const int &
  const auto &cc = ci;  // similarly, cc is const int &
  const auto &cd = rci; // similarly, cd is const int &

  std::cout << type_name<decltype(ca)>() << std::endl;
  std::cout << type_name<decltype(cb)>() << std::endl;
  std::cout << type_name<decltype(cc)>() << std::endl;
  std::cout << type_name<decltype(cd)>() << std::endl;

  return 0;
}
```

For pointer:

```cpp
int main() {
  int i = 1;      // top-level const
  int &ri = i;    // top-level const

  const int ci = 1, &rci = ci;
  auto &a = i;    // a is int &
  auto &b = ri;   // b is int &
  auto &c = ci;   // deducted type of ci is const int(if c doesn't have &, the top-level const is ignored), so c is const int &
  auto &d = rci;  // similarly, d is const int &

  const auto *pa = &i;        // const auto is base type, and *pa is declarators, so pa is pointer to const, the type of it is const int *
  const auto *const cpa = &i; // left-most const is low-level const, right-most const is top-level const. so, cpa is a const pointer to const object
  const auto *pb = &ri;       // similarly, pb is const int *
  const auto *pc = &ci;       // similarly, pc is const int *
  const auto *pd = &rci;      // similarly, pd is const int *

  std::cout << type_name<decltype(pa)>() << std::endl;
  std::cout << type_name<decltype(cpa)>() << std::endl;
  std::cout << type_name<decltype(pb)>() << std::endl;
  std::cout << type_name<decltype(pc)>() << std::endl;
  std::cout << type_name<decltype(pd)>() << std::endl;

  return 0;
}
```

### Summary

We can use a declaration, which is a **base type** followed by a list of **declarators**, to declare a compound type:

```cpp
int a = 1;    // base type is int(not compound type).
int *b = &a;  // base type is int, declarators is *b, * is modifier and b is variable name. So b is a pointer, which points to int(base type).
const int *c = b; // base type is const int. So, c is a pointer, which points to const int.
const int *const d = b; // the left-most const is a part of base type, the right-most const is a part of declarators. Hence, base type is const int, declarators is *const d; * const is modifier, means d is a const pointer.
int &e = a; // base type is int, declarators is &e, & is modifier and e is variable name. So e is a reference, which refers to int(base type).
const int &f = a; // base type is const int. So f refers to const int(base type). in this case, we can copy a nonconst object into a const object.
```

If we introduce `auto` specifier, `auto` should be considered into a part of base type(The example is above).

### The decltype Specifier

This section is intuitive, I directly refer from the original book:

> From C++ Primer:
> Sometimes we want to define a variable with a type that the compiler deduces from an expression but do not want to use that expression to initialize the variable. For such cases, the new standard introduced a second type specifier, `decltype`, which returns the type of its operand. The compiler analyzes the expression to determine its type but does not evaluate the expression.
> The way `decltype` handles top-level const and references differs subtly from the way auto does. When the expression to which we apply `decltype` is a variable, `decltype` returns the type of that variable, **including top-level const and references**:

```cpp
int main() {
  int i = 1, &ri = i;
  const int ci = 1, &rci = ci;

  decltype(i)   a = i;
  decltype(ri)  b = i;
  decltype(ci)  c = i;
  decltype(rci) d = i;

  std::cout << type_name<decltype(a)>() << std::endl;
  std::cout << type_name<decltype(b)>() << std::endl;
  std::cout << type_name<decltype(c)>() << std::endl;
  std::cout << type_name<decltype(d)>() << std::endl;

  return 0;
}
```

When we apply `decltype` to an expression that is not a variable, we get the type that that expression yields, and some expressions will cause `decltype` to yield a reference type. Generally speaking, `decltype` returns a reference type for expression that yield objects that can stand on the left-hand side of the assignment:

```cpp
int main() {
  int i = 1, *pi = &i;
  decltype(pi)  a = nullptr;
  decltype(*pi) b = i;

  std::cout << type_name<decltype(a)>() << std::endl;
  std::cout << type_name<decltype(b)>() << std::endl;

  return 0;
}
```

Enclosing a variable's name in parenthese affects its type when used with `decltype`. The compiler treats a variable name in parentheses, like `decltype(var)`, as an expression. If a variable can be considered a expression, it means that it can stand on the left-hand side of assignment. Hence, in this case, `decltype` yields a reference to that type.

Since variable's name can be assigned, it can be treated as a reference. On the other hand, we may only want to get the type of that variable. Hence, `decltype` gives two different ways to handle it, one for ordinary type, another for reference:

This gives `decltype` two distinct behaviors:
- When given a plain variable name, `decltype(var)`, it yields the variable's **decleared type**.
- when given a parenthesized variable name, `decltype((var))`, it yields a **reference to that type**, because `(var)` is treated as an lvalue expression.

```cpp
int main() {
  int i = 1;
  decltype(i)   a = 1;
  decltype((i)) b = i;

  std::cout << type_name<decltype(a)>() << std::endl;
  std::cout << type_name<decltype(b)>() << std::endl;

  int c = 1;
  (c) = 2;  // c is expression in this case
  std::cout << c << std::endl;

  return 0;
}
```

## TODO

- constexpr and constant expressions (p. 58)
