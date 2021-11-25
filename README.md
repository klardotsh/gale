# gluumy: a type-safe, minimal-ish, and hackable language targeting Lua

> it's pronounced "gloomy" (or maybe "glue me"), and is spelled in lowercase,
> always

```
 _.    _  |         ._ _       ._  o  _  |_ _|_   |_   _   _  o ._   _
(_|   (_| | |_| |_| | | | \/   | | | (_| | | |_   |_) (/_ (_| | | | _>
       _|                 /           _|                   _|
```

gluumy is a small, "fast enough for most day to day stuff", strongly-typed,
functional language that compiles to Lua, running anywhere Lua 5.1+ can. What
it lacks in academic background it tries to make up for in simplicity,
ergonomics, and intuitiveness. Simply put: gluumy is here to Get Shit Done and
get out of the way. As a bonus, the spec, implementation, and standard
libraries are all [Copyfree](https://copyfree.org/) software.

gluumy has just a few core language constructs:

- the function, with often-inferrable types
- relatedly, the foreign function (to dip into raw Lua when needed)
- the shape, which is a mix of structs (or tables), interfaces, and traits (or
  mixins)... or, if you prefer, "product types"
- the sum-shape, which is an exhaustiveness-checkable shape containing one or
  more disparate-but-related shapes (more on these later!)
- the pipeline (with prepend, `|>`, and append, `|>>`, both supported)
- strings, numbers, and booleans (no `nil`!)
- of course, comments and docstrings

Notably _not_ present are import statements, modules at all (for the most
part), package management at all (more on that later), macros, decorations,
classes, pragmas, or a number of other things found in other languages. gluumy
provides a solid base to build great software on and the tooling to help you do
it, while cutting out complexity anywhere it can.

### On Modules and Package Management

gluumy doesn't provide modules, namespaces, or package management. Instead,
[inspired by Joe Armstrong's musings on
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

Further, if modules don't exist, packages technically don't either. gluumy does
not, and does not ever plan to, have its own package manager. Somewhere
probably just shy of a billion of these things have already been written, and
many of them are quite good. If you choose to use gluumy (cool!) and need
external dependencies, consider any of the following options to retrieve and
version them:

- [Nix](https://nixos.org/manual/nix/stable/)
- [Guix](https://guix.gnu.org/)
- [pkgsrc](http://www.pkgsrc.org/)
- Git [Submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules) or
  [Subtrees](https://www.atlassian.com/git/tutorials/git-subtree), if your
  project uses Git
- Whatever your operating system provides, if anything and if working in a
  package-manager-homogenous environment (read: not at work, probably)
- Good old fashioned `curl` and `tar` in a shell script

For more about the aforementioned "module" config file, see `man 5
gluumy.conf` (link TBD).

## This Repo

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
