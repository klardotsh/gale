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

/// A doubly-linked list of doubly-linked lists: gluumy's memory model is
/// optimized around reducing heap allocations
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
        self.alloc.destroy(self);
    }

    // Pushes an object to the top of this stack or a newly-created stack, as
    // necessary based on available space. Returns pointer to whichever stack
    // the object ended up on.
    pub fn do_push(self: *Self, obj: Object) !*Self {
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
        try expectEqual(@as(usize, STACK_SIZE), baseStack.next_idx);

        // Now force a new one to be allocated
        try expect(try baseStack.do_push(obj) != baseStack);
        try expectEqual(@as(usize, 1), baseStack.next.?.next_idx);
    }

    pub fn do_swap(self: *Self) StackManipulationError!void {
        if (self.next != null) {
            return StackManipulationError.YouAlmostCertainlyDidNotMeanToUseThisNonTerminalStack;
        }

        return try self.do_swap_no_really_even_on_inner_stacks();
    }

    pub inline fn do_swap_no_really_even_on_inner_stacks(self: *Self) StackManipulationError!void {
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
    ///
    /// As with all multi-stack juggling operations here, operations right at
    /// the edge of the stack space bleeding into the next stack are unlikely
    /// to be performant, particularly those that juggle that boundary
    /// repeatedly.
    //
    // ^ That last tidbit of documentation belongs elsewhere, probably at the
    // top level of this struct.
    fn onwards(self: *Self) !*Self {
        var next = try Self.init(self.alloc, self);
        self.next = next;
        return next;
    }
};

test {
    std.testing.refAllDecls(@This());
}
