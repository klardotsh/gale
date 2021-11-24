# gluumy: a type-safe, minimal-ish, and hackable language targeting Lua

> it's pronounced "gloomy" (or maybe "glue me"), and is spelled in lowercase,
> always

```
 _.    _  |         ._ _       ._  o  _  |_ _|_   |_   _   _  o ._   _
(_|   (_| | |_| |_| | | | \/   | | | (_| | | |_   |_) (/_ (_| | | | _>
       _|                 /           _|                   _|
```

gluumy is a small, "fast enough for most day to day stuff", quasi-functional
(and the rest trait-and-interface-based) language that compiles to Lua, and
thus should run mostly anywhere Lua 5.1 (plus some compatibility modules, see
below) can. It probably won't win many benchmarks, it may or may not be most
appropriate for all or any domains, and it certainly has no basis in academia
nor a founder with any background in programming language design. What it lacks
in those departments it tries to make up for in ease of learning,
understanding, tinkering, and Just Getting Shit Done.

It takes influence from languages like Gleam, Rust, Ruby, and Lua, and aims to
create a language that is small, understandable in a day or so, easy to hack
on, safe, and expressive. If you're here for the latest and greatest in
programming language research or to make use of your degree in theoretical
mathematics (or even category theory), this is not the project you're looking
for. If you've ever wanted a subset of the type system of Rust with an offshoot
of ML-esque syntax and the mental-model simplicity of Lua, you might be in
the right place.

Now, to toot gluumy's horn on its awesome traits and features:

- No exceptions or `nil`, instead offering `Result` and `Option` types,
  respectively

  * It's worth noting that "no exceptions" doesn't mean foreign code wrapped by
	gluumy's FFI contraptions can't cause runtime panics. FFI is considered
	inherently unsafe for a reason - gluumy can't save you from things it can't
	control!

- A small-but-useful standard library that, in general, tries to offer as close
  to one way to solve a problem as possible. Learn a few patterns and you
  should be good to go for `core` and `std`.

- A trait-based functional-ish paradigm encouraging free functions accepting as
  broad of interfaces as possible as opposed to narrow member functions.

- To complement said paradigm, a strong type inference system that often
  eliminates the need for type annotations entirely (indeed, much of the
  standard library lacks explicit annotations, and instead happily works on any
  inputs that fit the inferred expected shape).

- Complementing almost all of the above, two pipeline operators (`|>` and
  `|>>`) to prepend and append (respectively) the results of one function to
  the arguments of another (those who have used Gleam, Elixir, or F# shuold
  feel at home with this).

- It all becomes Lua in the end, allowing for easy portability, inspectability,
  and optimization (by way of alternative Lua implementations such as LuaJIT).
  Forget about cross-compilation woes from many languages **and** many of the
  runtime exceptions from many others.

... and as a bonus, the spec, implementation, and standard library are all
[Copyfree](https://copyfree.org/) software.

This repository contains various components:

- `src/stage0` contains the bootstrapping compiler in dependency-free Lua 5.1.
  This is an extremely unsafe, raw translator of gluumy source to Lua source.
  Its output is unoptimized and only debatably readable. It also assumes all
  input code is type-safe. _Use of `stage0` is not supported for any purpose
  other than compiling `src/compiler` and any gluumy source files it may
  reference, notably, `lib/core`. Do not file bugs against `stage0` unless they
  directly cause broken `src/compiler` builds._ For now, the bootstrapping
  compiler will be retained such that the only requirement to build the gluumy
  compiler is a Lua 5.1 build, however there is no promise of how long this
  will last.

- `src/compiler`, `lib/compile`, `lib/tc`, `lib/lsp`, `lib/lint`, and `lib/fmt`
  are the actually-safe and as-production-ready-as-feasible gluumy compiler,
  type-checking engine, [language server](https://langserver.org/), linter, and
  formatter. They are all implemented in gluumy.

- `lib/core` and `lib/std` define the core (always present and in-scope via `:`
  sugar) and standard (optional, by import) libraries, each also implemented in
  gluumy.

> Please note that gluumy is a personal side project, mostly aimed towards
> developing things I want to build (which generally means command line and/or
> networked applications, and glue scripts). The standard library is thus only
> as complete as is necessary to solve those problems (and, of course, to
> self-host the toolchain). If you find this language interesting and choose to
> use it, be prepared to have to fill in holes in the standard library and/or
> to have to write FFI bindings and typedefs to Lua modules, and most of all,
> don't expect API stability across versions yet.

## Dependencies

- Any Lua compatible with the intersection of the [LuaJIT-defined subset of Lua
  5.2](https://luajit.org/extensions.html) and
  [lua-compat-5.2](https://github.com/keplerproject/lua-compat-5.2/). In
  practical terms, on most Unixes this means LuaJIT, Lua 5.2, Lua 5.1 with
  `compat52`, or anything else backwards-compatible to those APIs. Clear as
  mud, thanks Lua fragmentation!

## Alternatives

I find gluumy to fill a somewhat unique niche within the Lua ecosystem, but you
may wish to compare it against some related art in the community:

- [Teal](https://github.com/teal-language/tl) is by far the closest relative in
  the ecosystem, written by @hishamhm who also brought us `htop`, `luarocks`,
  and various Lua libraries. Hisham's work is routinely awesome, so give it a
  look. Teal, just like gluumy, compiles to Lua after its type-checking stage.
  gluumy deviates from Teal in a few key areas:

  * Clearly, the syntax. Teal retains Lua's overall syntax style, with a few
	keywords and symbols added as necessary. gluumy opts for a bespoke hybrid
	of ML-esque, LiveScript-esque, Ruby-esque, Rust-esque, and anything else to
	suit my personal taste. While the syntax should be understandable to those
	with backgrounds in Lua plus at least one of those families, it will _not_
	feel familiar to those coming from a pure-Lua background.

  * Teal [implicitly allows `nil` for all
	types](https://github.com/teal-language/tl/blob/68d9e8c57b6ee265b2353b179956a5e65e7936cc/docs/tutorial.md),
	whereas gluumy lacks a `nil` value entirely, instead requiring the use of
	[option types](https://en.wikipedia.org/wiki/Option_type). Teal's decision
	was made in the spirit of maximum compatibility with existing Lua code
	which depends on such looseness. gluumy is not inherently compatible with
	existing Lua code without at least some degree of bindings and glue, and
	thus was able to take a stricter stance.

- [Pallene](https://github.com/pallene-lang/pallene) aims to be a "sister
  language for Lua", offering AOT compilation to dynamically-loadable native
  modules. It seems to target creating a more-type-safe data layer, called into
  by existing Lua code
