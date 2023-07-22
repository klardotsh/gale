# Gale: small-but-mighty, strongly-typed, concatenative development at storm-force speed

Gale is a [concatenative programming
language](https://en.wikipedia.org/wiki/Concatenative_programming_language)
which:

- Has a strong,
  [dynamic](https://en.wikipedia.org/wiki/Type_system#Dynamic_type_checking_and_runtime_type_information),
  and generally
  [structural](https://en.wikipedia.org/wiki/Structural_type_system) type
  system that offers a moderate degree of type inference.

- Is designed interactively-first, with REPL and [Language
  Server](https://en.wikipedia.org/wiki/Language_Server_Protocol) experiences
  as first-class citizens, and as such encourages rapid prototyping and
  experimentation.

- Can be embedded within Zig and C applications (and those written in languages
  supporting C FFI).

- Sports a very small implementation: currently well under 5k lines of Zig
  (subtracting comments and blank lines) gets a runtime off the ground.

<!-- TODO: ^ count whatever it takes to get basic I/O, a standard library, etc. -->

- Is extremely permissively licensed (`0BSD`, public domain equivalent)

## What's it look like?

See the `sketches/` tree for now, which is in a constant state of flux and not
necessarily always kept up to date with what I'm aiming for, but I try.

## Navigating this repo

- `lib/gale` is a pure-Zig implementation of the Gale nucleus as a library
- `src/gale` builds on these to provide a thin CLI that works with the usual
  stdin/stdout/stderr
- `tests/` includes various end-to-end tests of language functionality that
  didn't cleanly fit as unit tests in the above categories

## Supporting Gale's Development

Currently, Gale is just a nights-and-weekends side project whenever my rather
busy life allows, and as with any hobby, I don't expect payment for it. For now,
simply riffing ideas with me and experimenting with Gale as it grows is payment
enough. If you really insist you want to financially support Gale in this
extremely early phase, there's a LiberaPay link in the `.github/` tree.

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
