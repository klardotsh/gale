# Gale

Strongly-typed, minimal-ish, stack-based development at storm-force speed.

## Philosophy

Gale is a general-purpose, memory-managed language designed around being easy
to learn and teach, logically consistent, reasonably performant, and around a
general Get Stuff Done vibe. I like to think it sits somewhere between Python,
Lua, and Rust on several axes: it enables rapid development and gets
overly-technical details out of the programmer's way, while also being
reasonably performant and having a strong type system that can make a number of
assurances about the quality of a codebase. It's also reasonably embeddable
into other languages: Zig is a given (the `gale` CLI is actually just a thin
wrapper around `gale` the library!), but anything that can speak a C FFI will
also be able to embed Gale reasonably well.

## What's it look like?

I realized recently that I never keep the `examples/` tree fully up to date,
but for now, it's the best I can offer you. Coming soon :)

## Navigating this repo

- `lib/gale` is a pure-Zig implementation of the Gale nucleus as a library
- `lib/prelude` (not implemented yet) is a pure-Gale implementation of the
  Gale standard library
- `src/gale` builds on these to provide a thin CLI that works with the usual
  stdin/stdout/stderr
- `tests/` includes various end-to-end tests of language functionality that
  didn't cleanly fit as unit tests in the above categories

## Legal Yadda-Yadda

Gale's canonical implementation and standard library is released under the
[Zero-Clause BSD License](https://tldrlegal.com/license/bsd-0-clause-license),
distributed alongside this source in a file called `COPYING`, and also found
at the top of each source file.

Further, while not a legally binding mandate, I ask that you have fun with it,
build cool stuff with it, don't exploit your fellow humans or the world at
large with it, and generally don't be an ass within or outside of the project
or anything written with it. And if you want to give attribution, it's
of course also appreciated.
