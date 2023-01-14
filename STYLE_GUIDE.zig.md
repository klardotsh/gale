# Gale style guide for Zig code

In general, `zig fmt` is the final arbiter of truth for things like line
length, indentation, etc. This document describes things we have control over
that `zig fmt` won't overwrite. Note that @klardotsh is the sole arbiter of
aesthetics (and indeed all things in the language); words like "Pretty",
"Ugly", etc. are judged by his eyes. They are capitalized in this document to
emphasize their fuzzy-subjective-ness.

## Comment the hell out of everything

This one doesn't even require an example, it's just the First Commandment of
this codebase. Even if you screw up the entire rest of this style guide, follow
this point.

You see [Jones Forth](https://github.com/nornagon/jonesforth)? You see how it
reads like the Lord of the freakin' Rings? Do that. My personal philosophy on
comments is to be far more liberal with them than is generally taught in
schools or in (startup-land, at least) industry, and holds much closer to [the
opinions of antirez](http://antirez.com/news/124), of Redis fame. We're writing
system software here, which is an inherently non-trivial domain. Help people
who might be coming from higher-level languages or less programming experience
understand what we're doing, and empower them to contribute (or build their own
low-level stuff!). We all started somewhere.

## All constants with semantic meaning should be named

Giving constants names makes their intent obvious and survives the renames of
functions. It also makes refactoring to make constants modifiable at build time
(with `build.zig` arguments) easier.

```zig
// Bad: why 8? and why can't I change this anywhere???
const foo = [_]u8{0} ** 8;

// Fixed: magic constant now has a name, and overrides could theoretically be
// plumbed without digging into the code around foo itself.
const NUMBER_OF_FOOS = 8; // in reality there's 5, plus one. IYKYK, RIP.
// ...
const foo = [_]u8{0} ** NUMBER_OF_FOOS;
```

## Don't make visually clutterful blocks

Except when it would cause line length to exceed 80ish characters or would just
otherwise look Ugly (such as by doing too many things in too little space at
the expense of reading comprehension), "one-liner" statements should be just
that: one line. This does not supercede "Give things vertical breathing room",
below: single-line statements should have empty lines immediately above and
below them, with no exceptions.

Good:

```zig
// Good: trivial if statement that does exactly one thing and fits well under
// 80 characters.
if (!any_alive_remaining) alloc.free(compound);

// Bad: there's just too much going on in one line here: a function call, a
// capture group, another function call, and an assignment. Further, in the
// context this was pulled from, the line reaches 97 characters counting
// indentation.
while (symbol_iter.next()) |entry| _ = entry.decrement_and_prune(.FreeInner, self.alloc);

// Fixed:
while (symbol_iter.next()) |entry| {
    _ = entry.decrement_and_prune(.FreeInner, self.alloc);
}
```

## Give things vertical breathing room

Unlike in IRC, extensive use of the `Enter` key is welcome in our Zig code
where it breaks a function up into logical chunks that don't otherwise make
sense to split into their own functions. Further, branching and looping
statements (`if`, `switch`, `for`, `while`) should **always** be separated from
other code with blank lines on both sides, with no exceptions. Note the
interaction of this rule with "Don't make visually clutterful blocks" above.

```zig
// Bad: This reads like a text from someone who just learned how texting works
// and doesn't bother to use punctuation, newlines, or multiple messages in
// sequence.
var runtime = try Runtime.init(testAllocator);
defer runtime.deinit();
const heap_for_word = try runtime.word_from_primitive_impl(&push_one);
runtime.stack = try runtime.stack.do_push(Object{ .Word = heap_for_word });
runtime.stack = try runtime.stack.do_push(Object{ .Boolean = true });
try CONDJMP(&runtime);
const should_be_1 = try runtime.stack.do_pop();
try expectEqual(@as(usize, 1), should_be_1.UnsignedInt);
runtime.stack = try runtime.stack.do_push(Object{ .Word = heap_for_word });
runtime.stack = try runtime.stack.do_push(Object{ .Boolean = false });
try CONDJMP(&runtime);
try expectError(StackManipulationError.Underflow, runtime.stack.do_pop());

// Fixed: splits that dense block up into logical sections:
// - High level initialization (since this excerpt is from a test, runtime
//   isn't coming as a function argument as it normally might)
// - Local initialization
// - Logical unit: testing truthy case
// - Logical unit: testing falsey case
var runtime = try Runtime.init(testAllocator);
defer runtime.deinit();

const heap_for_word = try runtime.word_from_primitive_impl(&push_one);

runtime.stack = try runtime.stack.do_push(Object{ .Word = heap_for_word });
runtime.stack = try runtime.stack.do_push(Object{ .Boolean = true });
try CONDJMP(&runtime);
const should_be_1 = try runtime.stack.do_pop();
try expectEqual(@as(usize, 1), should_be_1.UnsignedInt);

runtime.stack = try runtime.stack.do_push(Object{ .Word = heap_for_word });
runtime.stack = try runtime.stack.do_push(Object{ .Boolean = false });
try CONDJMP(&runtime);
try expectError(StackManipulationError.Underflow, runtime.stack.do_pop());
```
