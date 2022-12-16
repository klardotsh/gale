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
const expectError = std.testing.expectError;

const Object = @import("./object.zig").Object;

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
        self.alloc.destroy(self);
    }

    pub fn banish_top_object(self: *Self) !*Object {
        const banish_target = try self.alloc.create(Object);
        errdefer self.deinit_banished_object(banish_target);

        const top = (try self.do_peek_pair()).top;
        return switch (top.*) {
            Object.Word, Object.Opaque => error.Unimplemented,
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

        _ = try stack.do_push(Object{ .UnsignedInt = 1 });
        const one_ptr = try stack.banish_top_object();
        defer stack.deinit_banished_object(one_ptr);
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
        const baseStack = try Self.init(testAllocator, null);
        defer baseStack.deinit();

        try expectError(StackManipulationError.Underflow, baseStack.do_peek_pair());

        _ = try baseStack.do_push(Object{ .UnsignedInt = 1 });
        const top_one = try baseStack.do_peek_pair();
        try expectEqual(@as(usize, 1), top_one.top.*.UnsignedInt);
        try expectEqual(@as(?*Object, null), top_one.bottom);

        _ = try baseStack.do_push(Object{ .UnsignedInt = 2 });

        const top_two = try baseStack.do_peek_pair();
        try expectEqual(@as(usize, 2), top_two.top.*.UnsignedInt);
        try expectEqual(@as(usize, 1), top_two.bottom.?.*.UnsignedInt);
    }

    pub fn do_peek(self: *Self) !*Object {
        return (try self.do_peek_pair()).top;
    }

    // Pushes an object to the top of this stack or a newly-created stack, as
    // necessary based on available space. Returns pointer to whichever stack
    // the object ended up on.
    pub fn do_push(self: *Self, obj: Object) !*Self {
        try self.non_terminal_stack_guard();
        const target = try self.expand_to_fit(1) orelse self;
        target.contents[target.next_idx] = obj;
        target.next_idx += 1;
        return target;
    }

    test "do_push" {
        const baseStack = try Self.init(testAllocator, null);
        defer baseStack.deinit();
        const obj = Object{
            .UnsignedInt = 42,
        };

        // First, fill the current stack
        var i: usize = 0;
        while (i < STACK_SIZE) {
            try expectEqual(baseStack, try baseStack.do_push(obj));
            i += 1;
        }
        try expectEqual(@as(usize, 42), baseStack.contents[baseStack.next_idx - STACK_SIZE / 2].?.UnsignedInt);
        try expectEqual(@as(usize, 42), baseStack.contents[baseStack.next_idx - 1].?.UnsignedInt);
        try expectEqual(@as(usize, STACK_SIZE), baseStack.next_idx);

        // Now force a new one to be allocated
        try expect(try baseStack.do_push(obj) != baseStack);
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
            Object.String => error.Unimplemented,
            Object.Symbol => error.Unimplemented,
            Object.Opaque => error.Unimplemented,
            Object.Word => error.Unimplemented,
            else => |it| try self.do_push(it),
        };
    }

    test "do_dup" {
        const stack = try Self.init(testAllocator, null);
        defer stack.deinit();
        const obj = Object{
            .UnsignedInt = 42,
        };
        _ = try stack.do_push(obj);
        _ = try stack.do_dup();
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
        const baseStack = try Self.init(testAllocator, null);
        defer baseStack.deinit();
        baseStack.contents[0] = Object{ .UnsignedInt = 1 };
        baseStack.contents[1] = Object{ .UnsignedInt = 2 };
        // Even with leftover garbage on the stack, the stack pointer is the
        // source of truth: refuse to swap this manually-mangled stack with the
        // pointer in the wrong place!
        try expectError(StackManipulationError.Underflow, baseStack.do_swap());
        baseStack.next_idx += 2;

        try baseStack.do_swap();
        try expectEqual(@as(usize, 2), baseStack.contents[0].?.UnsignedInt);
        try expectEqual(@as(usize, 1), baseStack.contents[1].?.UnsignedInt);
    }

    test "do_swap: transcend stack boundaries" {
        const baseStack = try Self.init(testAllocator, null);
        defer baseStack.deinit();

        const obj = Object{ .UnsignedInt = 1 };

        // First, fill the current stack
        var i: usize = 0;
        while (i < STACK_SIZE) {
            _ = try baseStack.do_push(obj);
            i += 1;
        }
        // Now force a new one to be allocated with a single, different object
        // on it.
        const newStack = try baseStack.do_push(Object{ .UnsignedInt = 2 });
        try expect(baseStack != newStack);

        // Save us from ourselves if we call swap on the wrong stack
        // (presumably, we discarded the output of do_push).
        try expectError(StackManipulationError.YouAlmostCertainlyDidNotMeanToUseThisNonTerminalStack, baseStack.do_swap());

        try newStack.do_swap();
        try expectEqual(@as(usize, 2), baseStack.contents[STACK_SIZE - 1].?.UnsignedInt);
        try expectEqual(@as(usize, 1), newStack.contents[0].?.UnsignedInt);
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
    pub fn do_drop_no_really_even_on_inner_stacks(self: *Self) StackManipulationError!*Self {
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
        self.contents[self.next_idx - 1] = null;
        self.next_idx -= 1;
        return self;
    }

    test "do_drop" {
        const baseStack = try Self.init(testAllocator, null);
        defer baseStack.deinit();
        try expectEqual(@as(usize, 0), baseStack.next_idx);
        try expectEqual(@as(?Object, null), baseStack.contents[0]);

        const obj = Object{ .UnsignedInt = 1 };
        _ = try baseStack.do_push(obj);
        try expectEqual(@as(usize, 1), baseStack.next_idx);
        try expectEqual(@as(usize, 1), baseStack.contents[0].?.UnsignedInt);

        _ = try baseStack.do_drop();
        try expectEqual(@as(usize, 0), baseStack.next_idx);
        try expectEqual(@as(?Object, null), baseStack.contents[0]);
    }
};

test {
    std.testing.refAllDecls(@This());
}
