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

const _stack = @import("./stack.zig");
const _word = @import("./word.zig");

const InternalError = @import("./internal_error.zig").InternalError;
const Object = @import("./object.zig").Object;
const Rc = @import("./rc.zig").Rc;
const Stack = _stack.Stack;
const StackManipulationError = _stack.StackManipulationError;
const Word = _word.Word;
const WordImplementation = _word.WordImplementation;

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

fn push_one(stack: *Stack) anyerror!void {
    _ = try stack.do_push(Object{ .UnsignedInt = 1 });
}

fn push_two(stack: *Stack) anyerror!void {
    _ = try stack.do_push(Object{ .UnsignedInt = 2 });
}

// @CONDJMP ( Word Boolean -> nothing )
//
// Immediately executes the near word if the boolean is truthy, doing nothing
// otherwise. Consumes both inputs, even if either is an invalid type: invalid
// incantations will lose data. You've been warned.
//
// See also: @CONDJMP2
pub fn CONDJMP(stack: *Stack) !void {
    const pairing = try stack.do_pop_pair();
    const condition = pairing.near;
    const callback = pairing.far;

    if (@as(Object, condition) != Object.Boolean) {
        return InternalError.TypeError;
    }

    if (@as(Object, callback) != Object.Word) {
        return InternalError.TypeError;
    }

    if (!condition.Boolean) {
        return;
    }

    // TODO: safely handle null
    return switch (callback.Word.value.?.impl) {
        // TODO
        WordImplementation.Compound => error.Unimplemented,
        // TODO: should this be handled here, in Runtime, or in a helper util?
        WordImplementation.HeapLit => error.Unimplemented,
        // TODO: handle stack juggling
        WordImplementation.Primitive => |impl| try impl(stack),
    };
}

test "CONDJMP" {
    var stack = try Stack.init(testAllocator, null);
    defer stack.deinit();

    // TODO: make helper function on Word to create a sane default
    const push_one_word = Word{
        .flags = .{
            .hidden = false,
        },
        .tags = [_]u8{0} ** Word.TAG_ARRAY_SIZE,
        .impl = .{
            .Primitive = &push_one,
        },
    };

    // TODO: move to common location
    const HeapedWord = Rc(Word);

    // TODO: stop reaching into the stack here to borrow its allocator
    const heap_for_word = try stack.alloc.create(HeapedWord);
    defer stack.alloc.destroy(heap_for_word);
    heap_for_word.* = HeapedWord.init(push_one_word);

    _ = try stack.do_push(Object{ .Word = heap_for_word });
    _ = try stack.do_push(Object{ .Boolean = true });
    try CONDJMP(stack);
    const should_be_1 = try stack.do_pop();
    try expectEqual(@as(usize, 1), should_be_1.UnsignedInt);

    _ = try stack.do_push(Object{ .Word = heap_for_word });
    _ = try stack.do_push(Object{ .Boolean = false });
    try CONDJMP(stack);
    try expectError(StackManipulationError.Underflow, stack.do_pop());
}

// @CONDJMP2 ( Word Word Boolean -> nothing )
//
// Immediately executes the near word if the boolean is truthy, and the far
// word otherwise. Consumes all three inputs.
//
// See also: @CONDJMP
pub fn CONDJMP2(stack: *Stack) !void {
    const trio = try stack.do_pop_trio();
    const condition = trio.near;
    const truthy_callback = trio.far;
    const falsey_callback = trio.farther;

    if (@as(Object, condition) != Object.Boolean) {
        return InternalError.TypeError;
    }

    if (@as(Object, truthy_callback) != Object.Word) {
        return InternalError.TypeError;
    }

    if (@as(Object, falsey_callback) != Object.Word) {
        return InternalError.TypeError;
    }

    const callback = if (condition.Boolean) truthy_callback else falsey_callback;

    // TODO: safely handle null
    return switch (callback.Word.value.?.impl) {
        // TODO
        WordImplementation.Compound => error.Unimplemented,
        // TODO: should this be handled here, in Runtime, or in a helper util?
        WordImplementation.HeapLit => error.Unimplemented,
        // TODO: handle stack juggling
        WordImplementation.Primitive => |impl| try impl(stack),
    };
}

