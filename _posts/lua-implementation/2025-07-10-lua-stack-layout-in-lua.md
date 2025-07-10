---
layout: post
title: "[Lua] Stack layout in Lua"
date: 2025-07-10 20:17 +0800
categories:
- Lua Implementation
tags:
- Lua Implementation
- Lua VM
---

<!--toc:start-->
- [Stack Layout](#stack-layout)
<!--toc:end-->

## Stack Layout

In the `lua_State` structure, there are three pointers(`L->stack`, `L->stack_last` and `L->top`) 
that relate to stack management. Additionally, there is a structure representing information 
about the current called function, which is `CallInfo* ci`. In the `CallInfo` structure, there 
are two pointers(`ci->func` and `ci->top`) that also relate to stack management. Here, we will 
dive into the layout of entire stack and show the internal meaning of these pointers.

`L->stack` and `L->stack_last` used to represents the start of and the end of the total 
Lua stack area, respectively. The sizo of total stack may shrink or grow as needed, 
depending on the stack's usage.

`ci->func` points to the stack position where the function frame starts, and `ci->top` points to 
the **maximum stack position that current function can use**. These two pointers define the 
function's stack frame.

`L->top` represents the current position of the stack's top, which is where a new values are pushed. 
This pointer only used to track the active top of current stack, so its value can be greater then 
and equal to `ci->func` but less then `ci->top`(it cannot exceed `ci->top`).

The relationship of these pointer is `L->stack <= ci->func < L->top <= ci->top < L->stack_last`. 

so, we have:

- `L->top - (ci->func + 1)` represents the number of elements that currently exists in stack within the function's frame.
- `L->top - (ci->func + 1)` represents the index of top of stack. If the stack is empty, we have `L->top == ci->func + 1`.
- `ci->top - L->top` represents the unused space of current function's frame.
