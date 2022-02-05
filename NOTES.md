just a scratchpad of my notes on things I'd like to explore, implement, whatever.


## docstring stuff

change docstring syntax consistently from:

```
--- line one
--- line two
```

to

```
---
scdoc formatted stuff goes here, though the attached function (and section 3),
plus a Description header, will be prepended automatically

## Example

...

```

whether this means I take a dependency on system-wide scdoc, fork scdoc to
expose it as a library to Lua 5.1 / LuaJIT, write a pure-gluumy implementation
of scdoc, or something else, I'm not sure yet. any but the latter option would
mean docstring generation would be a PC-only (and probably Unix-only) thing,
which is _likely_ fine as the gluumy compiler running on, say, a
microcontroller is a pipe-dream right now and not something I'm planning _too_
heavily around beyond the separation of core and std

## gluumy cli notes

`gluumy build` parses `gluumy.conf` and the environment to figure out search
paths and any prioritization overrides necessary and passes off to `gluumyc`.
not sure yet whether to do a process per file (and then a linker phase) or to
do all in one. the giant monolith, if fast enough, would be nice in that
there's less to keep track of, and it may well be necessary because of the
flavor of type inference and arity-disambiguation I'm aiming for

`gluumy man` wraps system `man` and can explore manual entries for anything in
the project's search path. thus, `gluumy man println` would resolve to the
docstring-generated `man 3` entry for whatever `println` resolves to.

`gluumy man explore` can be a TUI manpage finder

`gluumy man explore-web` can be a web flavor of ^ perhaps (JIT roff -> html
conversion maybe?)

`gluumy repl` should drop into a repl with all known identifiers available. all
the same prep as if we were going to compile, but just... don't until needed. I
guess this means gluumy will have a live interpreter, woo hoo? what better way
to provide iterative design and explorability, though?

`gluumy fmt` should basically not be configurable at all. it should probably
also understand lua within FFI blocks :(

## dependencies

should provide an example of how to bring in external dependencies; the readme
alludes to it but a clear example would be nice

also need to document gluumy.conf and especially that lua-module-required thing

## coroutines? concurrency? parallelism? anything?

the language is reasonably well suited to offering either or both schools of
thought with the focus on immutable, simple data structures, and of course
being built on Lua provides some niceties too, but there's also the C-call
boundary thing to keep in mind (it'll be a gnarly runtime crash gluumy can't
catch) with coroutines, so if those will be exposed, thought should be given to
keep footguns away
