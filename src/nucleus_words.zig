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
const Runtime = @import("./runtime.zig").Runtime;
const StackManipulationError = _stack.StackManipulationError;
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

// TODO: move to test helpers file
fn push_one(runtime: *Runtime) anyerror!void {
    runtime.stack = try runtime.stack.do_push_uint(1);
}

fn push_two(runtime: *Runtime) anyerror!void {
    runtime.stack = try runtime.stack.do_push_uint(2);
}

/// @CONDJMP ( Word Boolean -> nothing )
///
/// Immediately executes the near word if the boolean is truthy, doing nothing
/// otherwise. Consumes both inputs, even if either is an invalid type: invalid
/// incantations will lose data. You've been warned.
///
/// See also: @CONDJMP2
pub fn CONDJMP(runtime: *Runtime) !void {
    const pairing = try runtime.stack.do_pop_pair();
    var condition = pairing.near;
    var callback = pairing.far;

    try condition.assert_is_kind(.Boolean);
    try callback.assert_is_kind(.Word);

    if (!condition.Boolean) {
        // See TODO below.
        condition.deinit(runtime.alloc);
        callback.deinit(runtime.alloc);
        return;
    }

    try runtime.run_boxed_word(callback.Word);

    // TODO: should these be handled in a receipt function of sorts on the
    // stack/runtime itself? pt1: pop trio off stack. pt2: turn in the receipt
    // gotten in pt1, runtime handles lifecycle teardowns along the way. This
    // would allow guarding against un-freed pop() returns, for example, which
    // have already bitten me so many times in unit tests.
    condition.deinit(runtime.alloc);
    callback.deinit(runtime.alloc);
}

test "CONDJMP" {
    var runtime = try Runtime.init(testAllocator);
    defer runtime.deinit_guard_for_empty_stack();

    // Destructors run when object popped off stack, so this memory should not
    // be defer-freed here (eg guarded_free_word_from_heap as one might be
    // tempted to use)
    const heap_for_word = try runtime.word_from_primitive_impl(&push_one);

    runtime.stack = try runtime.stack.do_push_word(heap_for_word);
    // We'll duplicate this early so that heap_for_word is not freed after
    // CONDJMP destroys the then-final reference to the memory, allowing us to
    // reuse that heap allocation for the falsey test below.
    runtime.stack = try runtime.stack.do_dup();
    runtime.stack = try runtime.stack.do_push_bool(true);
    try CONDJMP(&runtime);
    const should_be_1 = try runtime.stack.do_pop();
    try expectEqual(@as(usize, 1), should_be_1.UnsignedInt);

    runtime.stack = try runtime.stack.do_push_bool(false);
    try CONDJMP(&runtime);
}

/// @CONDJMP2 ( Word Word Boolean -> nothing )
///
/// Immediately executes the near word if the boolean is truthy, and the far
/// word otherwise. Consumes all three inputs.
///
/// See also: @CONDJMP
pub fn CONDJMP2(runtime: *Runtime) !void {
    const trio = try runtime.stack.do_pop_trio();
    var condition = trio.near;
    var truthy_callback = trio.far;
    var falsey_callback = trio.farther;

    try condition.assert_is_kind(.Boolean);
    try truthy_callback.assert_is_kind(.Word);
    try falsey_callback.assert_is_kind(.Word);

    const word = if (condition.Boolean) truthy_callback else falsey_callback;
    try runtime.run_boxed_word(word.Word);

    // TODO: should these be handled in a receipt function of sorts on the
    // stack/runtime itself? pt1: pop trio off stack. pt2: turn in the receipt
    // gotten in pt1, runtime handles lifecycle teardowns along the way. this
    // would also allow for clean increment/decrement handling along the way.
    condition.deinit(runtime.alloc);
    truthy_callback.deinit(runtime.alloc);
    falsey_callback.deinit(runtime.alloc);
}

test "CONDJMP2" {
    var runtime = try Runtime.init(testAllocator);
    defer runtime.deinit_guard_for_empty_stack();

    var heap_for_one_word = try runtime.word_from_primitive_impl(&push_one);
    var heap_for_two_word = try runtime.word_from_primitive_impl(&push_two);

    runtime.stack = try runtime.stack.do_push_word(heap_for_two_word);
    runtime.stack = try runtime.stack.do_push_word(heap_for_one_word);
    // We'll duplicate these early so that heap_for_*_word are not freed after
    // CONDJMP2 destroys the then-final references to the memory, allowing us
    // to reuse those heap allocations for the falsey test below.
    runtime.stack = try runtime.stack.do_2dupshuf();

    runtime.stack = try runtime.stack.do_push_bool(true);
    try CONDJMP2(&runtime);
    const should_be_1 = try runtime.stack.do_pop();
    try expectEqual(@as(usize, 1), should_be_1.UnsignedInt);

    runtime.stack = try runtime.stack.do_push(Object{ .Boolean = false });
    try CONDJMP2(&runtime);
    const should_be_2 = try runtime.stack.do_pop();
    try expectEqual(@as(usize, 2), should_be_2.UnsignedInt);
}

