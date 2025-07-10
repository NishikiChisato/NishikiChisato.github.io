---
layout: post
title: "[Lua] Table implementation in Lua"
date: 2025-07-10 20:13 +0800
categories:
- Lua Implementation
tags:
- Lua Implementation
- Table Implementation
---

<!--toc:start-->
- [Design of Table](#design-of-table)
- [Operation for Table](#operation-for-table)
  - [Auxiliary function](#auxiliary-function)
    - [Finding main position of key](#finding-main-position-of-key)
    - [Get free position](#get-free-position)
    - [Array part](#array-part)
    - [Rehash](#rehash)
  - [Insert operation](#insert-operation)
  - [Get operation](#get-operation)
    - [Main get function & Generic get function](#main-get-function-generic-get-function)
      - [Main get function](#main-get-function)
      - [Generic get function](#generic-get-function)
    - [Next function](#next-function)
    - [Auxiliary get function](#auxiliary-get-function)
      - [Get integer from hash table](#get-integer-from-hash-table)
      - [Get short string from hash table](#get-short-string-from-hash-table)
      - [Get long string from hash table](#get-long-string-from-hash-table)
  - [Set function](#set-function)
  - [Finding a boundary](#finding-a-boundary)
    - [What's the real size for the array part](#whats-the-real-size-for-the-array-part)
    - [The implication of `ispow2realasize`](#the-implication-of-ispow2realasize)
<!--toc:end-->

## Design of Table

```c
/*
** Nodes for Hash tables: A pack of two TValue's (key-value pairs)
** plus a 'next' field to link colliding entries. The distribution
** of the key's fields ('key_tt' and 'key_val') not forming a proper
** 'TValue' allows for a smaller size for 'Node' both in 4-byte
** and 8-byte alignments.
*/
typedef union Node {
  struct NodeKey {
    TValuefields;  /* fields for value */
    lu_byte key_tt;  /* key type */
    int next;  /* for chaining */
    Value key_val;  /* key value */
  } u;
  TValue i_val;  /* direct access to node's value as a proper 'TValue' */
} Node;
```

- Memory occupation

It should be noted that Node is defined as a union which encompasses both the key and the corresponding value for key-value pairs. 
Additionally, Lua reorders the fields inside Node with the aim of optimizing memory usage.

Take a 64-bit system as an example. In this context, the size of Node calculates to be `3 * 8 = 24`.

```c
typedef union Node {
  struct NodeKey {
    Value value_;   /* start at 0 offset, alignment is 8 */
    lu_byte tt_;    /* start at 8 offset, alignment is 1 */
    lu_byte key_tt; /* start at 9 offset, alignment is 1 */
    int next;       /* start at 12 offset(two bytes pedding before), alignment is 4 */
    Value key_val;  /* start at 16 offset, alignment is 8 */
  } u;
  TValue i_val;     /* in union and size is less than u */
} Node;
```

In contrast, if we define the `Node` structure as follows:

```c
typedef union Node {
  struct NodeKey {
    Value value_;
    lu_byte tt_;
    lu_byte key_tt;
    Value key_val;
    int next;
  } u;
  TValue i_val;
} Node;
```

In a 64-bits system, it would occupy `4 * 8 = 32` bits.

- The design of the `next` field

All hash nodes are stored in an array (with the type being `Node` and constituting the hash part of the table). 
However, different nodes that have the same hash value will be chained together, and this chaining is achieved through the `next` field.

We don't need to be concerned about the overflow issues of the `int` type. 
This is because the capacity of the hash part will not exceed the maximum value that an `int` can represent. 
Hence, using `int` for addressing purposes is adequate for this context.

```c
typedef struct Table {
  CommonHeader;
  lu_byte flags;  /* 1<<p means tagmethod(p) is not present */
  lu_byte lsizenode;  /* log2 of size of 'node' array */
  unsigned int alimit;  /* "limit" of 'array' array */
  TValue *array;  /* array part */
  Node *node;
  Node *lastfree;  /* any free position is before this position */
  struct Table *metatable;
  GCObject *gclist;
} Table;
```

For this definition, there are several key points to be pay attention:

- `array` and `node` field are consecutive, without another fields gap between them. Thanks to this design, we can iterate over both the array part and the hash part (represented by the node field) of the table using the same index, as is done in the `luaH_next` function. 
- `lsizenode` represents the ceiling of the base-2 logarithm of the size of the node array, that is, `ceil(log2(node size))`.
  - Moreover, the capacity (the space allocated by the allocator) of the hash part is invariably a power of 2, and the same applies to the array part.
  - The capacity of hash part can be calculated by `2^(lsizenode)`
- `alimit` does not represent the actual size(or real size) of array part. We can regard it as a **hint**, which helps us quickly determine whether an integer index exists in the array part or not.
  - The capacity of the array part is the smallest power of 2 that is greater than alimit, which is calculated by `luaH_realasize`.
  - If we explicitly call the setrealasize macro, alimit will represent the real size of the array part. It should be noted that this occurs only when we call the setlimittosize function.
  - In other cases, alimit may be set to other values to represent a "false positive" boundary of the array part (merely serving as a hint).

## Operation for Table

For basic operations of tables, our focus will be on their semantics, specifically the implications of input and output as well as their internal implementation.

### Auxiliary function

#### Finding main position of key

Given a key, we try to find its main position, which refers to the location where we directly apply the hash function to calculate the corresponding index.

- If the key is an integer, we directly hash its value. 
- If it is a floating-point number, we use a custom hash function for floating-point values. 
- For boolean values, a key of this type will always be mapped to either an index of 0 or 1 within the hash part of the table. 
- For strings, we utilize their hash values for addressing purposes. In particular, for long strings, we calculate their hash values in a lazy manner. 
- For light userdata, light C functions, and other types, we hash their pointer addresses.

```c
/*
** returns the 'main' position of an element in a table (that is,
** the index of its hash value).
*/
static Node *mainpositionTV (const Table *t, const TValue *key) {
  switch (ttypetag(key)) {
    case LUA_VNUMINT: {
      lua_Integer i = ivalue(key);
      return hashint(t, i);
    }
    case LUA_VNUMFLT: {
      lua_Number n = fltvalue(key);
      return hashmod(t, l_hashfloat(n));
    }
    case LUA_VSHRSTR: {
      TString *ts = tsvalue(key);
      return hashstr(t, ts);
    }
    case LUA_VLNGSTR: {
      TString *ts = tsvalue(key);
      return hashpow2(t, luaS_hashlongstr(ts));
    }
    case LUA_VFALSE:
      return hashboolean(t, 0);
    case LUA_VTRUE:
      return hashboolean(t, 1);
    case LUA_VLIGHTUSERDATA: {
      void *p = pvalue(key);
      return hashpointer(t, p);
    }
    case LUA_VLCF: {
      lua_CFunction f = fvalue(key);
      return hashpointer(t, f);
    }
    default: {
      GCObject *o = gcvalue(key);
      return hashpointer(t, o);
    }
  }
}
```

The contrast version of the last function, given a hash node, tries to find the main position of its key.

It should be noted that the reason we introduce these two functions is that in case a collision occurs (i.e., when two different keys are mapped to the same hash slot), we have to move one of them to another position (in Lua, typically to a higher address space).
So, we must write a function to obtain the main position of a key.

```c
l_sinline Node *mainpositionfromnode (const Table *t, Node *nd) {
  TValue key;
  getnodekey(cast(lua_State *, NULL), &key, nd);
  return mainpositionTV(t, &key);
}
```

#### Get free position

Starting from `t->node`, this function iterates through the nodes one by one to find the first node with an empty key. 
It should be noted that this function does not check whether the capacity is sufficient or not. Hence, this additional check must be carried out prior to calling this function.

```c
static Node *getfreepos (Table *t) {
  if (!isdummy(t)) {
    while (t->lastfree > t->node) {
      t->lastfree--;
      if (keyisnil(t->lastfree))
        return t->lastfree;
    }
  }
  return NULL;  /* could not find a free place */
}
```

#### Array part

The following two functions should be considered together. The `arrayindex` function merely checks whether an integer key is out of bounds (i.e., its index is greater than the largest array capacity). 
If it is out of bounds, the function returns zero; otherwise, it converts the integer to an `unsigned int`.

The second function attempts to find the integer index of a given key. This function should explicitly specify the array capacity. Let's explore the details.
The findindex function is only called within `luaH_next`, and we can regard it as an auxiliary function for `luaH_next`.

Since the integer keys in Lua start from 1, while the `t->array` indexing starts from `0`, we should check `key - 1` instead of key to determine whether it is out of bounds. 
Due to this offset, if we pass the last integer key of the array part to findindex, it will not actually retrieve that key.

For example, if in the Lua layer the table is defined as `t = {[1] = 1, [2] = 2, [3] = 3, ["key"] = "val"}` and we push `3` onto the stack as the starting key for `luaH_next`, it will not iterate over key `3` but rather the key "key". 
This is because `findindex` will return `3` in this scenario. Although `3` is less than `asize`, `t->array[3]` is empty (only `t->array[0:2]` have values), so it proceeds to iterate over the hash part.

In the hash part, we should maintain this property. If we simply return `i + asize`, it will iterate over the input key, which does not meet our expectations. Instead, we should return `(i + 1) + asize`.

```c
/*
** returns the index for 'k' if 'k' is an appropriate key to live in
** the array part of a table, 0 otherwise.
*/
static unsigned int arrayindex (lua_Integer k) {
  if (l_castS2U(k) - 1u < MAXASIZE)  /* 'k' in [1, MAXASIZE]? */
    return cast_uint(k);  /* 'key' is an appropriate array index */
  else
    return 0;
}

/*
** returns the index of a 'key' for table traversals. First goes all
** elements in the array part, then elements in the hash part. The
** beginning of a traversal is signaled by 0.
*/
static unsigned int findindex (lua_State *L, Table *t, TValue *key,
                               unsigned int asize) {
  unsigned int i;
  if (ttisnil(key)) return 0;  /* first iteration */
  i = ttisinteger(key) ? arrayindex(ivalue(key)) : 0;
  if (i - 1u < asize)  /* is 'key' inside array part? */
    return i;  /* yes; that's the index */
  else {
    const TValue *n = getgeneric(t, key, 1);
    if (l_unlikely(isabstkey(n)))
      luaG_runerror(L, "invalid key to 'next'");  /* key not found */
    i = cast_int(nodefromval(n) - gnode(t, 0));  /* key index in hash table */
    /* hash elements are numbered after array ones */
    return (i + 1) + asize;
  }
}
```

#### Rehash

The following series of functions implement the rehash and resize functionality of tables. 
If we read the source code from top to bottom in its original order, it's extremely difficult to understand the implementation of rehash. Therefore, we rearrange the order for better comprehension.

Let's first take a look at the higher-level function, which can assist in understanding the semantics of each auxiliary function (at the lower level). 
Thanks to the annotations after each line, we can roughly understand the functionality of each function.

The `numusearray` function is used to count the number of keys in the array part, while the `numusehash` function is used to count the number of integer keys in the hash part. 
The variable `na` represents the number of keys in the array part, and the array `nums` with a size of `MAXABITS + 1` serves as a buffer to distribute each integer key into intervals with a size that is a power of 2 and count how many keys exist in each interval.
For example, if the keys are dense, say in the range `[1, 100]`, the content of `nums` should be as follows:

```
nums[] = {0}
index i represents intervals (2^(i - 1), 2^i]
nums[0] += 1 // How many keys lie in [1, 2]
nums[1] += 2 // How many keys lie in (2, 4]
nums[2] += 4 // How many keys lie in (4, 8]
nums[3] += 8 // How many keys lie in (8, 16]
...
nums[31] +=...
```

Based on the implication of this array, the `countint` function is used to distribute (by applying the ceiling of `log2`) an integer key to the proper index of the `nums` array.
It should be noted that the return values of both `numusearray` and `numusehash` represent the number of keys (regardless of their types) in the array and hash parts respectively. 
However, internally, `numusehash` only accumulates integer keys and stores the result in `nums` and `na`.
Now that we understand the meaning of each variable, where `na` is the number of keys in the entire table and `nums` is the distribution of each integer key, we pass these two variables to the `computesizes` function to calculate the new size of the **array part**. 
This new size should ensure that half of the integer keys go into the new array part. Note that we pass `na` by reference to `computesizes`, so it will assign the number of integer keys that should go into the array part.
After obtaining the new size of the array part, we pass it along with the new size of the hash part (total keys minus all integer keys going to the array part) to resize the whole table.

```c
/*
** nums[i] = number of keys 'k' where 2^(i - 1) < k <= 2^i
*/
static void rehash (lua_State *L, Table *t, const TValue *ek) {
  unsigned int asize;  /* optimal size for array part */
  unsigned int na;  /* number of keys in the array part */
  unsigned int nums[MAXABITS + 1];
  int i;
  int totaluse;
  for (i = 0; i <= MAXABITS; i++) nums[i] = 0;  /* reset counts */
  setlimittosize(t);
  na = numusearray(t, nums);  /* count keys in array part */
  totaluse = na;  /* all those keys are integer keys */
  totaluse += numusehash(t, nums, &na);  /* count keys in hash part */
  /* count extra key */
  if (ttisinteger(ek))
    na += countint(ivalue(ek), nums);
  totaluse++;
  /* compute new size for array part */
  asize = computesizes(nums, &na);
  /* resize the table to new computed sizes */
  luaH_resize(L, t, asize, totaluse - na);
}
```

This function calculates the ceiling of `log2` of a key and adds the value to the corresponding index in the `nums` array.

```c
static int countint (lua_Integer key, unsigned int *nums) {
  unsigned int k = arrayindex(key);
  if (k != 0) {  /* is 'key' an appropriate array index? */
    nums[luaO_ceillog2(k)]++;  /* count as such */
    return 1;
  }
  else
    return 0;
}
```

The following two functions calculate the number of keys in the array part and hash part respectively. 
For `numusehash`, it simply iterates through all the hash nodes in reverse order and calls `countint` to accumulatively count the integer keys. 
For `numusearray`, it manually distributes each integer key into the `nums` array.

```c
/*
** Count keys in array part of table 't': Fill 'nums[i]' with
** number of keys that will go into corresponding slice and return
** total number of non-nil keys.
*/
static unsigned int numusearray (const Table *t, unsigned int *nums) {
  int lg;
  unsigned int ttlg;  /* 2^lg */
  unsigned int ause = 0;  /* summation of 'nums' */
  unsigned int i = 1;  /* count to traverse all array keys */
  unsigned int asize = limitasasize(t);  /* real array size */
  /* traverse each slice */
  for (lg = 0, ttlg = 1; lg <= MAXABITS; lg++, ttlg *= 2) {
    unsigned int lc = 0;  /* counter */
    unsigned int lim = ttlg;
    if (lim > asize) {
      lim = asize;  /* adjust upper limit */
      if (i > lim)
        break;  /* no more elements to count */
    }
    /* count elements in range (2^(lg - 1), 2^lg] */
    for (; i <= lim; i++) {
      if (!isempty(&t->array[i-1]))
        lc++;
    }
    nums[lg] += lc;
    ause += lc;
  }
  return ause;
}

static int numusehash (const Table *t, unsigned int *nums, unsigned int *pna) {
  int totaluse = 0;  /* total number of elements */
  int ause = 0;  /* elements added to 'nums' (can go to array part) */
  int i = sizenode(t);
  while (i--) {
    Node *n = &t->node[i];
    if (!isempty(gval(n))) {
      if (keyisinteger(n))
        ause += countint(keyival(n), nums);
      totaluse++;
    }
  }
  *pna += ause;
  return totaluse;
}
```

Now that we understand the meaning of the two input arguments, where `nums` represents the distribution of integer keys and `pna` represents the number of integer keys, this function should return the new size (referred to as the optimal size) of the array part, and this return value should possess several attributes:

- The optimal size should be a power of 2.
- Half of the optimal size should be less than the total number of integer keys, and the optimal size should be greater than or equal to the number of total integer keys.

The internal logic of this function is relatively straightforward. It accumulates the values in `nums` by index `i` and checks whether the current accumulated value `a` is greater than `2^i`. 
If so, it assigns `optimal` to the value `2^i` and `na` to the current accumulated value `a`, indicating how many integer keys should go to the new array part.

```c
/*
** Compute the optimal size for the array part of table 't'. 'nums' is a
** "count array" where 'nums[i]' is the number of integers in the table
** between 2^(i - 1) + 1 and 2^i. 'pna' enters with the total number of
** integer keys in the table and leaves with the number of keys that
** will go to the array part; return the optimal size.  (The condition
** 'twotoi > 0' in the for loop stops the loop if 'twotoi' overflows.)
*/
static unsigned int computesizes (unsigned int nums[], unsigned int *pna) {
  int i;
  unsigned int twotoi;  /* 2^i (candidate for optimal size) */
  unsigned int a = 0;  /* number of elements smaller than 2^i */
  unsigned int na = 0;  /* number of elements to go to array part */
  unsigned int optimal = 0;  /* optimal size for array part */
  /* loop while keys can fill more than half of total size */
  for (i = 0, twotoi = 1;
       twotoi > 0 && *pna > twotoi / 2;
       i++, twotoi *= 2) {
    a += nums[i];
    if (a > twotoi/2) {  /* more than half elements present? */
      optimal = twotoi;  /* optimal size (till now) */
      na = a;  /* all elements up to 'optimal' will go to array part */
    }
  }
  lua_assert((optimal == 0 || optimal / 2 < na) && na <= optimal);
  *pna = na;
  return optimal;
}
```

The following four functions are relatively straightforward, and we'll briefly look at them.

The `setnodevector` function resets the hash part of the table according to the input `size` (where `size` represents the number of elements rather than bytes). 
If `size` is zero, it doesn't actually allocate space but instead assigns `t->node` to the global static dummy node. This means that if many tables are empty, the `t->node` field of these tables will have the same value. 
If we happen to load `ltable.c` multiple times (where the global static dummy node is defined), it might cause some bugs. 
For each hash node, we simply set its key and value to empty. For `t->lastfree`, it will be assigned to the next position of the last node (to find a free node, refer to the `getfreepos` function).

The `reinsert` function simply iterates through all non-empty nodes from `ot` and inserts them into `t` by calling `luaH_set`.

The `exchangehashpart` function exchanges the hash fields (specifically, `t->node`, `t->lsizenode`, and `t->lastfree`), without performing a deep copy.

The `getfreepos` function attempts to find the first empty node starting from the last node of the entire hash node array. If all nodes are not empty, it returns `NULL`, indicating that there is no free space and rehashing is required.

```c
/*
** Creates an array for the hash part of a table with the given
** size, or reuses the dummy node if size is zero.
** The computation for size overflow is in two steps: the first
** comparison ensures that the shift in the second one does not
** overflow.
*/
static void setnodevector (lua_State *L, Table *t, unsigned int size) {
  if (size == 0) {  /* no elements to hash part? */
    t->node = cast(Node *, dummynode);  /* use common 'dummynode' */
    t->lsizenode = 0;
    t->lastfree = NULL;  /* signal that it is using dummy node */
  }
  else {
    int i;
    int lsize = luaO_ceillog2(size);
    if (lsize > MAXHBITS || (1u << lsize) > MAXHSIZE)
      luaG_runerror(L, "table overflow");
    size = twoto(lsize);
    t->node = luaM_newvector(L, size, Node);
    for (i = 0; i < cast_int(size); i++) {
      Node *n = gnode(t, i);
      gnext(n) = 0;
      setnilkey(n);
      setempty(gval(n));
    }
    t->lsizenode = cast_byte(lsize);
    t->lastfree = gnode(t, size);  /* all positions are free */
  }
}

/*
** (Re)insert all elements from the hash part of 'ot' into table 't'.
*/
static void reinsert (lua_State *L, Table *ot, Table *t) {
  int j;
  int size = sizenode(ot);
  for (j = 0; j < size; j++) {
    Node *old = gnode(ot, j);
    if (!isempty(gval(old))) {
      /* doesn't need barrier/invalidate cache, as entry was
         already present in the table */
      TValue k;
      getnodekey(L, &k, old);
      luaH_set(L, t, &k, gval(old));
    }
  }
}

/*
** Exchange the hash part of 't1' and 't2'.
*/
static void exchangehashpart (Table *t1, Table *t2) {
  lu_byte lsizenode = t1->lsizenode;
  Node *node = t1->node;
  Node *lastfree = t1->lastfree;
  t1->lsizenode = t2->lsizenode;
  t1->node = t2->node;
  t1->lastfree = t2->lastfree;
  t2->lsizenode = lsizenode;
  t2->node = node;
  t2->lastfree = lastfree;
}

static Node *getfreepos (Table *t) {
  if (!isdummy(t)) {
    while (t->lastfree > t->node) {
      t->lastfree--;
      if (keyisnil(t->lastfree))
        return t->lastfree;
    }
  }
  return NULL;  /* could not find a free place */
}
```

The following function is used to resize the entire hash table. 
According to the explanation in the [Rehash](#rehash) section, we already understand the meaning of the two input arguments. `newasize` represents the new size of the array part, and `nhsize` represents the new size of the hash part. 
Pay attention to the definition of size here; it refers to the number of elements rather than bytes. 
At the same time, the values of `newasize` and `nhsize` might not initially be powers of 2, but the capacities of these parts must eventually be powers of 2.

This function declares a table **on the stack** and only initializes its hash part (setting all elements to empty), intending to use it as a temporary hash part of the table. 
The process of resizing is as follows:
- First, check whether the array part of the table will shrink or not.
    - If it will shrink, insert elements that are out of bounds into the hash part of the temporary table.
        - Here, a question might arise as to why we pretend the array has a new (smaller) size. 
        - This is because we should shrink `t->alimit` in case original keys existing in the array part might be reinserted into the array part (while we expect these keys to go into the hash part).
    - Otherwise, we simply reallocate the array part. If the reallocation fails, we release the hash part of the temporary table and raise an error with the array already resized.
- Second, we set the key and value to empty in the newly allocated space, exchange the hash part with the larger one (exchange the hash part of the current table with that of the temporary table), and insert keys that previously existed in the array part into the hash part.

```c
/*
** Resize table 't' for the new given sizes. Both allocations (for
** the hash part and for the array part) can fail, which creates some
** subtleties. If the first allocation, for the hash part, fails, an
** error is raised and that is it. Otherwise, it copies the elements from
** the shrinking part of the array (if it is shrinking) into the new
** hash. Then it reallocates the array part.  If that fails, the table
** is in its original state; the function frees the new hash part and then
** raises the allocation error. Otherwise, it sets the new hash part
** into the table, initializes the new part of the array (if any) with
** nils and reinserts the elements of the old hash back into the new
** parts of the table.
*/
void luaH_resize (lua_State *L, Table *t, unsigned int newasize,
                                          unsigned int nhsize) {
  unsigned int i;
  Table newt;  /* to keep the new hash part */
  unsigned int oldasize = setlimittosize(t);
  TValue *newarray;
  /* create new hash part with appropriate size into 'newt' */
  setnodevector(L, &newt, nhsize);
  if (newasize < oldasize) {  /* will array shrink? */
    t->alimit = newasize;  /* pretend array has new size... */
    exchangehashpart(t, &newt);  /* and new hash */
    /* re-insert into the new hash the elements from vanishing slice */
    for (i = newasize; i < oldasize; i++) {
      if (!isempty(&t->array[i]))
        luaH_setint(L, t, i + 1, &t->array[i]);
    }
    t->alimit = oldasize;  /* restore current size... */
    exchangehashpart(t, &newt);  /* and hash (in case of errors) */
  }
  /* allocate new array */
  newarray = luaM_reallocvector(L, t->array, oldasize, newasize, TValue);
  if (l_unlikely(newarray == NULL && newasize > 0)) {  /* allocation failed? */
    freehash(L, &newt);  /* release new hash part */
    luaM_error(L);  /* raise error (with array unchanged) */
  }
  /* allocation ok; initialize new part of the array */
  exchangehashpart(t, &newt);  /* 't' has the new hash ('newt' has the old) */
  t->array = newarray;  /* set new array part */
  t->alimit = newasize;
  for (i = oldasize; i < newasize; i++)  /* clear new slice of the array */
     setempty(&t->array[i]);
  /* re-insert elements from old hash part into new parts */
  reinsert(L, &newt, t);  /* 'newt' now has the old hash */
  freehash(L, &newt);  /* free old hash part */
}
```

The following function is just a wrapper around `luaH_resize`. The input argument `nasize` represents the new array size. 
We pass it along with the size of the hash part to the `luaH_resize` function, meaning that our intention is only to resize the size of the array part.

```c
void luaH_resizearray (lua_State *L, Table *t, unsigned int nasize) {
  int nsize = allocsizenode(t);
  luaH_resize(L, t, nasize, nsize);
}
```

In general, when dealing with these functions related to table rehashing and resizing, it's crucial to understand how each function plays a role in maintaining and modifying the internal structure of the table. The operations are designed with careful consideration of memory management and the efficient organization of key-value pairs within the table. For instance, the way `luaH_resize` handles different scenarios of array shrinking or expanding, along with the proper handling of hash part exchanges and element reinsertions, showcases the complexity and precision required in this aspect of the Lua table implementation.

Moreover, functions like `setnodevector`, `reinsert`, and `exchangehashpart` work in concert to support the overall resizing process. `setnodevector` takes care of initializing or reusing the hash part based on the specified size, ensuring proper setup of nodes. `reinsert` is responsible for moving elements from one table's hash part to another, while `exchangehashpart` enables the seamless swapping of hash-related fields between different tables when needed.

All these functions together form a comprehensive mechanism for handling the dynamic nature of Lua tables, allowing them to adapt to changes in the number of elements and maintain optimal performance in terms of memory usage and access speed.

### Insert operation

As indicated in the annotations, this function aims to insert a new key into the table following these steps:
- Check whether the key's main position is free:
    - If it's free, then the insertion is completed.
    - Otherwise, check if the colliding key is in its main position:
        - If so, the new key will be placed in an empty position (without moving the colliding key).
        - Otherwise, move the colliding key to an empty position and insert the new key into its main position.

Miscellaneous points:
- If the new key is a floating-point number, an attempt will be made to convert it to an integer. This is done by applying the floor function and checking whether the result is equal to the original floating-point value.
- `mp` represents the main position of the new key (if not empty, it's the colliding key), and `othern` represents the main position of the colliding key (which could be `mp`).
- Regarding why looping with the condition `othern + gnext(othern)!= mp` will eventually find the previous key of `mp`:
    - Since the colliding key was inserted before the new key, its main position must precede that of the new key. Therefore, if we iterate from the colliding key's main position, we can eventually reach the current colliding position.
    - After finding the previous key of the colliding key, we insert the new key after it (by copying `mp` to `f`), and then correct the `next` fields of `f` and `mp` (`gnext(f)` should be set to the distance between `mp` and `f`, and `gnext(mp)` should be set to zero as it becomes the last node in this chain).

```c
/*
** inserts a new key into a hash table; first, check whether key's main
** position is free. If not, check whether colliding node is in its main
** position or not: if it is not, move colliding node to an empty place and
** put new key in its main position; otherwise (colliding node is in its main
** position), new key goes to an empty position.
*/
static void luaH_newkey (lua_State *L, Table *t, const TValue *key,
                                                 TValue *value) {
  Node *mp;
  TValue aux;
  if (l_unlikely(ttisnil(key)))
    luaG_runerror(L, "table index is nil");
  else if (ttisfloat(key)) {
    lua_Number f = fltvalue(key);
    lua_Integer k;
    if (luaV_flttointeger(f, &k, F2Ieq)) {  /* does key fit in an integer? */
      setivalue(&aux, k);
      key = &aux;  /* insert it as an integer */
    }
    else if (l_unlikely(luai_numisnan(f)))
      luaG_runerror(L, "table index is NaN");
  }
  if (ttisnil(value))
    return;  /* do not insert nil values */
  mp = mainpositionTV(t, key);
  if (!isempty(gval(mp)) || isdummy(t)) {  /* main position is taken? */
    Node *othern;
    Node *f = getfreepos(t);  /* get a free place */
    if (f == NULL) {  /* cannot find a free place? */
      rehash(L, t, key);  /* grow table */
      /* whatever called 'newkey' takes care of TM cache */
      luaH_set(L, t, key, value);  /* insert key into grown table */
      return;
    }
    lua_assert(!isdummy(t));
    othern = mainpositionfromnode(t, mp);
    if (othern != mp) {  /* is colliding node out of its main position? */
      /* yes; move colliding node into free position */
      while (othern + gnext(othern) != mp)  /* find previous */
        othern += gnext(othern);
      gnext(othern) = cast_int(f - othern);  /* rechain to point to 'f' */
      *f = *mp;  /* copy colliding node into free pos. (mp->next also goes) */
      if (gnext(mp) != 0) {
        gnext(f) += cast_int(mp - f);  /* correct 'next' */
        gnext(mp) = 0;  /* now 'mp' is free */
      }
      setempty(gval(mp));
    }
    else {  /* colliding node is in its own main position */
      /* new node will go into free position */
      if (gnext(mp) != 0)
        gnext(f) = cast_int((mp + gnext(mp)) - f);  /* chain new position */
      else lua_assert(gnext(f) == 0);
      gnext(mp) = cast_int(f - mp);
      mp = f;
    }
  }
  setnodekey(L, mp, key);
  luaC_barrierback(L, obj2gco(t), key);
  lua_assert(isempty(gval(mp)));
  setobj2t(L, gval(mp), value);
}
```

### Get operation

#### Main get function & Generic get function

All get functions are designed to return the value corresponding to the input key.

##### Main get function

```c
/*
** main search function
*/
const TValue *luaH_get (Table *t, const TValue *key) {
  switch (ttypetag(key)) {
    case LUA_VSHRSTR: return luaH_getshortstr(t, tsvalue(key));
    case LUA_VNUMINT: return luaH_getint(t, ivalue(key));
    case LUA_VNIL: return &absentkey;
    case LUA_VNUMFLT: {
      lua_Integer k;
      if (luaV_flttointeger(fltvalue(key), &k, F2Ieq)) /* integral index? */
        return luaH_getint(t, k);  /* use specialized version */
      /* else... */
    }  /* FALLTHROUGH */
    default:
      return getgeneric(t, key, 0);
  }
}
```

##### Generic get function

This function simply checks whether the key in a slot is identical to the input key, starting from the main position of the input key.

In Lua, the `gnext` macro is used to chain each hash slot. If a slot has an empty `next` field (with a value of zero), it means that it's the last slot in the hash table.

```c
/*
** "Generic" get version. (Not that generic: not valid for integers,
** which may be in array part, nor for floats with integral values.)
** See explanation about 'deadok' in function 'equalkey'.
*/
static const TValue *getgeneric (Table *t, const TValue *key, int deadok) {
  Node *n = mainpositionTV(t, key);
  for (;;) {  /* check whether 'key' is somewhere in the chain */
    if (equalkey(key, n, deadok))
      return gval(n);  /* that's it */
    else {
      int nx = gnext(n);
      if (nx == 0)
        return &absentkey;  /* not found */
      n += nx;
    }
  }
}
```

#### Next function

This function simply iterates over all elements starting from the index of the key obtained by `findindex`. 
We've already explained the inner workings of `findindex`, which returns the next index after the key's index. The implementation of `luaH_next` is quite intuitive as a result.

```c
int luaH_next (lua_State *L, Table *t, StkId key) {
  unsigned int asize = luaH_realasize(t);
  unsigned int i = findindex(L, t, s2v(key), asize);  /* find original key */
  for (; i < asize; i++) {  /* try first array part */
    if (!isempty(&t->array[i])) {  /* a non-empty entry? */
      setivalue(s2v(key), i + 1);
      setobj2s(L, key + 1, &t->array[i]);
      return 1;
    }
  }
  for (i -= asize; cast_int(i) < sizenode(t); i++) {  /* hash part */
    if (!isempty(gval(gnode(t, i)))) {  /* a non-empty entry? */
      Node *n = gnode(t, i);
      getnodekey(L, s2v(key), n);
      setobj2s(L, key + 1, gval(n));
      return 1;
    }
  }
  return 0;  /* no more elements */
}
```

#### Auxiliary get function

##### Get integer from hash table

The key point of this function is to check whether an integer key lies within the range of the array part.

In the simplest situation, if the key is in the range `[1, t->alimit]`, we can directly retrieve it from the array part (note that `alimit` may not represent the real size of the array part, but in this scenario, we don't need to concern ourselves with that).

If not, since `alimit` may not be the real size of the array part, we perform the following check:

- Objectives: Check whether `key - 1` is within the capacity of the array part.
    - Firstly, we know that the capacity of the array part is the smallest power of 2 that is greater than `alimit`, which means `2^p < alimit <= 2^(p + 1)`.
    - Secondly, we know that `key - 1` is now greater than or equal to `alimit`.
    - Therefore, we should check whether `key - 1` is less than `2^(p + 1)` or not.

We can clear the `p`-th bit of `key - 1`, which we'll call `res`.

If `key - 1` is greater than or equal to `2^(p + 1)`, `res` will have some bits higher than `p`, so it must be greater than or equal to `alimit` (`alimit <= 2 ^ (p + 1)`).
If `key - 1` is less than `2^(p + 1)`, `res` will definitely be less than `2^p` (since the `p`-th bit is cleared), so it must be less than `alimit` (`alimit > 2^p`).

Clearing the `p`-th bit of `key - 1` can be achieved by applying the operation `(key - 1) & ~(alimit - 1)`. Since `2^p < alimit <= 2 ^ (p + 1)`, we have `2^p <= alimit - 1 < 2 ^ (p + 1)`. Flipping `alimit - 1` will set all bits higher than the `p`-th bit to one and the `p`-th bit to zero, and other bits can be ignored. Therefore, performing a binary AND operation between `key - 1` and `~(alimit - 1)` will clear the `p`-th bit of `key - 1`.

If this key does not exist in the array part, we directly pass its value to the hash and perform probing in the hash part. The probing process is similar to that of the `getgeneric` function, where we find its main position and iterate from the low address to the high address.

```c
/*
** Search function for integers. If integer is inside 'alimit', get it
** directly from the array part. Otherwise, if 'alimit' is not
** the real size of the array, the key still can be in the array part.
** In this case, do the "Xmilia trick" to check whether 'key-1' is
** smaller than the real size.
** The trick works as follow: let 'p' be an integer such that
**   '2^(p+1) >= alimit > 2^p', or  '2^(p+1) > alimit-1 >= 2^p'.
** That is, 2^(p+1) is the real size of the array, and 'p' is the highest
** bit on in 'alimit-1'. What we have to check becomes 'key-1 < 2^(p+1)'.
** We compute '(key-1) & ~(alimit-1)', which we call 'res'; it will
** have the 'p' bit cleared. If the key is outside the array, that is,
** 'key-1 >= 2^(p+1)', then 'res' will have some bit on higher than 'p',
** therefore it will be larger or equal to 'alimit', and the check
** will fail. If 'key-1 < 2^(p+1)', then 'res' has no bit on higher than
** 'p', and as the bit 'p' itself was cleared, 'res' will be smaller
** than 2^p, therefore smaller than 'alimit', and the check succeeds.
** As special cases, when 'alimit' is 0 the condition is trivially false,
** and when 'alimit' is 1 the condition simplifies to 'key-1 < alimit'.
** If key is 0 or negative, 'res' will have its higher bit on, so that
** if cannot be smaller than alimit.
*/
const TValue *luaH_getint (Table *t, lua_Integer key) {
  lua_Unsigned alimit = t->alimit;
  if (l_castS2U(key) - 1u < alimit)  /* 'key' in [1, t->alimit]? */
    return &t->array[key - 1];
  else if (!isrealasize(t) &&  /* key still may be in the array part? */
           (((l_castS2U(key) - 1u) & ~(alimit - 1u)) < alimit)) {
    t->alimit = cast_uint(key);  /* probably '#t' is here now */
    return &t->array[key - 1];
  }
  else {  /* key is not in the array part; check the hash */
    Node *n = hashint(t, key);
    for (;;) {  /* check whether 'key' is somewhere in the chain */
      if (keyisinteger(n) && keyival(n) == key)
        return gval(n);  /* that's it */
      else {
        int nx = gnext(n);
        if (nx == 0) break;
        n += nx;
      }
    }
    return &absentkey;
  }
}
```

##### Get short string from hash table

Since strings always exist in the hash part, its getter function is quite intuitive. It involves calculating the main position of the input key and then iterating through the nodes one by one.

```c
/*
** search function for short strings
*/
const TValue *luaH_getshortstr (Table *t, TString *key) {
  Node *n = hashstr(t, key);
  lua_assert(key->tt == LUA_VSHRSTR);
  for (;;) {  /* check whether 'key' is somewhere in the chain */
    if (keyisshrstr(n) && eqshrstr(keystrval(n), key))
      return gval(n);  /* that's it */
    else {
      int nx = gnext(n);
      if (nx == 0)
        return &absentkey;  /* not found */
      n += nx;
    }
  }
}
```

##### Get long string from hash table

For long strings, we directly call the generic get function.

It should be noted that the way to get short strings is similar to that of getting long strings. Regardless of the string's length, we both leverage its hash value to address it within the hash part. 
The difference lies in the fact that the hash value for short strings is pre-calculated, while that for long strings is lazily calculated.

```c
const TValue *luaH_getstr (Table *t, TString *key) {
  if (key->tt == LUA_VSHRSTR)
    return luaH_getshortstr(t, key);
  else {  /* for long strings, use generic case */
    TValue ko;
    setsvalue(cast(lua_State *, NULL), &ko, key);
    return getgeneric(t, &ko, 0);
  }
}
```

### Set function

The `slot` field is a pointer to the value corresponding to the `key`. Its value should be obtained through the previous getter function, and then we can directly use the `setobj` macro to set its value.

If `isabstkey(slot)` evaluates to `true`, it indicates that this key does not exist in the table. In such a case, we should [insert a new key](#insert-operation) into it.

```c
/*
** Finish a raw "set table" operation, where 'slot' is where the value
** should have been (the result of a previous "get table").
** Beware: when using this function you probably need to check a GC
** barrier and invalidate the TM cache.
*/
void luaH_finishset (lua_State *L, Table *t, const TValue *key,
                                   const TValue *slot, TValue *value) {
  if (isabstkey(slot))
    luaH_newkey(L, t, key, value);
  else
    setobj2t(L, cast(TValue *, slot), value);
}
```

The following two functions are wrappers around `luaH_finishset`. 
The first one is a generic function used to set a key of any type into the table, and the second one is a specific function designed to set an integer key into the table.

```c
/*
** beware: when using this function you probably need to check a GC
** barrier and invalidate the TM cache.
*/
void luaH_set (lua_State *L, Table *t, const TValue *key, TValue *value) {
  const TValue *slot = luaH_get(t, key);
  luaH_finishset(L, t, key, slot, value);
}

void luaH_setint (lua_State *L, Table *t, lua_Integer key, TValue *value) {
  const TValue *p = luaH_getint(t, key);
  if (isabstkey(p)) {
    TValue k;
    setivalue(&k, key);
    luaH_newkey(L, t, &k, value);
  }
  else
    setobj2t(L, cast(TValue *, p), value);
}
```

### Finding a boundary

We need to clarify several basic facts:

#### What's the real size for the array part
- We already know that the capacity of the array part of a table is always the smallest power of 2 that is greater than `t->alimit`. This implies that `t->alimit` is always less than or equal to the capacity.
- Therefore, if `t->alimit` is equal to the capacity of the array part, we consider the current `t->alimit` to be the **real size** of the array part, meaning that `isrealasize` will return `true`.
- Besides, there is a macro `limitequalsasize` used to check whether `alimit` represents the real size. The condition is relatively simple: it just checks whether the 7th bit of the table's flag is set to zero and whether `t->alimit` is a power of 2.
- The `luaH_realasize` function is used to return the real size of the array part. Its calculation method involves finding the smallest power of 2 that is greater than `t->alimit`.

#### The implication of `ispow2realasize`
- First, when the macro `isrealasize` returns `true`, it means that `t->alimit` is equal to the capacity of the array, and vice versa.
- If `isrealasize` returns `false`, it indicates that the real size of the array part is a power of 2. This is because the real size of the array is equivalent to its capacity, and the latter is always a power of 2.
- If `isrealasize` returns `true`, it means that `t->alimit` equals the real size of the array, which is also the capacity of the array. In this case, we then check whether `t->alimit` is a power of 2.
- It's important to note that `isrealasize` is always updated synchronously with whether `t->alimit` is equal to the real size of the array part.
- This macro is used to check whether the real size of the array is a power of 2 (although one might think it's somewhat redundant since the capacity of the array part is always allocated as a power of 2).

The following function, `luaH_getn`, is used to find a boundary of the table. That is, it finds an index `i` such that `t[i]` is present but `t[i + 1]` is absent (here, `i` represents the boundary). Also, it should be noted that **its return index is in Lua form (base 1), while its internal processing index is in C form (base 0)**. According to the annotation before the function, it's relatively easy to understand, but we need to clarify the functionality of the `binsearch` and `hash_search` functions.

For the `binsearch` function, it attempts to find a boundary within the range from `i` to `j`. Additionally, it has two properties:
- For the element pointed to by `i`, it's present; for the element pointed to by `j`, it's absent.
- So, internally, when we encounter an element that is present, we update the left endpoint; and when we encounter an element that is absent, we update the right endpoint.

For the `hash_search` function, it tries to search for a boundary in the hash part of the table.
- The input argument `j` indicates that this element (which is `j`, an element in the table) is present (and `j + 1` is also present). We then try to find a boundary starting from this element within the hash part.
- This function keeps doubling `j` until it encounters an absent element. After that, we perform a binary search within the hash part between the two elements.

Note that `luaH_getn` is used to obtain the boundary of the table, and this boundary is always the maximum boundary if multiple boundaries exist. 
For example, if we have a table `t = {1, 2, 3, [5] = 5, [7] = 7}`, according to the definition of a boundary, the possible boundaries could be `3`, `5`, and `7` because `t[i]` is present while `t[i + 1]` is absent. 
Due to the existence of multiple boundaries, we always **return the largest (rightmost) boundary**.

```c
/*
** Try to find a boundary in table 't'. (A 'boundary' is an integer index
** such that t[i] is present and t[i+1] is absent, or 0 if t[1] is absent
** and 'maxinteger' if t[maxinteger] is present.)
** (In the next explanation, we use Lua indices, that is, with base 1.
** The code itself uses base 0 when indexing the array part of the table.)
** The code starts with 'limit = t->alimit', a position in the array
** part that may be a boundary.
**
** (1) If 't[limit]' is empty, there must be a boundary before it.
** As a common case (e.g., after 't[#t]=nil'), check whether 'limit-1'
** is present. If so, it is a boundary. Otherwise, do a binary search
** between 0 and limit to find a boundary. In both cases, try to
** use this boundary as the new 'alimit', as a hint for the next call.
**
** (2) If 't[limit]' is not empty and the array has more elements
** after 'limit', try to find a boundary there. Again, try first
** the special case (which should be quite frequent) where 'limit+1'
** is empty, so that 'limit' is a boundary. Otherwise, check the
** last element of the array part. If it is empty, there must be a
** boundary between the old limit (present) and the last element
** (absent), which is found with a binary search. (This boundary always
** can be a new limit.)
**
** (3) The last case is when there are no elements in the array part
** (limit == 0) or its last element (the new limit) is present.
** In this case, must check the hash part. If there is no hash part
** or 'limit+1' is absent, 'limit' is a boundary.  Otherwise, call
** 'hash_search' to find a boundary in the hash part of the table.
** (In those cases, the boundary is not inside the array part, and
** therefore cannot be used as a new limit.)
*/
lua_Unsigned luaH_getn (Table *t) {
  unsigned int limit = t->alimit;
  if (limit > 0 && isempty(&t->array[limit - 1])) {  /* (1)? */
    /* there must be a boundary before 'limit' */
    if (limit >= 2 &&!isempty(&t->array[limit - 2])) {
      /* 'limit - 1' is a boundary; can it be a new limit? */
      if (ispow2realasize(t) &&!ispow2(limit - 1)) {
        t->alimit = limit - 1;
        setnorealasize(t);  /* now 'alimit' is not the real size */
      }
      return limit - 1;
    }
    else {  /* must search for a boundary in [0, limit] */
      unsigned int boundary = binsearch(t->array, 0, limit);
      /* can this boundary represent the real size of the array? */
      if (ispow2realasize(t) && boundary > luaH_realasize(t) / 2) {
        t->alimit = boundary;  /* use it as the new limit */
        setnorealasize(t);
      }
      return boundary;
    }
  }
  /* 'limit' is zero or present in table */
  if (!limitequalsasize(t)) {  /* (2)? */
    /* 'limit' > 0 and array has more elements after 'limit' */
    if (isempty(&t->array[limit]))  /* 'limit + 1' is empty? */
      return limit;  /* this is the boundary */
    /* else, try last element in the array */
    limit = luaH_realasize(t);
    if (isempty(&t->array[limit - 1])) {  /* empty? */
      /* there must be a boundary in the array after old limit,
         and it must be a valid new limit */
      unsigned int boundary = binsearch(t->array, t->alimit, limit);
      t->alimit = boundary;
      return boundary;
    }
    /* else, new limit is present in the table; check the hash part */
  }
  /* (3) 'limit' is the last element and either is zero or present in table */
  lua_assert(limit == luaH_realasize(t) &&
             (limit == 0 ||!isempty(&t->array[limit - 1])));
  if (isdummy(t) || isempty(luaH_getint(t, cast(lua_Integer, limit + 1))))
    return limit;  /* 'limit + 1' is absent */
  else  /* 'limit + 1' is also present */
    return hash_search(t, limit);
}
```

The key point of this form of binary search is that the left endpoint always satisfies the condition while the right endpoint always does not. 
Therefore, we initialize the left and right endpoints to be **left closed and right open**, and we eventually return the left endpoint since it always satisfies the condition. 
Similarly, if we want to return the right endpoint (i.e., the right endpoint always satisfies the condition), we should initialize the left and right endpoints to be **left open and right closed**.

The function `binsearch` is actually the last part of `hash_search`, so we'll omit it for now.

```c
/*
** Try to find a boundary in the hash part of table 't'. From the
** caller, we know that 'j' is zero or present and that 'j + 1' is
** present. We want to find a larger key that is absent from the
** table, so that we can do a binary search between the two keys to
** find a boundary. We keep doubling 'j' until we get an absent index.
** If the doubling would overflow, we try LUA_MAXINTEGER. If it is
** absent, we are ready for the binary search. ('j', being max integer,
** is larger or equal to 'i', but it cannot be equal because it is
** absent while 'i' is present; so 'j > i'.) Otherwise, 'j' is a
** boundary. ('j + 1' cannot be a present integer key because it is
** not a valid integer in Lua.)
*/
static lua_Unsigned hash_search (Table *t, lua_Unsigned j) {
  lua_Unsigned i;
  if (j == 0) j++;  /* the caller ensures 'j + 1' is present */
  do {
    i = j;  /* 'i' is a present index */
    if (j <= l_castS2U(LUA_MAXINTEGER) / 2)
      j *= 2;
    else {
      j = LUA_MAXINTEGER;
      if (isempty(luaH_getint(t, j)))  /* t[j] not present? */
        break;  /* 'j' now is an absent index */
      else  /* weird case */
        return j;  /* well, max integer is a boundary... */
    }
  } while (!isempty(luaH_getint(t, j)));  /* repeat until an absent t[j] */
  /* i < j  &&  t[i] present  &&  t[j] absent */
  while (j - i > 1u) {  /* do a binary search between them */
    lua_Unsigned m = (i + j) / 2;
    if (isempty(luaH_getint(t, m))) j = m;
    else i = m;
  }
  return i;
}

static unsigned int binsearch (const TValue *array, unsigned int i,
                                                    unsigned int j) {
  while (j - i > 1u) {  /* binary search */
    unsigned int m = (i + j) / 2;
    if (isempty(&array[m - 1])) j = m;
    else i = m;
  }
  return i;
}
```