test "CONDJMP2" {
    var stack = try Stack.init(testAllocator, null);
    defer stack.deinit();

    // TODO: make helper function on Word to create a sane default
    const push_one_word = Word{
        .flags = .{
            .hidden = false,
        },
        .tags = [_]u8{0} ** Word.TAG_ARRAY_SIZE,
        .impl = .{
            .Primitive = &push_one,
        },
    };

    // TODO: make helper function on Word to create a sane default
    const push_two_word = Word{
        .flags = .{
            .hidden = false,
        },
        .tags = [_]u8{0} ** Word.TAG_ARRAY_SIZE,
        .impl = .{
            .Primitive = &push_two,
        },
    };

    // TODO: move to common location
    const HeapedWord = Rc(Word);

    // TODO: stop reaching into the stack here to borrow its allocator
    const heap_for_one_word = try stack.alloc.create(HeapedWord);
    const heap_for_two_word = try stack.alloc.create(HeapedWord);
    defer stack.alloc.destroy(heap_for_one_word);
    defer stack.alloc.destroy(heap_for_two_word);
    heap_for_one_word.* = HeapedWord.init(push_one_word);
    heap_for_two_word.* = HeapedWord.init(push_two_word);

    _ = try stack.do_push(Object{ .Word = heap_for_two_word });
    _ = try stack.do_push(Object{ .Word = heap_for_one_word });
    _ = try stack.do_push(Object{ .Boolean = true });
    try CONDJMP2(stack);
    const should_be_1 = try stack.do_pop();
    try expectEqual(@as(usize, 1), should_be_1.UnsignedInt);

    _ = try stack.do_push(Object{ .Word = heap_for_two_word });
    _ = try stack.do_push(Object{ .Word = heap_for_one_word });
    _ = try stack.do_push(Object{ .Boolean = false });
    try CONDJMP2(stack);
    const should_be_2 = try stack.do_pop();
    try expectEqual(@as(usize, 2), should_be_2.UnsignedInt);
    try expectError(StackManipulationError.Underflow, stack.do_pop());
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
///
/// Used to be called @HEAPWRAP, which might hint at why it's implemented the
/// way it is.
pub fn LIT(stack: *Stack) !void {
    const banished = try stack.banish_top_object();

    // TODO: make helper function on Word to create a sane default
    const heaplit_word = Word{
        .flags = .{
            .hidden = false,
        },
        .tags = [_]u8{0} ** Word.TAG_ARRAY_SIZE,
        .impl = .{
            .HeapLit = banished,
        },
    };

    // TODO: move to common location
    const HeapedWord = Rc(Word);

    // TODO: stop reaching into the stack here to borrow its allocator
    const heap_for_word = try stack.alloc.create(HeapedWord);
    errdefer stack.alloc.destroy(heap_for_word);
    heap_for_word.* = HeapedWord.init(heaplit_word);
    _ = try stack.do_push(Object{ .Word = heap_for_word });

    return;
}

// The name here might be silly, but it tries to emphasize that this test is
// scoped only to being able to yeet something from the working stack onto the
// heap (exactly where should be considered irrelevant to the end user) without
// leaving anything behind, but that we're not actually testing the ability to
// place that value back onto the working stack. Since the signature of
// PrimitiveWord doesn't really give us enough to work with (storing a pointer
// to the heap object is required), recall happens through a third branch of
// the WordImplementation enum, "HeapLit", and as such the recall process
// should be tested at the Word or perhaps Runtime level (it's a "glue" or
// "integration" type of test, moreso than the "units" here).
test "LIT: banishment, but not recall" {
    var stack = try Stack.init(testAllocator, null);
    defer stack.deinit();
    _ = try stack.do_push(Object{ .UnsignedInt = 1 });

    try LIT(stack);
    const top_two = try stack.do_peek_pair();
    // TODO: document this free sequence, or otherwise guard around it in
    // userspace, it's *nasty* right now, presumably because I'm working around
    // not really having Runtime here (which may be a smell that these tests
    // belong at a different altitude)
    defer {
        // TODO: this should use whatever the new allocator is after fixing
        // heap_for_word in LIT implementation above
        stack.alloc.destroy(top_two.top.Word.value.?.impl.HeapLit);
        _ = top_two.top.Word.decrement();
        stack.alloc.destroy(top_two.top.Word);
    }

    // First, ascertain that we still have just one thing on the stack.
    try expectEqual(@as(?*Object, null), top_two.bottom);

    // Now, let's validate that that thing is an Rc(Word->impl->HeapLit).
    try expect(@as(WordImplementation, top_two.top.Word.value.?.impl) == WordImplementation.HeapLit);

    // And finally, validate the actual value that would be restored to the
    // stack if this word were called is correct.
    //
    // TODO: should this test be reaching into such deeply nested foreign
    // concerns?
    try expectEqual(@as(usize, 1), top_two.top.Word.value.?.impl.HeapLit.UnsignedInt);
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
