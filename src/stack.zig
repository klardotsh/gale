// gluumy's canonical implementation and standard library is released to the
// public domain (or your jurisdiction's closest legal equivalent) under the
// Creative Commons Zero 1.0 dedication, distributed alongside this source in a
// file called COPYING.

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const testAllocator: Allocator = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

const InternalError = @import("./internal_error.zig").InternalError;
const Object = @import("./object.zig").Object;
const Rc = @import("./rc.zig").Rc;
const Types = @import("./types.zig");

pub const StackManipulationError = error{
    Underflow,
    Overflow,
    RefuseToGrowMultipleStacks,
    YouAlmostCertainlyDidNotMeanToUseThisNonTerminalStack,
};

/// A doubly-linked list of doubly-linked lists: we'll pretend to have infinite
/// stack space by simply making as many heap-based stacks as we have space
/// for, and seamlessly (as far as the end-user is concerned) glue them
/// together. This should serve to make common gluumy stack operations
/// reasonably performant with reasonable tradeoffs, as we're moving our way
/// around a block of mass-allocated memory, rather than constantly churning
/// garbage via alloc() and free() calls for each Object (imagining a
/// fully-pointer-based doubly linked list implementation of a "stack", for
/// example std.TailQueue). I suspect it should be uncommon to get anywhere
/// near the end of even a single stack, but if it does happen, we don't have
/// to take the perf hit of copying the old stack to a new stack of size N*2,
/// as one would generally do when resizing lists in most dynamic languages.
/// Whether this complexity pays itself off at any point is somewhat TBD...
///
/// Operations right at the edge of a stack's space bleeding into the next
/// stack are unlikely to be performant, particularly those that juggle that
/// boundary repeatedly (imagine swapping the top element of a "lower" stack
/// and the bottom element of a "higher" stack in a tight loop or some such). I
/// don't yet have benchmarking data to prove this hypothesis, however.
///
/// Not thread-safe. Use channels or something.
// TODO:
// - Docs
// - Sanitize entries when rolling back stack pointer?
// - Stop leaking literally everything: keep no more than N+1 stacks allocated
//   at a time, once self->next->next->next_idx == 0, it's time to start calling
//   free.
pub const Stack = struct {
    // Those finding they need more per-stack space should compile their own
    // project-specific gluumy build changing the constant as appropriate.
    // Unlike many languages where mucking about with the internals is
    // faux-pas, in gluumy it is encouraged on a "if you know you really need
    // it" basis.
    //
    // TODO: configurable in build.zig
    const STACK_SIZE: usize = 2048;

    comptime {
        assert(STACK_SIZE >= 1);

        // If STACK_SIZE for some godforsaken reason is MAX_INT of a usize,
        // we'll overflow .next_idx upon assigning the final item in this
        // stack. On a 16-bit microcontroller this is vaguely conceivable
        // (given that STACK_SIZE would only be ~8x bigger than default), on
        // any larger bitsizes this is a near-laughable concept in practical
        // usecases, but failure to handle this is an almost-guaranteed CVE
        // waiting to happen.
        var overflow_space: usize = undefined;
        assert(!@addWithOverflow(usize, STACK_SIZE, 1, &overflow_space));
    }

    const Self = @This();

    alloc: Allocator,
    prev: ?*Stack,
    next: ?*Stack,
    next_idx: usize,
    contents: [STACK_SIZE]?Object,

    pub fn init(alloc: Allocator, prev: ?*Stack) !*Self {
        var stack = try alloc.create(Self);
        stack.* = .{
            .alloc = alloc,
            .prev = prev,
            .next = null,
            .next_idx = 0,
            .contents = .{null} ** STACK_SIZE,
        };
        return stack;
    }

    pub fn deinit(self: *Self) void {
        // At what point will this completely blow out the stack? Is it worth
        // finding that point and somehow providing userspace guardrails around
        // it, or figuring out how to trampoline my way around a stack without
        // completely exploding? This is entirely uncharted waters for me and
        // "to trampoline" to me still involves a sunny summer day in a
        // suburban backyard of Ohio where I grew up, given I don't know the
        // compiler theory behind the idea well.
        //
        // ... but don't make me go back to Ohio, please.
        if (self.next) |next| {
            next.deinit();
        }
        if (self.prev) |prev| {
            prev.next = null;
        }

        while (self.next_idx > 0) {
            _ = self.do_drop() catch null;
        }
        self.alloc.destroy(self);
    }

    /// TODO: docs about stack jumping behavior here
    /// TODO: see if this should just be the mainline deinit() function instead
    /// or if they can otherwise be merged
    pub fn deinit_from_bottom(self: *Self) void {
        if (self.prev) |prev| {
            prev.deinit_from_bottom();
        } else {
            self.deinit();
        }
    }

    pub fn banish_top_object(self: *Self) !*Object {
        const banish_target = try self.alloc.create(Object);
        errdefer self.deinit_banished_object(banish_target);

        const top = (try self.do_peek_pair()).top;
        return switch (top.*) {
            .Word, .Opaque => InternalError.Unimplemented,
            else => |it| {
                banish_target.* = it;

                // TODO handle stack hopping: move to POP definition
                if (self.next_idx > 0) {
                    self.contents[self.next_idx - 1] = null;
                    self.next_idx -= 1;
                } else if (self.prev) |prev| {
                    prev.contents[prev.next_idx - 1] = null;
                    prev.next_idx -= 1;
                } else {
                    unreachable;
                }

                return banish_target;
            },
        };
    }

    pub fn deinit_banished_object(self: *Self, ptr: *Object) void {
        self.alloc.destroy(ptr);
    }

    test "banish_top_object" {
        const stack = try Self.init(testAllocator, null);
        defer stack.deinit();

        try expectError(StackManipulationError.Underflow, stack.banish_top_object());

        var target = try stack.do_push_uint(1);
        const one_ptr = try target.banish_top_object();
        defer target.deinit_banished_object(one_ptr);
        try expectEqual(@as(usize, 1), one_ptr.*.UnsignedInt);

        try expectError(StackManipulationError.Underflow, stack.banish_top_object());
    }

    /// Ensures there will be enough space in no more than two stacks to store
    /// `count` new objects. Returns pointer to newly created stack if it was
    /// necessary to store all items. If no growth was necessary, returns null.
    /// The ergonomics of this API make a bit more sense in context:
    ///
    /// ```
    /// const target = self.expand_to_fit(1) orelse self;
    ///
    /// // or...
    ///
    /// if (self.expand_to_fit(5)) |final_destination| {
    ///     // more complicated logic here to handle stack crossover
    /// } else {
    ///     // happy path here, all on one stack
    /// }
    /// ```
    fn expand_to_fit(self: *Self, count: usize) !?*Self {
        if (self.next_idx + count > STACK_SIZE * 2) {
            return StackManipulationError.RefuseToGrowMultipleStacks;
        }

        if (self.next_idx + count > STACK_SIZE) {
            return try self.onwards();
        }

        return null;
    }

    test "expand_to_fit" {
        const baseStack = try Self.init(testAllocator, null);
        defer baseStack.deinit();
        try expectError(StackManipulationError.RefuseToGrowMultipleStacks, baseStack.expand_to_fit(Stack.STACK_SIZE * 2 + 1));
        try expectEqual(@as(?*Self, null), try baseStack.expand_to_fit(STACK_SIZE / 2 + 1));
        try expect(try baseStack.expand_to_fit(STACK_SIZE * 2) != null);
        // Hella unsafe to just yolo a stack pointer forward into null data but
        // this is a test, whatever.
        baseStack.next_idx = 1;
        try expectError(StackManipulationError.RefuseToGrowMultipleStacks, baseStack.expand_to_fit(Stack.STACK_SIZE * 2));
    }

    /// Extend the Stack into a new stack, presumably because we've run out of
    /// room in the current one (if there is one). Return a pointer to the new
    /// stack, as that stack is what callers should now be working with.
    fn onwards(self: *Self) !*Self {
        var next = try Self.init(self.alloc, self);
        self.next = next;
        return next;
    }

    inline fn non_terminal_stack_guard(self: *Self) StackManipulationError!void {
        if (self.next != null) {
            return StackManipulationError.YouAlmostCertainlyDidNotMeanToUseThisNonTerminalStack;
        }
    }

    pub const PeekTrio = struct {
        near: *Object,
        far: ?*Object,
        farther: ?*Object,
    };

    pub fn do_peek_trio(self: *Self) !PeekTrio {
        try self.non_terminal_stack_guard();
        return try @call(
            .{ .modifier = .always_inline },
            self.do_peek_trio_no_really_even_on_inner_stacks,
            .{},
        );
    }

    pub fn do_peek_trio_no_really_even_on_inner_stacks(self: *Self) !PeekTrio {
        if (self.next_idx == 0) {
            if (self.prev) |prev| {
                return prev.do_peek_trio_no_really_even_on_inner_stacks();
            }

            return StackManipulationError.Underflow;
        }

        if (self.next_idx == 1) {
            return PeekTrio{
                .near = &self.contents[0].?,
                .far = if (self.prev) |prev|
                    &prev.contents[prev.next_idx - 1].?
                else
                    null,
                .farther = if (self.prev) |prev|
                    &prev.contents[prev.next_idx - 2].?
                else
                    null,
            };
        }

        if (self.next_idx == 2) {
            return PeekTrio{
                .near = &self.contents[1].?,
                .far = &self.contents[0].?,
                .farther = if (self.prev) |prev|
                    &prev.contents[prev.next_idx - 1].?
                else
                    null,
            };
        }

        return PeekTrio{
            .near = &self.contents[self.next_idx - 1].?,
            .far = &self.contents[self.next_idx - 2].?,
            .farther = &self.contents[self.next_idx - 3].?,
        };
    }

    test "do_peek_trio" {
        const stack = try Self.init(testAllocator, null);
        defer stack.deinit();

        try expectError(StackManipulationError.Underflow, stack.do_peek_trio());

        var target = try stack.do_push_uint(1);
        const near_one = try target.do_peek_trio();
        try expectEqual(@as(usize, 1), near_one.near.*.UnsignedInt);
        try expectEqual(@as(?*Object, null), near_one.far);
        try expectEqual(@as(?*Object, null), near_one.farther);

        target = try target.do_push_uint(2);
        const near_two = try target.do_peek_trio();
        try expectEqual(@as(usize, 2), near_two.near.*.UnsignedInt);
        try expectEqual(@as(usize, 1), near_two.far.?.*.UnsignedInt);
        try expectEqual(@as(?*Object, null), near_one.farther);

        target = try target.do_push_uint(3);
        const near_three = try target.do_peek_trio();
        try expectEqual(@as(usize, 3), near_three.near.*.UnsignedInt);
        try expectEqual(@as(usize, 2), near_three.far.?.*.UnsignedInt);
        try expectEqual(@as(usize, 1), near_three.farther.?.*.UnsignedInt);
    }

    pub const PeekPair = struct {
        top: *Object,
        bottom: ?*Object,
    };

    pub fn do_peek_pair(self: *Self) !PeekPair {
        try self.non_terminal_stack_guard();
        return try @call(
            .{ .modifier = .always_inline },
            self.do_peek_pair_no_really_even_on_inner_stacks,
            .{},
        );
    }

    pub fn do_peek_pair_no_really_even_on_inner_stacks(self: *Self) !PeekPair {
        if (self.next_idx == 0) {
            if (self.prev) |prev| {
                return prev.do_peek_pair_no_really_even_on_inner_stacks();
            }

            return StackManipulationError.Underflow;
        }

        if (self.next_idx == 1) {
            return PeekPair{
                .top = &self.contents[0].?,
                .bottom = if (self.prev) |prev|
                    &prev.contents[prev.next_idx - 1].?
                else
                    null,
            };
        }

        return PeekPair{
            .top = &self.contents[self.next_idx - 1].?,
            .bottom = &self.contents[self.next_idx - 2].?,
        };
    }

    test "do_peek_pair" {
        const stack = try Self.init(testAllocator, null);
        defer stack.deinit_guard_for_empty();

        try expectError(StackManipulationError.Underflow, stack.do_peek_pair());

        var target = try stack.do_push_uint(1);
        const top_one = try target.do_peek_pair();
        try expectEqual(@as(usize, 1), top_one.top.*.UnsignedInt);
        try expectEqual(@as(?*Object, null), top_one.bottom);

        target = try target.do_push_uint(2);
        const top_two = try target.do_peek_pair();
        try expectEqual(@as(usize, 2), top_two.top.*.UnsignedInt);
        try expectEqual(@as(usize, 1), top_two.bottom.?.*.UnsignedInt);
    }

    pub fn do_peek(self: *Self) !*Object {
        return (try self.do_peek_pair()).top;
    }

    pub fn do_pop(self: *Self) !Object {
        if (self.next_idx == 0) {
            return StackManipulationError.Underflow;
        }

        self.next_idx -= 1;
        if (self.contents[self.next_idx]) |obj| {
            self.contents[self.next_idx] = null;
            return obj;
        }

        unreachable;
    }

    test "do_pop" {
        const stack = try Self.init(testAllocator, null);
        defer stack.deinit();
        var target = try stack.do_push_uint(41);
        target = try stack.do_push_uint(42);
        try expectEqual(@as(usize, 42), (try target.do_pop()).UnsignedInt);
        try expectEqual(@as(usize, 41), (try target.do_pop()).UnsignedInt);
        try expectError(StackManipulationError.Underflow, target.do_pop());
    }

    pub const PopPair = struct {
        near: Object,
        far: Object,
    };

    pub fn do_pop_pair(self: *Self) !PopPair {
        const top_two = try self.do_peek_pair();

        if (top_two.bottom) |_| {
            return PopPair{
                .near = try self.do_pop(),
                .far = try self.do_pop(),
            };
        }

        return StackManipulationError.Underflow;
    }

    test "do_pop_pair" {
        const stack = try Self.init(testAllocator, null);
        defer stack.deinit();

        var target = try stack.do_push_uint(41);
        target = try stack.do_push_uint(42);
        const pairing = try target.do_pop_pair();
        try expectEqual(@as(usize, 42), pairing.near.UnsignedInt);
        try expectEqual(@as(usize, 41), pairing.far.UnsignedInt);
        try expectError(StackManipulationError.Underflow, stack.do_pop_pair());
    }

    pub const PopTrio = struct {
        near: Object,
        far: Object,
        farther: Object,
    };

    pub fn do_pop_trio(self: *Self) !PopTrio {
        const top_three = try self.do_peek_trio();

        if (top_three.farther) |_| {
            return PopTrio{
                .near = try self.do_pop(),
                .far = try self.do_pop(),
                .farther = try self.do_pop(),
            };
        }

        return StackManipulationError.Underflow;
    }

    test "do_pop_trio" {
        const stack = try Self.init(testAllocator, null);
        defer stack.deinit();

        var target = try stack.do_push_uint(40);
        target = try stack.do_push_uint(41);
        target = try stack.do_push_uint(42);

        const trio = try target.do_pop_trio();
        try expectEqual(@as(usize, 42), trio.near.UnsignedInt);
        try expectEqual(@as(usize, 41), trio.far.UnsignedInt);
        try expectEqual(@as(usize, 40), trio.farther.UnsignedInt);
        try expectError(StackManipulationError.Underflow, stack.do_pop_trio());
    }

    /// Pushes an object to the top of this stack or a newly-created stack, as
    /// necessary based on available space. Returns pointer to whichever stack
    /// the object ended up on.
    pub fn do_push(self: *Self, obj: Object) !*Self {
        try self.non_terminal_stack_guard();
        const target = try self.expand_to_fit(1) orelse self;
        target.contents[target.next_idx] = obj;
        target.next_idx += 1;
        return target;
    }

    pub fn do_push_symbol(self: *Self, symbol: Types.GluumySymbol) !*Self {
        return try self.do_push(Object{ .Symbol = symbol });
    }

    /// Push a Zig unsigned integer value onto this Stack as an Object.
    pub inline fn do_push_uint(self: *Self, number: usize) !*Self {
        return try self.do_push(Object{ .UnsignedInt = number });
    }

    /// Push a managed word pointer onto this Stack as an Object.
    pub inline fn do_push_word(self: *Self, word: Types.GluumyWord) !*Self {
        return try self.do_push(Object{ .Word = word });
    }

    test "do_push" {
        const baseStack = try Self.init(testAllocator, null);
        defer baseStack.deinit();

        // First, fill the current stack
        var i: usize = 0;
        while (i < STACK_SIZE) {
            try expectEqual(baseStack, try baseStack.do_push_uint(42));
            i += 1;
        }
        try expectEqual(@as(usize, 42), baseStack.contents[baseStack.next_idx - STACK_SIZE / 2].?.UnsignedInt);
        try expectEqual(@as(usize, 42), baseStack.contents[baseStack.next_idx - 1].?.UnsignedInt);
        try expectEqual(@as(usize, STACK_SIZE), baseStack.next_idx);

        // Now force a new one to be allocated
        try expect(try baseStack.do_push_uint(42) != baseStack);
        try expectEqual(@as(usize, 1), baseStack.next.?.next_idx);
    }

    // Implemented in terms of do_push to cover boundary cases, and because why
    // not, I suppose.
    //
    // TODO: handle the Rc(_) types which cannot be blindly copied and expected
    // to do the right thing.
    pub fn do_dup(self: *Self) !*Self {
        try self.non_terminal_stack_guard();
        return switch ((try self.do_peek_pair()).top.*) {
            .String => InternalError.Unimplemented,
            .Symbol => InternalError.Unimplemented,
            .Opaque => InternalError.Unimplemented,
            .Word => InternalError.Unimplemented,
            else => |it| try self.do_push(it),
        };
    }

    test "do_dup" {
        const stack = try Self.init(testAllocator, null);
        defer stack.deinit();
        defer stack.deinit_guard_for_empty();

        var target = try stack.do_push_uint(42);
        target = try stack.do_dup();

        try expectEqual(@as(usize, 2), stack.next_idx);
        const top_two = try stack.do_peek_pair();
        try expectEqual(@as(usize, 42), top_two.top.*.UnsignedInt);
        try expectEqual(@as(usize, 42), top_two.bottom.?.*.UnsignedInt);
    }

    pub fn do_swap(self: *Self) StackManipulationError!void {
        try self.non_terminal_stack_guard();
        return try @call(
            .{ .modifier = .always_inline },
            self.do_swap_no_really_even_on_inner_stacks,
            .{},
        );
    }

    pub fn do_swap_no_really_even_on_inner_stacks(self: *Self) StackManipulationError!void {
        if (self.next_idx < 2 and self.prev == null) {
            return StackManipulationError.Underflow;
        }

        if (self.next_idx < 2 and self.prev.?.next_idx == 0) {
            unreachable;
        }

        const near_obj = &self.contents[self.next_idx - 1];
        const far_obj = if (self.next_idx > 1)
            &self.contents[self.next_idx - 2]
        else
            &self.prev.?.contents[self.prev.?.next_idx - 1];

        std.mem.swap(?Object, near_obj, far_obj);
    }

    test "do_swap: single stack" {
        const stack = try Self.init(testAllocator, null);
        defer stack.deinit_guard_for_empty();

        var target = try stack.do_push_uint(1);
        target = try target.do_push_uint(2);
        try target.do_swap();

        const top_two = try target.do_pop_pair();
        try expectEqual(@as(usize, 2), top_two.far.UnsignedInt);
        try expectEqual(@as(usize, 1), top_two.near.UnsignedInt);
    }

    test "do_swap: transcend stack boundaries" {
        const baseStack = try Self.init(testAllocator, null);
        defer baseStack.deinit();

        // First, fill the current stack
        var i: usize = 0;
        while (i < STACK_SIZE) {
            // Ensure that none of these operations will result in a new stack
            // being allocated.
            try expectEqual(baseStack, try baseStack.do_push_uint(1));
            i += 1;
        }
        // Now force a new one to be allocated with a single, different object
        // on it.
        const newStack = try baseStack.do_push_uint(2);
        try expect(baseStack != newStack);

        // Save us from ourselves if we call swap on the wrong stack
        // (presumably, we discarded the output of do_push).
        try expectError(
            StackManipulationError.YouAlmostCertainlyDidNotMeanToUseThisNonTerminalStack,
            baseStack.do_swap(),
        );

        try newStack.do_swap();
        const top_two = try newStack.do_pop_pair();
        try expectEqual(@as(usize, 2), top_two.far.UnsignedInt);
        try expectEqual(@as(usize, 1), top_two.near.UnsignedInt);
    }

    /// Returns the new "upper" stack.
    pub fn do_drop(self: *Self) !*Self {
        try self.non_terminal_stack_guard();
        return try @call(
            .{ .modifier = .always_inline },
            self.do_drop_no_really_even_on_inner_stacks,
            .{},
        );
    }

    /// Returns the new "upper" stack.
    ///
    // TODO: handle the Rc(_) types, deinit() if appropriate (when final copy
    // falls out of scope)
    pub fn do_drop_no_really_even_on_inner_stacks(self: *Self) !*Self {
        if (self.next_idx == 0) {
            if (self.prev) |prev| {
                // TODO: determine if it would be better to just make this
                // state unreachable, instead.
                const ret = try prev.do_drop_no_really_even_on_inner_stacks();
                self.deinit();
                return ret;
            }
            return StackManipulationError.Underflow;
        }

        // Save a ref to the "dead" object immediately, since we may need to do
        // lifecycle management on it.
        const dead = self.contents[self.next_idx - 1];

        // Now clean out the stack slot for future use, as this must be done
        // whether we had a boxed or unboxed type here.
        self.contents[self.next_idx - 1] = null;
        self.next_idx -= 1;

        // Finally, for boxed types, we need to at least decrement the
        // refcount, and potentially free the underlying memory.
        if (dead) |_dead_deref| {
            var dead_deref = _dead_deref;

            // TODO: this currently relies on an assumption that Stack and
            // Runtime share the same allocator *instance*, which is only
            // somewhat accidentally true. The type signatures of these structs
            // or initialization sequencing should be used to guarantee this,
            // or Runtime should be an expected argument to this function.
            dead_deref.deinit(self.alloc);
        }

        return self;
    }

    test "do_drop: unboxed" {
        const stack = try Self.init(testAllocator, null);
        defer stack.deinit();
        try expectEqual(@as(usize, 0), stack.next_idx);
        try expectEqual(@as(?Object, null), stack.contents[0]);

        var target = try stack.do_push_uint(1);
        try expectEqual(@as(usize, 1), (try target.do_pop()).UnsignedInt);
        try expectError(StackManipulationError.Underflow, target.do_pop());
    }

    // N.B. the auto-freeing mechanics of do_drop are being tested here, so
    // explicitly no defer->free() setups here *except* for the Stack itself.
    test "do_drop: boxed frees underlying data" {
        // TODO: use a shared String type of some sort
        const SharedStr = Rc([]u8);
        const hello_world = "Hello World!";
        // Freed by do_drop since we'll only have one reference to it
        var str = try testAllocator.alloc(u8, hello_world.len);
        std.mem.copy(u8, str[0..], hello_world);
        var shared_str = try testAllocator.create(SharedStr);
        shared_str.* = SharedStr.init(str);

        const stack = try Self.init(testAllocator, null);
        defer stack.deinit();
        try expectEqual(@as(usize, 0), stack.next_idx);
        try expectEqual(@as(?Object, null), stack.contents[0]);

        _ = try stack.do_push(Object{ .String = shared_str });
        try expectEqual(@as(usize, 1), stack.next_idx);
        try expectEqualStrings(hello_world, stack.contents[0].?.String.value.?);

        _ = try stack.do_drop();
        try expectEqual(@as(usize, 0), stack.next_idx);
        try expectEqual(@as(?Object, null), stack.contents[0]);

        // No further assertions required because Zig is awesome: the
        // GeneralPurposeAllocator will fail our tests if we've leaked anything
        // at this point.
    }
};

test {
    std.testing.refAllDecls(@This());
}
