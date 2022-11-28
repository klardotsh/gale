// gluumy's canonical implementation and standard library is released to the
// public domain (or your jurisdiction's closest legal equivalent) under the
// Creative Commons Zero 1.0 dedication, distributed alongside this source in a
// file called COPYING.

const std = @import("std");
const IAllocator = std.mem.Allocator;
const Object = @import("./object.zig").Object;

pub const StackManipulationError = error{
    Underflow,
    Overflow,
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

    alloc: *IAllocator,
    prev: ?*Stack,
    next: ?*Stack,
    head: usize,
    contents: [STACK_SIZE]Object,

    pub fn init(alloc: *IAllocator, prev: ?*Stack) !*Self {
        var stack = try alloc.create(Self);
        stack.* = .{
            .alloc = alloc,
            .prev = prev,
            .next = null,
            .head = 0,
        };
        return stack;
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
        var next = try Self.init(self.alloc, &self);
        self.next = next;
    }
};
