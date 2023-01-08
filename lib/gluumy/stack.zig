// gluumy's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const testAllocator: Allocator = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

const builtin = @import("builtin");

const InternalError = @import("./internal_error.zig").InternalError;
const Object = @import("./object.zig").Object;
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
        if (self.next) |next| next.deinit();

        if (self.prev) |prev| prev.next = null;

        while (self.next_idx > 0) {
            _ = self.do_drop() catch null;
        }

        self.alloc.destroy(self);
    }

    // TODO: docs about stack jumping behavior here
    // TODO: see if this should just be the mainline deinit() function instead
    // or if they can otherwise be merged
    pub fn deinit_from_bottom(self: *Self) void {
        if (self.prev) |prev| {
            prev.deinit_from_bottom();
        } else {
            self.deinit();
        }
    }

    /// Deinitialize this stack, but only if it is empty. This is a helper
    /// function for tests only (all other attempts to use this will result in
    /// a @compileError) to ensure no unexpected garbage is left behind on the
    /// stack after the test. In tests, this is almost certainly the correct
    /// function to use, except when testing garbage collection itself, and
    /// should be called with `defer` immediately after the Stack is
    /// instantiated (thus the use of `@panic` instead of assertions from
    /// `std.testing`, since `defer try` is not valid in Zig).
    ///
    /// For non-test deinitialization, see `deinit`.
    pub fn deinit_guard_for_empty(self: *Self) void {
        if (!builtin.is_test) {
            @compileError("deinit_guard_for_empty should NEVER be used outside of the test framework");
        }

        if (self.do_peek_pair()) |_| {} else |err| {
            if (err != StackManipulationError.Underflow) {
                std.debug.panic("do_peek_pair returned non-Underflow error: {any}", .{err});
            }

            return self.deinit();
        }

        std.debug.panic("stack was not empty at deinit time", .{});
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
        defer baseStack.deinit_guard_for_empty();

        try expectError(
            StackManipulationError.RefuseToGrowMultipleStacks,
            baseStack.expand_to_fit(Stack.STACK_SIZE * 2 + 1),
        );
        try expectEqual(@as(?*Self, null), try baseStack.expand_to_fit(STACK_SIZE / 2 + 1));
        const new_stack = try baseStack.expand_to_fit(STACK_SIZE * 2);
        try expect(new_stack != null);
        try expectError(
            StackManipulationError.RefuseToGrowMultipleStacks,
            new_stack.?.expand_to_fit(Stack.STACK_SIZE * 2 + 1),
        );
        new_stack.?.deinit();
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

    pub fn do_peek_trio(self: *Self) !Types.PeekTrio {
        try self.non_terminal_stack_guard();
        return try @call(
            .{ .modifier = .always_inline },
            self.do_peek_trio_no_really_even_on_inner_stacks,
            .{},
        );
    }

    pub fn do_peek_trio_no_really_even_on_inner_stacks(self: *Self) !Types.PeekTrio {
        if (self.next_idx == 0) {
            if (self.prev) |prev| {
                return prev.do_peek_trio_no_really_even_on_inner_stacks();
            }

            return StackManipulationError.Underflow;
        }

        if (self.next_idx == 1) {
            return Types.PeekTrio{
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
            return Types.PeekTrio{
                .near = &self.contents[1].?,
                .far = &self.contents[0].?,
                .farther = if (self.prev) |prev|
                    &prev.contents[prev.next_idx - 1].?
                else
                    null,
            };
        }

        return Types.PeekTrio{
            .near = &self.contents[self.next_idx - 1].?,
            .far = &self.contents[self.next_idx - 2].?,
            .farther = &self.contents[self.next_idx - 3].?,
        };
    }

    test "do_peek_trio" {
        const stack = try Self.init(testAllocator, null);
        defer stack.deinit_guard_for_empty();

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

        target = try target.do_drop();
        target = try target.do_drop();
        target = try target.do_drop();
    }

    pub fn do_peek_pair(self: *Self) !Types.PeekPair {
        try self.non_terminal_stack_guard();
        return try @call(
            .{ .modifier = .always_inline },
            self.do_peek_pair_no_really_even_on_inner_stacks,
            .{},
        );
    }

    pub fn do_peek_pair_no_really_even_on_inner_stacks(self: *Self) !Types.PeekPair {
        if (self.next_idx == 0) {
            if (self.prev) |prev| {
                return prev.do_peek_pair_no_really_even_on_inner_stacks();
            }

            return StackManipulationError.Underflow;
        }

        if (self.next_idx == 1) {
            return Types.PeekPair{
                .near = &self.contents[0].?,
                .far = if (self.prev) |prev|
                    &prev.contents[prev.next_idx - 1].?
                else
                    null,
            };
        }

        return Types.PeekPair{
            .near = &self.contents[self.next_idx - 1].?,
            .far = &self.contents[self.next_idx - 2].?,
        };
    }

    test "do_peek_pair" {
        const stack = try Self.init(testAllocator, null);
        defer stack.deinit_guard_for_empty();

        try expectError(StackManipulationError.Underflow, stack.do_peek_pair());

        var target = try stack.do_push_uint(1);
        const top_one = try target.do_peek_pair();
        try expectEqual(@as(usize, 1), top_one.near.*.UnsignedInt);
        try expectEqual(@as(?*Object, null), top_one.far);

        target = try target.do_push_uint(2);
        const top_two = try target.do_peek_pair();
        try expectEqual(@as(usize, 2), top_two.near.*.UnsignedInt);
        try expectEqual(@as(usize, 1), top_two.far.?.*.UnsignedInt);

        target = try target.do_drop();
        target = try target.do_drop();
    }

    pub inline fn do_peek(self: *Self) !*Object {
        return (try self.do_peek_pair()).near;
    }

    /// Remove the top item off of this stack and return it, along with a
    /// pointer to which Stack object to perform future operations on. If this
    /// is the bottom Stack and there are no contents remaining, an Underflow
    /// is raised.
    pub fn do_pop(self: *Self) !Types.PopSingle {
        if (self.next_idx == 0) {
            if (self.prev) |prev| {
                self.deinit();
                return prev.do_pop();
            }

            return StackManipulationError.Underflow;
        }

        self.next_idx -= 1;
        if (self.contents[self.next_idx]) |obj| {
            self.contents[self.next_idx] = null;
            return Types.PopSingle{
                .item = obj,
                .now_top_stack = self,
            };
        }

        unreachable;
    }

    test "do_pop" {
        const stack = try Self.init(testAllocator, null);
        defer stack.deinit_guard_for_empty();
        var target = try stack.do_push_uint(41);
        target = try stack.do_push_uint(42);
        const pop_42 = try target.do_pop();
        try expectEqual(@as(usize, 42), pop_42.item.UnsignedInt);
        target = pop_42.now_top_stack;
        const pop_41 = try target.do_pop();
        try expectEqual(@as(usize, 41), pop_41.item.UnsignedInt);
        target = pop_41.now_top_stack;
        try expectError(StackManipulationError.Underflow, target.do_pop());
    }

    /// Remove the top two items off of this stack and return them, along with
    /// a pointer to which Stack object to perform future operations on. If
    /// this is the bottom Stack and there aren't at least two Objects
    /// remaining, an Underflow is raised. If this happens with one Object on
    /// the Stack, it will remain there.
    pub fn do_pop_pair(self: *Self) !Types.PopPair {
        const top_two = try self.do_peek_pair();

        if (top_two.far) |_| {
            const near_pop = try self.do_pop();
            const far_pop = try near_pop.now_top_stack.do_pop();

            return Types.PopPair{
                .near = near_pop.item,
                .far = far_pop.item,
                .now_top_stack = far_pop.now_top_stack,
            };
        }

        return StackManipulationError.Underflow;
    }

    test "do_pop_pair" {
        const stack = try Self.init(testAllocator, null);
        defer stack.deinit_guard_for_empty();

        var target = try stack.do_push_uint(41);
        target = try stack.do_push_uint(42);
        const pairing = try target.do_pop_pair();
        try expectEqual(@as(usize, 42), pairing.near.UnsignedInt);
        try expectEqual(@as(usize, 41), pairing.far.UnsignedInt);
        try expectError(StackManipulationError.Underflow, target.do_pop());
    }

    /// Remove the top three items off of this stack and return them, along
    /// with a pointer to which Stack object to perform future operations on.
    /// If this is the bottom Stack and there aren't at least three Objects
    /// remaining, an Underflow is raised. If this happens with one or two
    /// Objects on the Stack, they will remain there.
    pub fn do_pop_trio(self: *Self) !Types.PopTrio {
        const top_three = try self.do_peek_trio();

        if (top_three.farther) |_| {
            const near_pop = try self.do_pop();
            const far_pop = try near_pop.now_top_stack.do_pop();
            const farther_pop = try far_pop.now_top_stack.do_pop();

            return Types.PopTrio{
                .near = near_pop.item,
                .far = far_pop.item,
                .farther = farther_pop.item,
                .now_top_stack = farther_pop.now_top_stack,
            };
        }

        return StackManipulationError.Underflow;
    }

    test "do_pop_trio" {
        const stack = try Self.init(testAllocator, null);
        defer stack.deinit_guard_for_empty();

        var target = try stack.do_push_uint(40);
        target = try stack.do_push_uint(41);
        target = try stack.do_push_uint(42);

        const trio = try target.do_pop_trio();
        try expectEqual(@as(usize, 42), trio.near.UnsignedInt);
        try expectEqual(@as(usize, 41), trio.far.UnsignedInt);
        try expectEqual(@as(usize, 40), trio.farther.UnsignedInt);
    }

    /// Pushes an object to the top of this stack or a newly-created stack, as
    /// necessary based on available space. Returns pointer to whichever stack
    /// the object ended up on.
    pub fn do_push(self: *Self, obj: Object) !*Self {
        try self.non_terminal_stack_guard();
        const target = try self.expand_to_fit(1) orelse self;
        target.contents[target.next_idx] = try obj.ref();
        target.next_idx += 1;
        return target;
    }

    /// Push a Zig boolean value onto this Stack as an Object.
    pub inline fn do_push_bool(self: *Self, item: bool) !*Self {
        return try self.do_push(Object{ .Boolean = item });
    }

    /// Push a Zig floating-point value onto this Stack as an Object.
    pub inline fn do_push_float(self: *Self, item: f64) !*Self {
        return try self.do_push(Object{ .Float = item });
    }

    /// Push a Zig signed integer value onto this Stack as an Object.
    pub inline fn do_push_sint(self: *Self, number: isize) !*Self {
        return try self.do_push(Object{ .SignedInt = number });
    }

    /// Push a managed string pointer onto this Stack as an Object.
    pub inline fn do_push_string(self: *Self, string: Types.GluumyString) !*Self {
        return try self.do_push(Object{ .String = string });
    }

    /// Push a managed symbol pointer onto this Stack as an Object.
    pub inline fn do_push_symbol(self: *Self, symbol: Types.GluumySymbol) !*Self {
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

    /// Duplicate the top Object on this stack via do_peek and do_push,
    /// returning a pointer to the Stack the Object ended up on.
    pub fn do_dup(self: *Self) !*Self {
        try self.non_terminal_stack_guard();
        // By implementing in terms of do_push we get Rc(_) incrementing for
        // free
        return try self.do_push((try self.do_peek_pair()).near.*);
    }

    test "do_dup" {
        const stack = try Self.init(testAllocator, null);
        defer stack.deinit_guard_for_empty();

        var target = try stack.do_push_uint(42);
        target = try stack.do_dup();

        try expectEqual(@as(usize, 2), stack.next_idx);
        const top_two = try stack.do_pop_pair();
        try expectEqual(@as(usize, 42), top_two.near.UnsignedInt);
        try expectEqual(@as(usize, 42), top_two.far.UnsignedInt);
    }

    pub fn do_2dupshuf(self: *Self) !*Self {
        try self.non_terminal_stack_guard();
        const top_two = try self.do_peek_pair();

        if (top_two.far == null) return StackManipulationError.Underflow;

        // TODO: avoid some overhead of jumping to do_push here by doing a
        // self.expand_to_fit(2) and handling the edge case I'm too lazy to
        // deal with right now where n+1 fits on the current stack, but n+2
        // forces a new allocation (split-stack case)
        //
        // technically the current implementation is "safest", since it'll do a
        // terminal guard each time, ensuring that we actually use target for
        // the second push, and not self...
        var target = try self.do_push(top_two.far.?.*);
        return try target.do_push(top_two.near.*);
    }

    test "do_2dupshuf" {
        const stack = try Self.init(testAllocator, null);
        defer stack.deinit_guard_for_empty();

        var target = try stack.do_push_uint(420);
        target = try stack.do_push_uint(69);
        target = try stack.do_2dupshuf();

        try expectEqual(@as(usize, 4), target.next_idx);
        const top_three = try target.do_pop_trio();
        try expectEqual(@as(usize, 69), top_three.near.UnsignedInt);
        try expectEqual(@as(usize, 420), top_three.far.UnsignedInt);
        try expectEqual(@as(usize, 69), top_three.farther.UnsignedInt);
        target = top_three.now_top_stack;

        const top = try target.do_pop();
        try expectEqual(@as(usize, 420), top.item.UnsignedInt);
        target = top.now_top_stack;

        try expectError(StackManipulationError.Underflow, target.do_pop());
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

    /// Remove the top item off of this stack. Return a pointer to which Stack
    /// object to perform future operations on. If this is the bottom Stack and
    /// there are no contents remaining, an Underflow is raised. If this is not
    /// the top Stack, a very wordy error is raised to save callers from
    /// usually-bug-derived-and-incorrect risky behavior; if you're absolutely
    /// sure you know what you're doing, see
    /// `do_drop_no_really_even_on_inner_stacks` instead.
    pub fn do_drop(self: *Self) !*Self {
        try self.non_terminal_stack_guard();
        return try @call(
            .{ .modifier = .always_inline },
            self.do_drop_no_really_even_on_inner_stacks,
            .{},
        );
    }

    /// Remove the top item off of this stack. Return a pointer to which Stack
    /// object to perform future operations on. If this is the bottom Stack and
    /// there are no contents remaining, an Underflow is raised.
    pub fn do_drop_no_really_even_on_inner_stacks(self: *Self) !*Self {
        var dropped = try self.do_pop();

        // TODO: this currently relies on an assumption that Stack and Runtime
        // share the same allocator *instance*, which is only somewhat
        // accidentally true. The type signatures of these structs or
        // initialization sequencing should be used to guarantee this, or
        // Runtime should be an expected argument to this function.
        dropped.item.deinit(self.alloc);

        return dropped.now_top_stack;
    }

    // The auto-freeing mechanics of do_drop are being tested here, so
    // explicitly no defer->free() setups here *except* for the Stack itself.
    test "do_drop" {
        const hello_world = "Hello World!";
        var str = try testAllocator.alloc(u8, hello_world.len);
        std.mem.copy(u8, str[0..], hello_world);
        var shared_str = try testAllocator.create(Types.HeapedString);
        shared_str.* = Types.HeapedString.init(str);

        const stack = try Self.init(testAllocator, null);
        defer stack.deinit_guard_for_empty();

        var target = try stack.do_push_string(shared_str);
        target = try target.do_drop();
        try expectEqual(@as(usize, 0), target.next_idx);
        try expectError(StackManipulationError.Underflow, target.do_pop());
    }
};

test {
    std.testing.refAllDecls(@This());
}
