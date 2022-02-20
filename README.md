# gluumy: a hackable, type-safe, minimal-ish, high-level programming language

> it's pronounced "gloomy" (or maybe "glue me"), and is spelled in lowercase,
> always

```
 _.    _  |         ._ _       ._  o  _  |_ _|_   |_   _   _  o ._   _
(_|   (_| | |_| |_| | | | \/   | | | (_| | | |_   |_) (/_ (_| | | | _>
       _|                 /           _|                   _|
```

gluumy is an opinionated, conceptually small, "fast enough for most day to day
stuff", strongly-typed, functional, interpreted, and legally-unencumbered
language that sits atop Lua, generally running anywhere Lua 5.1+ can. What it
lacks in academic background it tries to make up for in simplicity, ergonomics,
and intuitiveness. Simply put: gluumy is here to Get Shit Done and get out of
the way.

gluumy has just a few core language constructs:

- the function, which is strongly (but inferredly) typed, curryable, and can
  optionally be implemented in raw Lua when necessary (perhaps to wrap a C FFI
  library or reuse a Lua library)
- the shape, which combines aspects of several concepts from other languages:
    * structs, tables, dictionaries, hashes, etc.
	* interfaces
	* traits and mixins
	* generally, "product types"
- the sum-shape, which is roughly analogous to the concept of enums in
  ML-inspired languages or Rust in that they are exhaustiveness-checkable
  containers of related shapes
- of course, the primitives:
    * strings (`"like this"`)
	* numbers (`1` and `1.0` are equivalent, as in Lua itself' and so are
	  `1_000_000.000_000` and `1000000`)
	* booleans
	* _notably missing is `nil`, which is instead covered by the `Option` and
	  `Result` sum-shapes_
- miscellanea:
    * comments (`--`), which run to the end of the line
    * docstrings,
      [scdoc](https://git.sr.ht/~sircmpwn/scdoc/tree/master/item/scdoc.5.scd)-formatted
      blocks bookended by `---`
    * compiler hints (`#`) to, for example, map primitives to gluumy-side
      shapes

The language is primarily catered towards interpreted usecases. While it can be
ahead-of-time compiled down to bare Lua if necessary (perhaps to target a
microcontroller with minimal flash memory available), it's generally expected
that a gluumy application work in some ways similar to a Forth one: everything,
including the code generator and typechecking logic, is available at runtime,
and can be overridden by the end user if so desired (see "On Modules and
Package Management" below).

This language is designed to be usable by developers at any level from recent
bootcamp grad or bedroom hacker, on up to principal engineers who surely will
find countless problems in my implementation. It's designed to be usable by
folks on symmetrical gigabit fibre in the city, or folks on terrible sattelite
connections in the mountains or at sea somewhere. It's designed to be usable on
what are, in mainstream terms, relatively "weak" computers, such as Raspberry
Pis or junked machines you'd find at places like Re-PC, as well as the
hyper-modern beasts you can spend thousands of USD on. But most of all, it's
designed to be _usable_, and not just by "application developers" - the spirit
of gluumy is to a degree inspired by the spirit of Forth: that programs are
built up of flexible and end-user-replaceable bits and bobs, and are not opaque
monoliths handed down by powers that be.

Finally: gluumy does not exist in a zero-sum vaccuum of languages, and is not
the correct tool for every job. It sits somewhere approximately in the altitude
of languages like Python, Ruby, JavaScript, and can even be considered in some
places where Go or Haskell might be used, but is _not_ an appropriate
replacement for low-level languages in the domains where such low-level control
is necessary. It's expected, for example, that a functional gluumy stack is
likely made up of C, Zig, and/or Rust componentry, and some gluumy "libraries"
may be best implemented as type-hint wrappers around FFI modules implemented in
one of those languages.

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

- `bootstrap` contains the bootstrapping compiler, implemented in Rust. It is
  **only** supported for the purposes of bootstrapping the official gluumy
  compiler that is, itself, implemented in gluumy. As with the official
  compiler, it outputs Lua code, and thus standing up gluumy on a new
  architecture does not actually require Rust support on that architecture,
  provided Lua source generated on another system is fair game.

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
