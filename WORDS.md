# gluumy Core Words Reference

This document describes all words in gluumy's Core - in the reference
implementation, this refers to any words provided by the Kernel or Prelude.

All word signatures in this document use the fully qualified right-pointing
form, which is to say, the stack will be taken from the arrow leftwards, and
given from the arrow rightwards. Thus, `@2 @1 -> @1 @2` will take a generic
(kind 1) from the top of the stack, then another generic (kind 2) from the
now-top of the stack, do... whatever with them, and eventually place objects
of kind 1 and kind 2, respectively and orderly, onto the top of the stack,
performing an effective swap. Technically word signatures alone aren't
enough to know that @1 and @1 are the same objects in memory: they'll simply
be the same Shape. You'll need to read the docs and/or implementation to
make "object in memory" assertions.

## Primitives

The Kernel understands a few data types out of the box, as follows.
Particularly in the case of numbers, trailing slashes and suffixes can be used
to disambiguate datatypes (eg. between signed and unsigned integers within
range).

- `42`, `42/u`: unsigned integers, aligned to the native bit-size of the
  system.

- `-1`, `42/i`: signed integers, aligned to the native bit-size of the system.

- `

- `"strings"`: a sequence of valid UTF-8 codepoints. Double quotes within the
  string can be escaped with `\`, and thus a raw `\` character must also be
  escaped as `\\`.

## Trusting Words

These words sit at the absolute lowest level of the gluumy Kernel, implementing
memory management in "unsafe" ways. Unsafe is a rather strong word with rather
strong connotations: well-tested code that accesses raw memory is not
inherently "unsafe", it simply must be heavily tested, and trusted. Thus, they
are called "Trusting Words". Their risky nature is emphasized stylistically by
way of their being `!UPPERCASED`, and prefixed with an exclamation point. They
look a bit more FORTH-y than most of gluumy's vocabulary.

## Generic Stack Manipulation

All of these live in the Global mode, as they apply regardless of execution
state.

| Word      | Signature                             | Notes |
|-----------|---------------------------------------|-------|
| id        | `@1 -> @1`                            | |
| dup       | `@1 -> @1 @1`                         | |
| dupn2     | `@2 @1 -> @2 @1 @2`                   | |
| dupn3     | `@3 @2 @1 -> @3 @2 @1 @3`             | |
| dupn4     | `@4 @3 @2 @1 -> @4 @3 @2 @1 @4`       | |
| 2dup      | `@2 @1 -> @2 @2 @1 @1`                | |
| 2dupshuf  | `@2 @1 -> @2 @1 @2 @1`                | |
| swap      | `@2 @1 -> @1 @2`                      | |
| pairswap  | `@4 @3 @2 @1 -> @2 @1 @4 @3`          | |
| yoinkn3   | `@3 @2 @1 -> @2 @1 @3`                | [^1] |
| yoinkn4   | `@4 @3 @2 @1 -> @3 @2 @1 @4`          | [^1] |
| cartwheel | `@4 @3 @2 @1 -> @1 @2 @3 @4`          | |
| drop      | `@1 -> nothing`                       | |
| 2drop     | `@2 @1 -> nothing`                    | |
| 3drop     | `@3 @2 @1 -> nothing`                 | |
| 4drop     | `@4 @3 @2 @1 -> nothing`              | |
| zapn2     | `@2 @1 -> @1 /* ~= swap drop */`      | [^2] |
| zapn3     | `@3 @2 @1 -> @2 @1 /* ~= rot drop */` | [^2] |
| zapn4     | `@4 @3 @2 @1 -> @3 @2 @1`             | [^2] |

[^1]: There is no `yoink` or `yoinkn2`. `yoink` would just be `id`, and
`yoinkn2` is `swap`.

[^2]: There is no `zap`, as it is functionally equivalent to `drop` While
`zapn2` and `zapn3` have logical equivalents as documented in the table,
their implementations are able to be optimized and thus stand alone.

## Word, Mode, and Shape Manipulation

These are implemented twice each:

* Once in Build mode, for _statically-initiated_ definitions
* Again in Run mode, for manipulating these within methods (allowing runtime
  metaprogramming)
  

This distinction is important: the Run mode varieties have to trigger special,
performance-impacting behaviors in the Runtime, notably invoking the
Pollutifier and Surveyor systems (used to retain static analysis of
metaprogrammed gluumy code and to find any now-invalidated code caused by the
redefinition). Suffice to say, gluumy encourages (and is designed around)
knowing as much as you can about your Words, Modes, and Shapes at Build time,
but allows for useful runtime metaprogramming - for a price.

| Word                   | Signature                             | Notes |
|------------------------|---------------------------------------|-------|
| Shape!                 | `nothing -> Shape`                    | |
| register-globally      | `Shape Identifier -> nothing`         | |
| register-modally       | `Shape Identifier Mode -> nothing`    | |
| enum-member            | `Identifier Shape -> Shape`           | |
| enum-member-containing | `Shape Identifier Shape -> Shape`     | |
