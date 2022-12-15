// gluumy's canonical implementation and standard library is released to the
// public domain (or your jurisdiction's closest legal equivalent) under the
// Creative Commons Zero 1.0 dedication, distributed alongside this source in a
// file called COPYING.

const std = @import("std");
const Allocator = std.mem.Allocator;
const testAllocator: Allocator = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

const Object = @import("./object.zig").Object;
const PrimitiveWord = @import("./word.zig").PrimitiveWord;
const Stack = @import("./stack.zig").Stack;
const StackManipulationError = @import("./stack.zig").StackManipulationError;

// As a general rule, only write tests for methods in this file that actually
// do something noteworthy of their own. Some of these words call directly into
// Stack.whatever() without meaningful (if any) handling, duplicating those
// tests would be pointless.

/// @BEFORE_WORD ( Word -> nothing )
///                |
///                +-> ( Symbol <- nothing )
pub fn BEFORE_WORD(_: *Stack) !void {
    // TODO
}

// @CONDJMP ( Word Boolean -> nothing )
//
// Immediately executes the near word if the boolean is truthy, doing nothing
// otherwise. Consumes both inputs.
//
// See also: @CONDJMP2
pub fn CONDJMP(_: *Stack) !void {
    // TODO
}

// @CONDJMP2 ( Word Word Boolean -> nothing )
//
// Immediately executes the near word if the boolean is truthy, and the far
// word otherwise. Consumes all three inputs.
//
// See also: @CONDJMP
pub fn CONDJMP2(_: *Stack) !void {
    // TODO
}

/// @EQ ( @2 @1 <- Boolean )
///
/// Non-destructive equality check of the top two items of the stack. At this
/// low a level, there is no type system, so checking equality of disparate
/// primitive types will panic.
pub fn EQ(stack: *Stack) !*Stack {
    const peek = try stack.do_peek_pair();

    if (peek.bottom) |bottom| {
        return try stack.do_push(Object{ .Boolean = try peek.top.eq(bottom) });
    }

    return StackManipulationError.Underflow;
}

test "EQ" {
    var stack = try Stack.init(testAllocator, null);
    defer stack.deinit();
    _ = try stack.do_push(Object{ .UnsignedInt = 1 });
    // Can't compare with just one Object on the Stack.
    try expectError(StackManipulationError.Underflow, EQ(stack));
    _ = try stack.do_push(Object{ .UnsignedInt = 1 });
    // 1 == 1, revelatory, truly.
    stack = try EQ(stack);
    try expect((try stack.do_peek_pair()).top.*.Boolean);
    // Now compare that boolean to the UnsignedInt... or don't, preferably.
    try expectError(error.CannotCompareDisparateTypes, EQ(stack));
}

// TODO: comptime away these numerous implementations of DEFINE-WORD-VA*, I
// gave it a go upfront and wound up spending 30 minutes fighting the Zig
// compiler to do what I thought it would be able to do. I was wrong, and don't
// have time for that right now.

/// DEFINE-WORD-VA1 ( Word Symbol -> nothing )
pub fn DEFINE_WORD_VA1(_: *Stack) !void {
    // TODO
}

/// DEFINE-WORD-VA2 ( Word Word Symbol -> nothing )
pub fn DEFINE_WORD_VA2(_: *Stack) !void {
    // TODO
}

/// DEFINE-WORD-VA3 ( Word Word Word Symbol -> nothing )
pub fn DEFINE_WORD_VA3(_: *Stack) !void {
    // TODO
}

/// DEFINE-WORD-VA4 ( Word Word Word Word Symbol -> nothing )
pub fn DEFINE_WORD_VA4(_: *Stack) !void {
    // TODO
}

/// DEFINE-WORD-VA5 ( Word Word Word Word Word Symbol -> nothing )
pub fn DEFINE_WORD_VA5(_: *Stack) !void {
    // TODO
}

/// @DROP ( @1 -> nothing )
pub fn DROP(stack: *Stack) !void {
    _ = try stack.do_drop();
}

/// @DUP ( @1 -> @1 )
pub fn DUP(stack: *Stack) !*Stack {
    return try stack.do_dup();
}

/// @LIT ( @1 -> Word )
///
/// Wraps any value type in an anonymous word which will return that value when
/// called. Generally useful when defining words which need to refer to
/// numbers, strings, symbols, etc. at runtime.
pub fn LIT(_: *Stack) !void {
    // TODO
}

/// @PRIV_SPACE_SET_BYTE ( UInt8 UInt8 -> nothing )
///                        |     |
///                        |     +-> address to set
///                        +-------> value to set
pub fn PRIV_SPACE_SET_BYTE(_: *Stack) !void {
    // TODO
}

/// @SWAP ( @2 @1 -> @2 @1 )
pub fn SWAP(stack: *Stack) !void {
    return stack.do_swap();
}

test {
    std.testing.refAllDecls(@This());
}
