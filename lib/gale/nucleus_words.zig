// Copyright (C) 2023 Josh Klar aka "klardotsh" <josh@klar.sh>
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
// REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
// FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
// INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
// LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
// OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
// PERFORMANCE OF THIS SOFTWARE.

const std = @import("std");
const Allocator = std.mem.Allocator;
const testAllocator: Allocator = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

const _stack = @import("./stack.zig");
const test_helpers = @import("./test_helpers.zig");

const InternalError = @import("./internal_error.zig").InternalError;
const Runtime = @import("./runtime.zig").Runtime;
const StackManipulationError = _stack.StackManipulationError;
const Word = @import("./word.zig").Word;
const WordSignature = @import("./word_signature.zig").WordSignature;

// As a general rule, only write tests for methods in this file that actually
// do something noteworthy of their own. Some of these words call directly into
// Stack.whatever() without meaningful (if any) handling, duplicating those
// tests would be pointless.

/// @EQ ( @2 @1 <- Boolean )
///
/// Non-destructive equality check of the top two items of the stack. At this
/// low a level, there is no type system, so checking equality of disparate
/// primitive types will panic.
pub fn EQ(runtime: *Runtime) !void {
    const peek = try runtime.stack_peek_pair();

    if (peek.far) |bottom| {
        _ = try peek.near.assert_same_kind_as(bottom);
        try runtime.stack_push_bool(true);
        return;
    }

    return StackManipulationError.Underflow;
}

test "EQ" {
    var runtime = try Runtime.init(testAllocator);
    defer runtime.deinit();
    try runtime.stack_push_uint(1);
    // Can't compare with just one Object on the Stack.
    try expectError(StackManipulationError.Underflow, EQ(&runtime));
    try runtime.stack_push_uint(1);
    // 1 == 1, revelatory, truly.
    try EQ(&runtime);
    try expect((try runtime.stack_peek_pair()).near.*.Boolean);
    // Now compare that boolean to the UnsignedInt... or don't, preferably.
    try expectError(InternalError.TypeError, EQ(&runtime));
}

/// @DROP ( @1 -> nothing )
pub fn DROP(runtime: *Runtime) !void {
    try runtime.stack_wrangle(.DropTopObject);
}

/// @DUP ( @1 -> @1 )
pub fn DUP(runtime: *Runtime) !void {
    try runtime.stack_wrangle(.DuplicateTopObject);
}

/// @2DUPSHUF ( @2 @1 -> @2 @1 @2 @1 )
pub fn TWODUPSHUF(runtime: *Runtime) !void {
    try runtime.stack_wrangle(.DuplicateTopTwoObjectsShuffled);
}

/// @LIT ( @1 -> Word )
///
/// Wraps any value type in an anonymous word which will return that value when
/// called. Generally useful when defining words which need to refer to
/// numbers, strings, symbols, etc. at runtime.
///
/// Used to be called @HEAPWRAP, which might hint at why it's implemented the
/// way it is.
pub fn LIT(runtime: *Runtime) !void {
    // TODO: Should these return Bounded versions instead, since we inherently
    // already know the word's return value?
    const banished = try runtime.stack_pop_to_heap();
    const word = try runtime.word_from_heaplit_impl(banished, switch (banished.*) {
        .Opaque => @panic("unimplemented"), // TODO
        .Boolean => .{ .Declared = runtime.get_well_known_word_signature(.NullarySingleUnboundedBoolean) },
        .Float => .{ .Declared = runtime.get_well_known_word_signature(.NullarySingleUnboundedFloat) },
        .SignedInt => .{ .Declared = runtime.get_well_known_word_signature(.NullarySingleUnboundedSignedInt) },
        .UnsignedInt => .{ .Declared = runtime.get_well_known_word_signature(.NullarySingleUnboundedUnsignedInt) },
        .String => .{ .Declared = runtime.get_well_known_word_signature(.NullarySingleUnboundedString) },
        .Symbol => .{ .Declared = runtime.get_well_known_word_signature(.NullarySingleUnboundedSymbol) },
        .Word => .{ .Declared = runtime.get_well_known_word_signature(.NullarySingleUnboundedWord) },
    });
    try runtime.stack_push_raw_word(word);
}

test "LIT" {
    var runtime = try Runtime.init(testAllocator);
    defer runtime.deinit_guard_for_empty_stack();

    // First, push an UnsignedInt literal onto the stack
    try runtime.stack_push_uint(1);

    // Create and yank a HeapLit word from that UnsignedInt
    try LIT(&runtime);
    var lit_word = try runtime.stack_pop();
    defer lit_word.deinit(testAllocator);

    // That word should have been the only thing on the stack
    try expectError(StackManipulationError.Underflow, runtime.stack_pop());

    // Now, run the word - three times, for kicks...
    try runtime.run_word(lit_word.Word);
    try runtime.run_word(lit_word.Word);
    try runtime.run_word(lit_word.Word);

    // ...and assert that the UnsignedInt was placed back onto the stack all
    // three times.
    const top_three = try runtime.stack_pop_trio();
    try expectEqual(@as(usize, 1), top_three.near.UnsignedInt);
    try expectEqual(@as(usize, 1), top_three.far.UnsignedInt);
    try expectEqual(@as(usize, 1), top_three.farther.UnsignedInt);
}

/// @SWAP ( @2 @1 -> @2 @1 )
pub fn SWAP(runtime: *Runtime) !void {
    try runtime.stack_wrangle(.SwapTopTwoObjects);
}

test {
    std.testing.refAllDecls(@This());
}
