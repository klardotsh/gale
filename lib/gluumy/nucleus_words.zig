// gluumy's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

const std = @import("std");
const Allocator = std.mem.Allocator;
const testAllocator: Allocator = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

const _stack = @import("./stack.zig");
const test_helpers = @import("./test_helpers.zig");

const InternalError = @import("./internal_error.zig").InternalError;
const Object = @import("./object.zig").Object;
const Runtime = @import("./runtime.zig").Runtime;
const StackManipulationError = _stack.StackManipulationError;

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

/// @CONDJMP ( Word Boolean -> nothing )
///
/// Immediately executes the near word if the boolean is truthy, doing nothing
/// otherwise. Consumes both inputs, even if either is an invalid type: invalid
/// incantations will lose data. You've been warned.
///
/// See also: @CONDJMP2
pub fn CONDJMP(runtime: *Runtime) !void {
    const pairing = try runtime.stack_pop_pair();
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
    const heap_for_word = try runtime.word_from_primitive_impl(&test_helpers.push_one);

    try runtime.stack_push_raw_word(heap_for_word);
    // We'll duplicate this early so that heap_for_word is not freed after
    // CONDJMP destroys the then-final reference to the memory, allowing us to
    // reuse that heap allocation for the falsey test below.
    try runtime.stack_wrangle(.DuplicateTopObject);
    try runtime.stack_push_bool(true);
    try CONDJMP(&runtime);
    const should_be_1 = try runtime.stack_pop();
    try expectEqual(@as(usize, 1), should_be_1.UnsignedInt);

    try runtime.stack_push_bool(false);
    try CONDJMP(&runtime);
}

/// @CONDJMP2 ( Word Word Boolean -> nothing )
///
/// Immediately executes the near word if the boolean is truthy, and the far
/// word otherwise. Consumes all three inputs.
///
/// See also: @CONDJMP
pub fn CONDJMP2(runtime: *Runtime) !void {
    const trio = try runtime.stack_pop_trio();
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

    var heap_for_one_word = try runtime.word_from_primitive_impl(&test_helpers.push_one);
    var heap_for_two_word = try runtime.word_from_primitive_impl(&test_helpers.push_two);

    try runtime.stack_push_raw_word(heap_for_two_word);
    try runtime.stack_push_raw_word(heap_for_one_word);
    // We'll duplicate these early so that heap_for_*_word are not freed after
    // CONDJMP2 destroys the then-final references to the memory, allowing us
    // to reuse those heap allocations for the falsey test below.
    try runtime.stack_wrangle(.DuplicateTopTwoObjectsShuffled);

    try runtime.stack_push_bool(true);
    try CONDJMP2(&runtime);
    const should_be_1 = try runtime.stack_pop();
    try expectEqual(@as(usize, 1), should_be_1.UnsignedInt);

    try runtime.stack_push_bool(false);
    try CONDJMP2(&runtime);
    const should_be_2 = try runtime.stack_pop();
    try expectEqual(@as(usize, 2), should_be_2.UnsignedInt);
}

