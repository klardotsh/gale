# gluumy: a type-safe, semi-minimal, and hackable language targeting Lua-ish

> it's pronounced "gloomy", and is spelled in lowercase, always

gluumy is an intentionally "good enough for lots of things, excellent probably
at only a few things" language designed by and for @klardotsh, which takes
influence from languages such as [Gleam](https://gleam.run/),
[TypeScript](https://www.typescriptlang.org/),
[LiveScript](https://livescript.net/), and to a more limited degree,
[Rust](https://www.rust-lang.org/) and [Zig](https://ziglang.org/). It's
suitable as a type-safe scripting language, a language for reasonably-scoped
command line tools, and can probably take a decent stab at small-scale
networked utilities. However, gluumy is an intentionally small language
designed to be understandable (and, crucially, buildable) by a single human (or
a very, very small group of them), so probably won't have all the creature
comforts one may be used to from other, beefier languages, and is likely
entirely unsuited for some domains. That's fine - there's a multitude of
wonderful languages out there, gluumy will not replace all of them for all
things.

If you're not aforementioned author but still find gluumy appealing and would
like to use it, note that it's not stable yet, and is currently suited only for
those willing to get their hands dirty and build the standard library (and
indeed, much of the compiler and LSP tooling) out themselves.

gluumy intends to eventually be "nearly-complete". While the world around us
will of course change (including the platforms gluumy runs on) and these
changes may necessitate standard library changes (or in an extreme scenario,
perhaps even core language spec changes), it is hoped that such changes
eventually can slow to a bit of a crawl.

gluumy code compiles down to what I'll describe as "Lua-ish" - the syntax will
all be valid Lua 5.1, but it will assume the environment provides the gluumy
`Prelude`. The `Prelude` is independent of the standard library and is somewhat
analogous to `core` in Rust, defining various types and structures that are not
part of the Lua spec. They may be written in the language and style of the
host's choice: a pure-Lua `Prelude` is provided here, but a more performant
INSERT IMPLEMENTATION LANGUAGE HERE-based native extension for LuaJIT 2.1 is
available at INSERT WHERE TO FIND IT HERE.

For convenience and for interopability with embedded Lua runtimes (perhaps that
of [Neovim](https://neovim.io/)'s config files, or your favorite moddable video
game), the pure-Lua `Prelude` can optionally be automatically embedded into the
output source with `--embedded-prelude`.

### A note about Lua versions

Of note, Lua 5.1 is explicitly targeted for a few reasons: firstly, it's the
lowest common denominator between PUC Lua, LuaJIT, and Zua (and likely other
embedded custom Lua implementations), secondly it's philosophically an
extremely simple version of the language (which helps keep gluumy's code
generation straightforward to understand), and thirdly, because it's been
around and battle-tested for ages. If it ain't broke, I don't have time to fix
it.

This policy will remain in place until one of three things happens:

- the costs of retaining 5.1 support outweigh the benefits added by some newer
  version of the language spec
- there are multiple reasonably-well-used implementations of some newer version
  of Lua, and gluumy can actually make use of the new language features somehow
- Lua 5.1 can no longer be reasonably expected to build on modern systems
  **and** the then-current implementations of Lua have lost
  backwards-compatibility with Lua 5.1. Both seem unlikely within the next
  decade, but of course the biggest lesson of the 2020s is that Anything Can
  Happen, so who knows.

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