/// @EQ ( @2 @1 <- Boolean )
///
/// Non-destructive equality check of the top two items of the stack. At this
/// low a level, there is no type system, so checking equality of disparate
/// primitive types will panic.
pub fn EQ(runtime: *Runtime) !void {
    const peek = try runtime.stack.do_peek_pair();

    if (peek.bottom) |bottom| {
        runtime.stack = try runtime.stack.do_push_bool(try peek.top.eq(bottom));
        return;
    }

    return StackManipulationError.Underflow;
}

test "EQ" {
    var runtime = try Runtime.init(testAllocator);
    defer runtime.deinit();
    runtime.stack = try runtime.stack.do_push_uint(1);
    // Can't compare with just one Object on the Stack.
    try expectError(StackManipulationError.Underflow, EQ(&runtime));
    runtime.stack = try runtime.stack.do_push_uint(1);
    // 1 == 1, revelatory, truly.
    try EQ(&runtime);
    try expect((try runtime.stack.do_peek_pair()).top.*.Boolean);
    // Now compare that boolean to the UnsignedInt... or don't, preferably.
    try expectError(InternalError.TypeError, EQ(&runtime));
}

/// DEFINE-WORD-VA1 ( Word Symbol -> nothing )
// TODO: See if there's a better way to lay out "alias words" such as this in
// memory: can the lookups be more efficient in some way? Can we apply the
// learnings from this to Shapes later (thinking of a newtype-esque
// functionality especially...)
pub fn DEFINE_WORD_VA1(runtime: *Runtime) !void {
    const pairing = try runtime.stack.do_pop_pair();
    var symbol = pairing.near;
    var target = pairing.far;
    try symbol.assert_is_kind(.Symbol);
    try target.assert_is_kind(.Word);
    try runtime.define_word_va1(symbol.Symbol, target.Word);
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

test "DEFINE_WORD_VA*" {
    var runtime = try Runtime.init(testAllocator);
    // This one's definitely a bit overloaded: we're somewhat also testing
    // Runtime.deinit() here, as we depend on it cleaning up all this
    // straggling RAM along the way. This is a rather useful test despite the
    // mixture of concerns, since this is an actual real-world usecase more
    // philosophically "pure" unit testing might not (easily) catch.
    defer runtime.deinit();

    const heap_for_word = try runtime.word_from_primitive_impl(&push_one);
    const heaped_symbol = (try runtime.get_or_put_symbol("push-one")).value_ptr;

    runtime.stack = try runtime.stack.do_push_word(heap_for_word);
    runtime.stack = try runtime.stack.do_push_symbol(heaped_symbol);
    try DEFINE_WORD_VA1(&runtime);

    var found_word_list = runtime.dictionary.get(heaped_symbol).?;
    try expectEqual(found_word_list.len(), 1);
    const word_as_defined = found_word_list.items()[0];
    try expect(!word_as_defined.value.?.flags.hidden);
    try expectEqual(@as(usize, 1), word_as_defined.value.?.impl.Compound.len);
    try expectEqual(&push_one, word_as_defined.value.?.impl.Compound[0].value.?.impl.Primitive);
}

/// @DROP ( @1 -> nothing )
pub fn DROP(runtime: *Runtime) !void {
    runtime.stack = try runtime.stack.do_drop();
}

/// @DUP ( @1 -> @1 )
pub fn DUP(runtime: *Runtime) !void {
    runtime.stack = try runtime.stack.do_dup();
}

/// @2DUPSHUF ( @2 @1 -> @2 @1 @2 @1 )
pub fn TWODUPSHUF(runtime: *Runtime) !void {
    runtime.stack = try runtime.stack.do_2dupshuf();
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
    const obj = Object{ .Word = try runtime.word_from_heaplit_impl(banished) };
    runtime.stack = try runtime.stack.do_push(obj);
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

    try address.assert_is_kind(.UnsignedInt);
    try value.assert_is_kind(.UnsignedInt);

    try runtime.priv_space_set_byte(
        @truncate(u8, address.UnsignedInt),
        @truncate(u8, value.UnsignedInt),
    );
}

test "PRIV_SPACE_SET_BYTE" {
    var rt = try Runtime.init(testAllocator);
    defer rt.deinit_guard_for_empty_stack();

    try expectEqual(
        Runtime.InterpreterMode.Exec,
        rt.private_space.interpreter_mode,
    );

    rt.stack = try rt.stack.do_push_uint(1); // value
    rt.stack = try rt.stack.do_push_uint(0); // address
    try PRIV_SPACE_SET_BYTE(&rt);
    try expectEqual(
        Runtime.InterpreterMode.Symbol,
        rt.private_space.interpreter_mode,
    );

    // Quite intentionally right now, Runtime.priv_space_set_byte just panics
    // if the passed int is out of bounds, so there's no error cases to check
    // here that are actually catchable.
}

/// @SWAP ( @2 @1 -> @2 @1 )
pub fn SWAP(runtime: *Runtime) !void {
    return runtime.stack.do_swap();
}

test {
    std.testing.refAllDecls(@This());
}
