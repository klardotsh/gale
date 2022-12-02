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

pub const StackManipulationError = error{
    Underflow,
    Overflow,
    RefuseToGrowMultipleStacks,
};

/// A doubly-linked list of doubly-linked lists: gluumy's memory model is
/// optimized around reducing heap allocations
///
/// Not thread-safe. Use channels or something.
// TODO:
// - Docs
// - Sanitize entries when rolling back stack pointer?
// - Stop leaking literally everything: keep no more than N+1 stacks allocated
//   at a time, once self->next->next->head == 0, it's time to start calling
//   free.
pub const Stack = struct {
    // Those finding they need more per-stack space should compile their own
    // project-specific gluumy build changing the constant as appropriate.
    // Unlike many languages where mucking about with the internals is
    // faux-pas, in gluumy it is encouraged on a "if you know you really need
    // it" basis.
    //
    // TODO: configurable in build.zig
    const STACK_SIZE = 2048;

    const Self = @This();

    alloc: Allocator,
    prev: ?*Stack,
    next: ?*Stack,
    head: usize,
    contents: [STACK_SIZE]?Object,

    pub fn init(alloc: Allocator, prev: ?*Stack) !*Self {
        var stack = try alloc.create(Self);
        stack.* = .{
            .alloc = alloc,
            .prev = prev,
            .next = null,
            .head = 0,
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
        target.contents[target.head] = obj;
        target.head += 1;
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
        try expectEqual(@as(usize, STACK_SIZE), baseStack.head);

        // Now force a new one to be allocated
        try expect(try baseStack.do_push(obj) != baseStack);
        try expectEqual(@as(usize, 1), baseStack.next.?.head);
    }

    pub fn do_swap(self: *Self) StackManipulationError!void {
        if (self.head < 2 and self.prev == null) {
            return StackManipulationError.Underflow;
        }

        if (self.head < 2 and self.prev.?.head == 0) {
            unreachable;
        }

        const near_obj = &self.contents[self.head];
        const far_obj = if (self.head > 1)
            &self.contents[self.head - 1]
        else
            &self.prev.contents[self.prev.head];

        std.mem.swap(Object, near_obj, far_obj);
    }

    test "do_swap" {
        const baseStack = try Self.init(testAllocator, null);
        defer baseStack.deinit();
        // try expectEqual(@as(?*Self, null), try baseStack.expand_to_fit(Stack.STACK_SIZE / 2 + 1));
        // try expect(try baseStack.expand_to_fit(Stack.STACK_SIZE / 2 + 1) != null);
        // try expectError(StackManipulationError.RefuseToGrowMultipleStacks, baseStack.expand_to_fit(Stack.STACK_SIZE + 1));
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
        if (self.head + count > STACK_SIZE * 2) {
            return StackManipulationError.RefuseToGrowMultipleStacks;
        }

        if (self.head + count > STACK_SIZE) {
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
        baseStack.head = 1;
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
