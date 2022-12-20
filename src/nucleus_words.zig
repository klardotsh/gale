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

const Object = @import("./object.zig").Object;
const Rc = @import("./rc.zig").Rc;
const Runtime = @import("./runtime.zig").Runtime;
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
pub fn BEFORE_WORD(_: *Runtime) !void {
    // TODO
}

fn push_one(runtime: *Runtime) anyerror!void {
    runtime.stack = try runtime.stack.do_push(Object{ .UnsignedInt = 1 });
}

fn push_two(runtime: *Runtime) anyerror!void {
    runtime.stack = try runtime.stack.do_push(Object{ .UnsignedInt = 2 });
}

// @CONDJMP ( Word Boolean -> nothing )
//
// Immediately executes the near word if the boolean is truthy, doing nothing
// otherwise. Consumes both inputs, even if either is an invalid type: invalid
// incantations will lose data. You've been warned.
//
// See also: @CONDJMP2
pub fn CONDJMP(runtime: *Runtime) !void {
    const pairing = try runtime.stack.do_pop_pair();
    var condition = pairing.near;
    var callback = pairing.far;

    try condition.assert_is_kind(Object.Boolean);
    try callback.assert_is_kind(Object.Word);

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
        WordImplementation.Primitive => |impl| try impl(runtime),
    };
}

test "CONDJMP" {
    var runtime = try Runtime.init(testAllocator);
    defer runtime.deinit();

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

    const heap_for_word = try runtime.alloc.create(HeapedWord);
    defer runtime.alloc.destroy(heap_for_word);
    heap_for_word.* = HeapedWord.init(push_one_word);

    runtime.stack = try runtime.stack.do_push(Object{ .Word = heap_for_word });
    runtime.stack = try runtime.stack.do_push(Object{ .Boolean = true });
    try CONDJMP(&runtime);
    const should_be_1 = try runtime.stack.do_pop();
    try expectEqual(@as(usize, 1), should_be_1.UnsignedInt);

    runtime.stack = try runtime.stack.do_push(Object{ .Word = heap_for_word });
    runtime.stack = try runtime.stack.do_push(Object{ .Boolean = false });
    try CONDJMP(&runtime);
    try expectError(StackManipulationError.Underflow, runtime.stack.do_pop());
}

// @CONDJMP2 ( Word Word Boolean -> nothing )
//
// Immediately executes the near word if the boolean is truthy, and the far
// word otherwise. Consumes all three inputs.
//
// See also: @CONDJMP
pub fn CONDJMP2(runtime: *Runtime) !void {
    const trio = try runtime.stack.do_pop_trio();
    var condition = trio.near;
    var truthy_callback = trio.far;
    var falsey_callback = trio.farther;

    try condition.assert_is_kind(Object.Boolean);
    try truthy_callback.assert_is_kind(Object.Word);
    try falsey_callback.assert_is_kind(Object.Word);

    const callback = if (condition.Boolean) truthy_callback else falsey_callback;

    // TODO: safely handle null
    return switch (callback.Word.value.?.impl) {
        // TODO
        WordImplementation.Compound => error.Unimplemented,
        // TODO: should this be handled here, in Runtime, or in a helper util?
        WordImplementation.HeapLit => error.Unimplemented,
        // TODO: handle stack juggling
        WordImplementation.Primitive => |impl| try impl(runtime),
    };
}

test "CONDJMP2" {
    var runtime = try Runtime.init(testAllocator);
    defer runtime.deinit();

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
    const heap_for_one_word = try runtime.alloc.create(HeapedWord);
    const heap_for_two_word = try runtime.alloc.create(HeapedWord);
    defer runtime.alloc.destroy(heap_for_one_word);
    defer runtime.alloc.destroy(heap_for_two_word);
    heap_for_one_word.* = HeapedWord.init(push_one_word);
    heap_for_two_word.* = HeapedWord.init(push_two_word);

    runtime.stack = try runtime.stack.do_push(Object{ .Word = heap_for_two_word });
    runtime.stack = try runtime.stack.do_push(Object{ .Word = heap_for_one_word });
    runtime.stack = try runtime.stack.do_push(Object{ .Boolean = true });
    try CONDJMP2(&runtime);
    const should_be_1 = try runtime.stack.do_pop();
    try expectEqual(@as(usize, 1), should_be_1.UnsignedInt);

    runtime.stack = try runtime.stack.do_push(Object{ .Word = heap_for_two_word });
    runtime.stack = try runtime.stack.do_push(Object{ .Word = heap_for_one_word });
    runtime.stack = try runtime.stack.do_push(Object{ .Boolean = false });
    try CONDJMP2(&runtime);
    const should_be_2 = try runtime.stack.do_pop();
    try expectEqual(@as(usize, 2), should_be_2.UnsignedInt);
    try expectError(StackManipulationError.Underflow, runtime.stack.do_pop());
}

