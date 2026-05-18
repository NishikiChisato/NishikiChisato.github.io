---
layout: post
title: 'Member object pointer: from the perspective of the ABI'
date: 2026-04-26 09:37 +0800
---

# Intro

In C, a pointer essentially represents the memory address of an entity (such as variable, function or array). C++ shares this exact mental model, with one notable exception: pointers to members.

The underlying mechanism of C pointers, providing a indirect way to access variables, is straightforward, and this same mental model broadly applies to C++.

Historically, C++ began as "C with classes," introducing the paradigm of encapsulation. This allows us to bundle related data together with the methods manipluate them.

After applying these encapsulation, we introduce the meaning of classes, and the object instanced from its class named object.

The address of object have no difference with address of entities from C. But something changed from the class perspective.

The issue is that if we want to access data member, we must through the object. The data memebr cannot exist without the object alive!

But here is our demand, if we want to have a way to access the same member data across multiple object, how can we do? From the traditional perspective, we must write the name of member data down, then we can access its value.

It's so curbersome, we need a way to access member data from class without the needing of object itself. This comes to member object pointer.

# Underlying mechanism

## POD data type

If the class itself is POD data type, this is the easist scenario. The underlying representation of member data type is `std::ptrdiff_t`, according from the [ItaniumABI](https://itanium-cxx-abi.github.io/cxx-abi/abi.html#data-member-pointers):

> A data member pointer is represented as the data member's offset in bytes from the address point of an object of the base type, as a ptrdiff_t.
> 
> A null data member pointer is represented as an offset of -1.

The meaning of data memebr pointer is the offset in bytes from the start address of an object of the base type, and the null value for data member pointer is `-1`, since the `0` should be used to represented the zero offset in class representation.

Here is an simple example:

```cpp
#include <print>
template <typename T>
concept IsMemberDataPointer = std::is_member_object_pointer_v<T>;
template <IsMemberDataPointer Ptr>
auto ToRawVal(Ptr ptr) {
  using RawType = std::conditional_t<sizeof(ptr) == sizeof(std::ptrdiff_t),
                                     std::ptrdiff_t, std::uint32_t>;
  return std::bit_cast<RawType>(ptr);
}

template <IsMemberDataPointer... Ptrs>
void PrintMemberDataPointers(Ptrs... ptrs) {
  auto print_signle = [is_first = true](auto ptr) mutable {
    auto val = ToRawVal(ptr);
    if (is_first) {
      std::print("{}", val);
      is_first = false;
    } else {
      std::print(", {}", val);
    }
  };

  (print_signle(ptrs), ...);
  std::println("");
}

struct A {
  std::uint32_t a1;
  std::uint32_t a2;
  std::uint32_t a3;
};

int main() {
  auto p1 = &A::a1;
  auto p2 = &A::a2;
  auto p3 = &A::a3;

  PrintMemberDataPointers(p1, p2, p3);
}
```

If we compile it with the C++23 standard, we would get the following output:

```fish
hotaru@MinazukideMacBook-Air ~/workspace/ItaniumABI (main)
❯ clang++ -std=c++23 test.cc -o test
hotaru@MinazukideMacBook-Air ~/workspace/ItaniumABI (main)
❯ ./test
0, 4, 8
```

Despite we don't have a way to directly print the value in data member pointer, but we can dump its memory layout by `std::bit_cast`, and then prints its value.

This is the most easist scenario, where we don't involve inheritance. Besides, the comparison for data member pointer rules is as follows, according to the [draft](https://eel.is/c++draft/expr.eq#4):
- (4.1) If two pointer are both null member pointer value, they compare equal.
- (4.2) If only one of them are null member pointer value, they compare uneaual.
- (4.5) If both refer to the members of the same union, they compare equal.

Note that we can only compare equality for data member pointer, we cannot apply relational operators to data member pointer, as described in [expr.rel](https://eel.is/c++draft/expr.rel#4):
- Two pointers point to the different elements of the same array can be compare greater.
- Two pointer point to the non-static data member in the same object can be compare greater.
- Otherwise, they cannot be compared greater then the other.

This might seems counterintuitive at first glance, because intuitively we would convert the valuee of the two pointers(which are address) into numerical value and then compare them, which is essentially comparing the higher address and lower address. However, since this is how the C++ standard defines it, we can only sat that comparing two data member pointers is an undefined behavior.

## With Inheritance

Things get much more intersting when we consider inheritance into account.
