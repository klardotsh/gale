# gluumy: a minimalist, type-safe, stack-based programming language

> it's pronounced "gloomy" (or maybe "glue me"), and is spelled in lowercase,
> always

```
 _.    _  |         ._ _       ._  o  _  |_ _|_   |_   _   _  o ._   _
(_|   (_| | |_| |_| | | | \/   | | | (_| | | |_   |_) (/_ (_| | | | _>
       _|                 /           _|                   _|
```

## Philosophy

gluumy is a strongly-typed Forth-inspired language designed around being easy
to learn and teach, logically consistent, reasonably performant, and a general
Get Shit Done vibe.

\< snip for now \>

gluumy does not exist in a zero-sum vaccuum of languages, and is not the
correct tool for every job. It sits somewhere approximately in the altitude of
languages like Python, Ruby, JavaScript, and can even be considered in some
places where Go or Haskell might be used, but is not always an appropriate
replacement for low-level languages in the domains where such precise control
is necessary. It's expected, for example, that a functional gluumy stack is
likely made up of C, Zig, and/or Rust componentry and FFI bindings thereto.

> Please note that gluumy is a personal side project, mostly aimed towards
> developing things I want to build (which generally means command line and/or
> networked applications, and glue scripts). The standard library is thus only
> as complete as is necessary to solve those problems (and, of course, to
> self-host the toolchain). If you find this language interesting and choose to
> use it, be prepared to have to fill in holes in the standard library and/or
> to have to write FFI bindings and most of all, don't expect API stability
> across versions yet.

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

gluumy does not currently have its own package manager. If you need to pull
external dependencies into your project, consider any of the following options
to retrieve and version them:

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

## Thanks

This project didn't happen in a vacuum - it was shaped by the input and advice
and teachings of various people and prior art in computer science. In
alphabetical order, here's some of those people:

- [Devine Lu Linvega](https://wiki.xxiivv.com/site/home.html)
- [@ndpi@merveilles.town](https://merveilles.town/@ndpi) ([on gemini](gemini://gemini.circumlunar.space/~ndpi/))
- [@swift@merveilles.town](https://merveilles.town/@swift)
- [Phil Hagelberg aka technomancy](http://technomancy.us/)

## Legal Yadda-Yadda

`gluumy` (inclusive of all _original_ code found in this repository) is
released under the Creative Commons Zero 1.0 dedication, found in `COPYING`.
While not a legally binding mandate, I ask that you have fun with it, build
cool stuff with it, don't exploit your fellow humans or the world at large with
it, and generally don't be an ass within or outside of the project or anything
written with it.