/// @EQ ( @2 @1 <- Boolean )
///
/// Non-destructive equality check of the top two items of the stack. At this
/// low a level, there is no type system, so checking equality of disparate
/// primitive types will panic.
pub fn EQ(runtime: *Runtime) !void {
    const peek = try runtime.stack.do_peek_pair();

    if (peek.bottom) |bottom| {
        runtime.stack = try runtime.stack.do_push(Object{ .Boolean = try peek.top.eq(bottom) });
        return;
    }

    return StackManipulationError.Underflow;
}

test "EQ" {
    var runtime = try Runtime.init(testAllocator);
    defer runtime.deinit();
    runtime.stack = try runtime.stack.do_push(Object{ .UnsignedInt = 1 });
    // Can't compare with just one Object on the Stack.
    try expectError(StackManipulationError.Underflow, EQ(&runtime));
    runtime.stack = try runtime.stack.do_push(Object{ .UnsignedInt = 1 });
    // 1 == 1, revelatory, truly.
    try EQ(&runtime);
    try expect((try runtime.stack.do_peek_pair()).top.*.Boolean);
    // Now compare that boolean to the UnsignedInt... or don't, preferably.
    try expectError(error.CannotCompareDisparateTypes, EQ(&runtime));
}

// TODO: comptime away these numerous implementations of DEFINE-WORD-VA*, I
// gave it a go upfront and wound up spending 30 minutes fighting the Zig
// compiler to do what I thought it would be able to do. I was wrong, and don't
// have time for that right now.

/// DEFINE-WORD-VA1 ( Word Symbol -> nothing )
///
/// This is a glorified alias/assignment utility.
pub fn DEFINE_WORD_VA1(runtime: *Runtime) !void {
    const pairing = try runtime.stack.do_pop_pair();
    _ = pairing.near;
    _ = pairing.far;
}

/// DEFINE-WORD-VA2 ( Word Word Symbol -> nothing )
pub fn DEFINE_WORD_VA2(_: *Runtime) !void {
    // TODO
}

/// DEFINE-WORD-VA3 ( Word Word Word Symbol -> nothing )
pub fn DEFINE_WORD_VA3(_: *Runtime) !void {
    // TODO
}

/// DEFINE-WORD-VA4 ( Word Word Word Word Symbol -> nothing )
pub fn DEFINE_WORD_VA4(_: *Runtime) !void {
    // TODO
}

/// DEFINE-WORD-VA5 ( Word Word Word Word Word Symbol -> nothing )
pub fn DEFINE_WORD_VA5(_: *Runtime) !void {
    // TODO
}

/// @DROP ( @1 -> nothing )
pub fn DROP(runtime: *Runtime) !void {
    runtime.stack = try runtime.stack.do_drop();
}

/// @DUP ( @1 -> @1 )
pub fn DUP(runtime: *Runtime) !void {
    runtime.stack = try runtime.stack.do_dup();
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
    const banished = try runtime.stack.banish_top_object();

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
    const heap_for_word = try runtime.stack.alloc.create(HeapedWord);
    errdefer runtime.stack.alloc.destroy(heap_for_word);
    heap_for_word.* = HeapedWord.init(heaplit_word);
    runtime.stack = try runtime.stack.do_push(Object{ .Word = heap_for_word });

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
    var runtime = try Runtime.init(testAllocator);
    defer runtime.deinit();
    runtime.stack = try runtime.stack.do_push(Object{ .UnsignedInt = 1 });

    try LIT(&runtime);
    const top_two = try runtime.stack.do_peek_pair();
    // TODO: document this free sequence, or otherwise guard around it in
    // userspace, it's *nasty* right now, presumably because I'm working around
    // not really having Runtime here (which may be a smell that these tests
    // belong at a different altitude)
    defer {
        // TODO: this should use whatever the new allocator is after fixing
        // heap_for_word in LIT implementation above
        runtime.stack.alloc.destroy(top_two.top.Word.value.?.impl.HeapLit);
        _ = top_two.top.Word.decrement();
        runtime.stack.alloc.destroy(top_two.top.Word);
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
pub fn PRIV_SPACE_SET_BYTE(runtime: *Runtime) !void {
    const pairing = try runtime.stack.do_pop_pair();
    var address = pairing.near;
    var value = pairing.far;

    try address.assert_is_kind(Object.UnsignedInt);
    try value.assert_is_kind(Object.UnsignedInt);

    try runtime.priv_space_set_byte(@truncate(u8, address.UnsignedInt), @truncate(u8, value.UnsignedInt));
}

test "PRIV_SPACE_SET_BYTE" {
    var rt = try Runtime.init(testAllocator);
    defer rt.deinit();
    try expectEqual(@as(u8, 0), @enumToInt(rt.private_space.interpreter_mode));
    rt.stack = try rt.stack.do_push(Object{ .UnsignedInt = 1 }); // value
    rt.stack = try rt.stack.do_push(Object{ .UnsignedInt = 0 }); // address
    try PRIV_SPACE_SET_BYTE(&rt);
    try expectEqual(@as(u8, 1), @enumToInt(rt.private_space.interpreter_mode));
}

/// @SWAP ( @2 @1 -> @2 @1 )
pub fn SWAP(runtime: *Runtime) !void {
    return runtime.stack.do_swap();
}

test {
    std.testing.refAllDecls(@This());
}
