# gluumy: a hackable, type-safe, minimal-ish language atop Lua

> it's pronounced "gloomy" (or maybe "glue me"), and is spelled in lowercase,
> always

```
 _.    _  |         ._ _       ._  o  _  |_ _|_   |_   _   _  o ._   _
(_|   (_| | |_| |_| | | | \/   | | | (_| | | |_   |_) (/_ (_| | | | _>
       _|                 /           _|                   _|
```

gluumy is an opinionated, conceptually small, "fast enough for most day to day
stuff", strongly-but-inferredly-typed, functional, and legally-unencumbered
language that sits atop Lua, generally running anywhere Lua 5.1+ can. What it
lacks in academic background it tries to make up for in simplicity, ergonomics,
and intuitiveness. Simply put: gluumy is here to Get Shit Done and get out of
the way.

gluumy has just a few core language constructs:

- the function, `->`, with often-inferrable argument and return types
- relatedly, the foreign function, `!->`, to dip into raw Lua when needed
- the shape, `=>`, which is a mix of structs (or tables), interfaces, and
  traits (or mixins)... or, if you prefer, "product types"
- the sum-shape, `~>`, which is an exhaustiveness-checkable shape containing
  one or more disparate-but-related shapes (more on these later!)
- the pipeline, with prepend, `|>`, and append, `|>>`, both supported
- strings (`"like this"`), numbers (`1` and `1.0` are equivalent, as in Lua
  itself), and booleans. Notably missing is `nil`, which is instead covered by
  `Option` and `Result` sum-shapes
- comments (`--`), docstrings (`---`), and compiler hints (`#`)

Notably _not_ present are import statements, to some degree modules (more on
that in a minute), package management at all (more on that later), macros,
decorations, classes, or a number of other concepts found in other languages.
It's not that those things (or the numerous others not listed here) are bad,
per-se, but keeping the language tightly-scoped helps it excel at those things,
rather than trying to be everything to everyone.

As a final note of introduction: gluumy is designed to be usable by developers
at any level from recent bootcamp grad or bedroom hacker, on up to principal
engineers who surely will find countless problems in my implementation. It's
designed to be usable by folks on symmetrical gigabit fibre in the city, or
folks on terrible sattelite connections in the mountains or at sea somewhere.
It's designed to be usable on what are, in mainstream terms, relatively "weak"
computers, such as Raspberry Pis or junked machines you'd find at places like
Re-PC, as well as the hyper-modern beasts you can spend thousands of USD on.
But most of all, it's designed to be _usable_, and not just by "application
developers" - the spirit of gluumy is to a degree inspired by the spirit of
Forth: that programs are built up of flexible and end-user-replaceable bits and
bobs, and are not opaque monoliths handed down by powers that be.

### On Modules and Package Management

gluumy doesn't provide source-level modules, namespaces, or package management.
Instead, [inspired by Joe Armstrong's musings on
Erlang](https://web.archive.org/web/20211122060812/https://erlang.org/pipermail/erlang-questions/2011-May/058768.html),
all identifiers in gluumy live in a single namespace, with functions
disambiguated by their arities, and any further ambiguities resolved in the
entrypoint's `gluumy.conf` using a `z-index`-like priority system. While this
is a dramatic departure from most modern languages (including Lua itself), this
allows for a few cool features and workflows:

- gluumy is monorepo-friendly by default
- without explicit import syntax, moving functions around between files (or
  even repositories) is a non-event
- third party libraries are patchable at compile-time without the need to
  maintain a full fork
- in Joe's words, "contribution to open source can be as simple as contributing
  a single function"

> Dependencies are part of your application and should be reviewed and
> understood as well as your own code, not treated as a foreign black box of
> magic!

gluumy does not, and does not currently plan to, have its own package manager.
Somewhere probably just shy of a billion of these things have already been
written, and some of them are quite good. If you need to pull external
dependencies into your project, consider any of the following options to
retrieve and version them:

- [Nix](https://nixos.org/manual/nix/stable/)
- [Guix](https://guix.gnu.org/)
- [pkgsrc](http://www.pkgsrc.org/)
- Git [Submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules) or
  [Subtrees](https://www.atlassian.com/git/tutorials/git-subtree), if your
  project uses Git
- Whatever your operating system provides, if anything and if working in a
  package-manager-homogenous environment (read: not at work, probably)
- Good old fashioned `curl` and `tar` in a shell script

For more about the aforementioned config file for configuring search paths and
resolving function conflicts, see `man 5 gluumy.conf` (link TBD, and will also
become part of `gluumy doc` eventually).

## This Repo

This repository contains various components:

- `src/stage0` contains the bootstrapping compiler in native-dependency-free
  Lua 5.1. Its output is unoptimized and only debatably readable. _Use of
  `stage0` is not supported for any purpose other than compiling `src/compiler`
  and any gluumy source files it may reference, notably, `lib/core`. Do not
  file bugs against `stage0` unless they directly cause broken `src/compiler`
  builds._ For now, the bootstrapping compiler will be retained such that the
  only native requirement to build the gluumy compiler is a standalone Lua 5.1
  executable, however there is no promise of how long this will last.

- `src/compiler`, `lib/compile`, `lib/tc`, `lib/lsp`, `lib/lint`, and `lib/fmt`
  are the actually-safe and as-production-ready-as-feasible gluumy compiler,
  type-checking engine, [language server](https://langserver.org/), linter, and
  formatter. They are all implemented in gluumy.

- `lib/core` and `lib/std` define the base language and standard library, each
  also implemented in gluumy.

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

> Note: currently, the standard library is basic enough that it'll probably run
> anywhere something resembling PUC Lua can run. It's possible that future
> revisions of gluumy will take optional dependencies on further libraries to
> provide, for example, stdlib bindings to a network request library. TBD, but
> those running gluumy on non-Unix platforms (as well as packagers) should keep
> an eye on project commits/releases for this reason.

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

## Legal Yadda-Yadda

`gluumy` (inclusive of all _original_ code found in this repository) is
released under your choice of either of the following terms. Whichever you
choose, have fun with it, build cool stuff with it, don't exploit your fellow
humans or the world at large with it, and generally don't be an ass within or
outside of the project or anything written with it. Further, while it's not a
license term (and is instead more of a handshake request), I ask that you
please find some other name for significant derivatives of gluumy - I'm
thrilled if you want to target Python or Ruby instead of Lua, but to avoid
confusing folks, please find some other name for your repo than, for example,
`gluumy-py`. Maybe `pyluumy`, I dunno.

- The [Guthrie Public
  License](https://web.archive.org/web/20180407192134/https://witches.town/@ThatVeryQuinn/3540091)
  as written by `@ThatVeryQuinn@witches.town`

- The [Creative Commons Zero 1.0
  dedication](https://creativecommons.org/publicdomain/zero/1.0/), which is
  public domain or maximally-permissive, as your jurisdiction allows.

This repository redistributes the following third-party code, under their
original license terms:

- [luaunit](https://github.com/bluebird75/luaunit), a BSD-licensed unit testing
  library
