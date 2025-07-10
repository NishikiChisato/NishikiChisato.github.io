---
layout: post
title: "[Lua] Hash for floating-point in Lua"
date: 2025-07-10 20:12 +0800
categories:
- Lua Implementation
tags:
- Lua Implementation
- Hash Method
---

<!--toc:start-->
- [Hash for Float](#hash-for-float)
<!--toc:end-->

## Hash for Float

This function is going to create a integer hash value for floating-point input, and this artical is about to dive into the details.
The calculation of hash for floating-point conceptlly is pretty intuitive. The core expression is `n = frexp(n, &i); return (n * INT_MAX) + i;`
But, there are several subtleties to be considered...

Main function defines here:

```c
/*
** Hash for floating-point numbers.
** The main computation should be just
**     n = frexp(n, &i); return (n * INT_MAX) + i
** but there are some numerical subtleties.
** In a two-complement representation, INT_MAX does not has an exact
** representation as a float, but INT_MIN does; because the absolute
** value of 'frexp' is smaller than 1 (unless 'n' is inf/NaN), the
** absolute value of the product 'frexp * -INT_MIN' is smaller or equal
** to INT_MAX. Next, the use of 'unsigned int' avoids overflows when
** adding 'i'; the use of '~u' (instead of '-u') avoids problems with
** INT_MIN.
*/
#if !defined(l_hashfloat)
static int l_hashfloat (lua_Number n) {
  int i;
  lua_Integer ni;
  n = l_mathop(frexp)(n, &i) * -cast_num(INT_MIN);
  if (!lua_numbertointeger(n, &ni)) {  /* is 'n' inf/-inf/NaN? */
    lua_assert(luai_numisnan(n) || l_mathop(fabs)(n) == cast_num(HUGE_VAL));
    return 0;
  }
  else {  /* normal case */
    unsigned int u = cast_uint(i) + cast_uint(ni);
    return cast_int(u <= cast_uint(INT_MAX) ? u : ~u);
  }
}
##endif
```

Some auxiliary function defines here:

```c
/*
@@ lua_numbertointeger converts a float number with an integral value
** to an integer, or returns 0 if float is not within the range of
** a lua_Integer.  (The range comparisons are tricky because of
** rounding. The tests here assume a two-complement representation,
** where MININTEGER always has an exact representation as a float;
** MAXINTEGER may not have one, and therefore its conversion to float
** may have an ill-defined value.)
*/
#define lua_numbertointeger(n,p) \
  ((n) >= (LUA_NUMBER)(LUA_MININTEGER) && \
   (n) < -(LUA_NUMBER)(LUA_MININTEGER) && \
      (*(p) = (LUA_INTEGER)(n), 1))


#define luai_numeq(a,b)         ((a)==(b))
#define luai_numisnan(a)        (!luai_numeq((a), (a)))

/* type casts (a macro highlights casts in the code) */
#define cast(t, exp)	((t)(exp))
#define cast_num(i)	cast(lua_Number, (i))
#define cast_uint(i)	cast(unsigned int, (i))
```

There are several key points to be considered:

- How to check if a floating-point number is inf/-inf/nan:

```c
double inf = INFINITY;
double ninf = -INFINITY;
double nan = NAN;

/* after including math.h header, we can directly use built-in macro */
bool c1 = isinf(inf);
bool c2 = isinf(ninf);
bool c3 = isnan(nan);

/* or, we can manually write a macro to check it */
#define isinf(n) (fabs(n) == HUGE_VAL) /* use built-in macro to represent int */
#define isnan(n) (!((n) == (n))) /* and equality check for nan results faile */
```

- Implication of lua_numbertointeger

The main role of this function is checking if a integer number within the range of integer(which is `long long`) and converting it to integer.
Take an example of `long long` for integer, `LLONG_MAX` **can not be exactly represented by double** but `LLONG_MIN` does. Besides, 
the absolute value of `LLONG_MIN` is **one greater** than `LLONG_MAX`. Therefore, if we want to check if a integer(say `num`) to be converted 
within the range of `long long`, we can manually check it by `num >= double(LLONG_MIN) && num < double(-LLONG_MIN)`.

- Implication of `cast_int(u <= cast_uint(INT_MAX) ? u : ~u)`

Firstly, `u` is `unsigned int`, which is always greater than and equal to zero. By contrast, `int` has negative value. Secondly, if `u` is nun-negative 
value, we just return it. If `u` is negative value, we cannot directly return `-u`, since `abs(INT_MIN) = abs(INT_MAX) + 1`, it will cause overflow.
Therefore, we just flip all bits for `u` but not adding one(negative a negative value is equvalent to fliping all bits and adding one).
