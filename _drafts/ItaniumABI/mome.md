In what follows, we define the memory layout for C++ data objects. Specifically, for each type, we specify
the following information about an object `O` of that type:

- the size of an object, `sizeof(O)`;
- the alignment of an object, `align(O)`; and
- the offset within `O`, `offset(C)`, of each data component `C`, i.e. base or member.

For purposes internal to the specification, we also specify:

- `dsize(O)`: the data size of an object, which is the size of `O` without tail padding.
- `nvsize(O)`: the non-virtual size of an object, which is the size of `O` without virtual bases.
- `nvalign(O)`: the non-virtual alignment of an object, which is the alignment of `O` without virtual bases.

> what's virtual bases:
> https://stackoverflow.com/a/21607/27227723
> https://isocpp.org/wiki/faq/multiple-inheritance


