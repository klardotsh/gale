# gluumy Core Words Reference

This document describes all words in gluumy's Core - in the reference
implementation, this refers to any words provided by the Kernel or Prelude.

All word signatures in this document use the fully qualified right-pointing
form, which is to say, the deque will be taken from the arrow leftwards, and
given from the arrow rightwards. Thus,

    @2 @1 -> @1 @2
    
Will take a generic (kind 1) from the top of the deque, then another generic
(kind 2) from the now-top of the deque, do... whatever with them, and
eventually place objects of kind 1 and kind 2, respectively and orderly, onto
the top of the deque, performing an effective swap. Technically word signatures
alone aren't enough to know that @1 and @1 are the same objects in memory:
they'll simply be the same Shape. You'll need to read the docs and/or
implementation to make "object in memory" assertions.

## Generic Deque Manipulation

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
| yoinkn3   | `@3 @2 @1 -> @2 @1 @3`                | [1] |
| yoinkn4   | `@4 @3 @2 @1 -> @3 @2 @1 @4`          | [1] |
| cartwheel | `@4 @3 @2 @1 -> @1 @2 @3 @4`          | |
| drop      | `@1 -> nothing`                       | |
| 2drop     | `@2 @1 -> nothing`                    | |
| 3drop     | `@3 @2 @1 -> nothing`                 | |
| 4drop     | `@4 @3 @2 @1 -> nothing`              | |
| zap       | `@1 -> nothing /* == drop */`         | |
| zapn2     | `@2 @1 -> @1 /* == swap drop */`      | |
| zapn3     | `@3 @2 @1 -> @2 @1 /* == rot drop */` | |
| zapn4     | `@4 @3 @2 @1 -> @3 @2 @1`             | |

[1]: There is no `yoink` or `yoinkn2`. `yoink` would just be `id`, and
`yoinkn2` is `swap`.

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

- Shape! nothing -> Shape
- register-globally Shape Identifier -> nothing
- register-modally Shape Identifier Mode -> nothing
- enum-member Identifier Shape -> Shape
- enum-member-containing Shape Identifier Shape -> Shape