/// @EQ ( @2 @1 <- Boolean )
///
/// Non-destructive equality check of the top two items of the stack. At this
/// low a level, there is no type system, so checking equality of disparate
/// primitive types will panic.
pub fn EQ(runtime: *Runtime) !void {
    const peek = try runtime.stack_peek_pair();

    if (peek.far) |bottom| {
        try runtime.stack_push_bool(try peek.near.eq(bottom));
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

/// DEFINE-WORD-VA1 ( Word Symbol -> nothing )
// TODO: See if there's a better way to lay out "alias words" such as this in
// memory: can the lookups be more efficient in some way? Can we apply the
// learnings from this to Shapes later (thinking of a newtype-esque
// functionality especially...)
pub fn DEFINE_WORD_VA1(runtime: *Runtime) !void {
    const pairing = try runtime.stack_pop_pair();
    var symbol = pairing.near;
    var target = pairing.far;
    try symbol.assert_is_kind(.Symbol);
    try target.assert_is_kind(.Word);
    try runtime.define_word_va(symbol.Symbol, .{target.Word});
}

/// DEFINE-WORD-VA2 ( Word Word Symbol -> nothing )
pub fn DEFINE_WORD_VA2(runtime: *Runtime) !void {
    const pairing = try runtime.stack_pop_trio();
    var symbol = pairing.near;
    var exec_first = pairing.far;
    var exec_second = pairing.farther;

    try symbol.assert_is_kind(.Symbol);
    try exec_first.assert_is_kind(.Word);
    try exec_second.assert_is_kind(.Word);
    try runtime.define_word_va(symbol.Symbol, .{ exec_first.Word, exec_second.Word });
}

/// DEFINE-WORD-VA3 ( Word Word Word Symbol -> nothing )
pub fn DEFINE_WORD_VA3(runtime: *Runtime) !void {
    const pairing1 = try runtime.stack_pop_pair();
    const pairing2 = try runtime.stack_pop_pair();
    var symbol = pairing1.near;
    var exec_first = pairing1.far;
    var exec_second = pairing2.near;
    var exec_third = pairing2.far;

    try symbol.assert_is_kind(.Symbol);
    var candidates = .{ exec_first, exec_second, exec_third };
    inline for (candidates) |*it| try it.assert_is_kind(.Word);
    try runtime.define_word_va(
        symbol.Symbol,
        .{ exec_first.Word, exec_second.Word, exec_third.Word },
    );
}

/// DEFINE-WORD-VA4 ( Word Word Word Word Symbol -> nothing )
pub fn DEFINE_WORD_VA4(runtime: *Runtime) !void {
    const pairing1 = try runtime.stack_pop_trio();
    const pairing2 = try runtime.stack_pop_pair();
    var symbol = pairing1.near;
    var exec_first = pairing1.far;
    var exec_second = pairing1.farther;
    var exec_third = pairing2.near;
    var exec_fourth = pairing2.far;

    try symbol.assert_is_kind(.Symbol);
    var candidates = .{ exec_first, exec_second, exec_third, exec_fourth };
    inline for (candidates) |*it| try it.assert_is_kind(.Word);
    try runtime.define_word_va(
        symbol.Symbol,
        .{ exec_first.Word, exec_second.Word, exec_third.Word, exec_fourth.Word },
    );
}

/// DEFINE-WORD-VA5 ( Word Word Word Word Word Symbol -> nothing )
pub fn DEFINE_WORD_VA5(runtime: *Runtime) !void {
    const pairing1 = try runtime.stack_pop_trio();
    const pairing2 = try runtime.stack_pop_trio();
    var symbol = pairing1.near;
    var exec_first = pairing1.far;
    var exec_second = pairing1.farther;
    var exec_third = pairing2.near;
    var exec_fourth = pairing2.far;
    var exec_fifth = pairing2.farther;

    try symbol.assert_is_kind(.Symbol);
    var candidates = .{ exec_first, exec_second, exec_third, exec_fourth, exec_fifth };
    inline for (candidates) |*it| try it.assert_is_kind(.Word);
    try runtime.define_word_va(
        symbol.Symbol,
        .{
            exec_first.Word,
            exec_second.Word,
            exec_third.Word,
            exec_fourth.Word,
            exec_fifth.Word,
        },
    );
}

test "DEFINE_WORD_VA*" {
    var runtime = try Runtime.init(testAllocator);
    // This one's definitely a bit overloaded: we're somewhat also testing
    // Runtime.deinit() here, as we depend on it cleaning up all this
    // straggling RAM along the way. This is a rather useful test despite the
    // mixture of concerns, since this is an actual real-world usecase more
    // philosophically "pure" unit testing might not (easily) catch.
    defer runtime.deinit();

    const heap_for_word = try runtime.word_from_primitive_impl(&test_helpers.push_one);
    try expectEqual(@as(usize, 0), heap_for_word.strong_count.value);

    var heaped_symbol = (try runtime.get_or_put_symbol("va1")).value_ptr;
    try runtime.stack_push_raw_word(heap_for_word);
    try runtime.stack_push_symbol(heaped_symbol);
    try DEFINE_WORD_VA1(&runtime);
    var found_word_list = runtime.dictionary.get(heaped_symbol).?;
    try expectEqual(@as(usize, 1), found_word_list.len());
    var word_as_defined = found_word_list.items()[0];
    try expect(!word_as_defined.value.?.flags.hidden);
    try expectEqual(@as(usize, 1), word_as_defined.value.?.impl.Compound.len);
    try expectEqual(&test_helpers.push_one, word_as_defined.value.?.impl.Compound[0].value.?.impl.Primitive);

    heaped_symbol = (try runtime.get_or_put_symbol("va2")).value_ptr;
    try runtime.stack_push_raw_word(heap_for_word);
    try runtime.stack_push_raw_word(heap_for_word);
    try runtime.stack_push_symbol(heaped_symbol);
    try DEFINE_WORD_VA2(&runtime);
    found_word_list = runtime.dictionary.get(heaped_symbol).?;
    try expectEqual(@as(usize, 1), found_word_list.len());
    word_as_defined = found_word_list.items()[0];
    try expectEqual(@as(usize, 2), word_as_defined.value.?.impl.Compound.len);
    try expectEqual(@as(u16, 3), word_as_defined.value.?.impl.Compound[1].strong_count.value);
    try expectEqual(&test_helpers.push_one, word_as_defined.value.?.impl.Compound[1].value.?.impl.Primitive);

    heaped_symbol = (try runtime.get_or_put_symbol("va3")).value_ptr;
    try runtime.stack_push_raw_word(heap_for_word);
    try runtime.stack_push_raw_word(heap_for_word);
    try runtime.stack_push_raw_word(heap_for_word);
    try runtime.stack_push_symbol(heaped_symbol);
    try DEFINE_WORD_VA3(&runtime);
    found_word_list = runtime.dictionary.get(heaped_symbol).?;
    try expectEqual(@as(usize, 1), found_word_list.len());
    word_as_defined = found_word_list.items()[0];
    try expectEqual(@as(usize, 3), word_as_defined.value.?.impl.Compound.len);
    try expectEqual(@as(u16, 6), word_as_defined.value.?.impl.Compound[2].strong_count.value);
    try expectEqual(&test_helpers.push_one, word_as_defined.value.?.impl.Compound[2].value.?.impl.Primitive);

    heaped_symbol = (try runtime.get_or_put_symbol("va4")).value_ptr;
    try runtime.stack_push_raw_word(heap_for_word);
    try runtime.stack_push_raw_word(heap_for_word);
    try runtime.stack_push_raw_word(heap_for_word);
    try runtime.stack_push_raw_word(heap_for_word);
    try runtime.stack_push_symbol(heaped_symbol);
    try DEFINE_WORD_VA4(&runtime);
    found_word_list = runtime.dictionary.get(heaped_symbol).?;
    try expectEqual(@as(usize, 1), found_word_list.len());
    word_as_defined = found_word_list.items()[0];
    try expectEqual(@as(usize, 4), word_as_defined.value.?.impl.Compound.len);
    try expectEqual(@as(u16, 10), word_as_defined.value.?.impl.Compound[3].strong_count.value);
    try expectEqual(&test_helpers.push_one, word_as_defined.value.?.impl.Compound[3].value.?.impl.Primitive);

    heaped_symbol = (try runtime.get_or_put_symbol("va5")).value_ptr;
    try runtime.stack_push_raw_word(heap_for_word);
    try runtime.stack_push_raw_word(heap_for_word);
    try runtime.stack_push_raw_word(heap_for_word);
    try runtime.stack_push_raw_word(heap_for_word);
    try runtime.stack_push_raw_word(heap_for_word);
    try runtime.stack_push_symbol(heaped_symbol);
    try DEFINE_WORD_VA5(&runtime);
    found_word_list = runtime.dictionary.get(heaped_symbol).?;
    try expectEqual(@as(usize, 1), found_word_list.len());
    word_as_defined = found_word_list.items()[0];
    try expectEqual(@as(usize, 5), word_as_defined.value.?.impl.Compound.len);
    try expectEqual(@as(u16, 15), word_as_defined.value.?.impl.Compound[4].strong_count.value);
    try expectEqual(&test_helpers.push_one, word_as_defined.value.?.impl.Compound[4].value.?.impl.Primitive);
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
    const banished = try runtime.stack_pop_to_heap();
    const word = try runtime.word_from_heaplit_impl(banished);
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
    try runtime.run_boxed_word(lit_word.Word);
    try runtime.run_boxed_word(lit_word.Word);
    try runtime.run_boxed_word(lit_word.Word);

    // ...and assert that the UnsignedInt was placed back onto the stack all
    // three times.
    const top_three = try runtime.stack_pop_trio();
    try expectEqual(@as(usize, 1), top_three.near.UnsignedInt);
    try expectEqual(@as(usize, 1), top_three.far.UnsignedInt);
    try expectEqual(@as(usize, 1), top_three.farther.UnsignedInt);
}

/// @PRIV_SPACE_SET_BYTE ( UInt8 UInt8 -> nothing )
///                        |     |
///                        |     +-> address to set
///                        +-------> value to set
pub fn PRIV_SPACE_SET_BYTE(runtime: *Runtime) !void {
    const pairing = try runtime.stack_pop_pair();
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

    try rt.stack_push_uint(1); // value
    try rt.stack_push_uint(0); // address
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
    try runtime.stack_wrangle(.SwapTopTwoObjects);
}

test {
    std.testing.refAllDecls(@This());
}
