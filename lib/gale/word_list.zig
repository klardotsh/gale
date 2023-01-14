// Gale's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Types = @import("./types.zig");

/// A managed std.ArrayList of *Types.HeapedWords.
pub const WordList = struct {
    const Self = @This();
    const Inner = std.ArrayList(*Types.HeapedWord);

    contents: Inner,

    pub fn init(alloc: Allocator) Self {
        return Self{
            .contents = Inner.init(alloc),
        };
    }

    /// Destroy all contents of self (following the nested garbage collection
    /// rules discussed in `Rc.decrement_and_prune`'s documentation) and any
    /// overhead metadata incurred along the way.
    pub fn deinit(self: *Self, alloc: Allocator) void {
        while (self.contents.popOrNull()) |entry| {
            _ = entry.decrement_and_prune(.DeinitInnerWithAllocDestroySelf, alloc);
        }
        self.contents.deinit();
    }

    pub fn items(self: *Self) []*Types.HeapedWord {
        return self.contents.items;
    }

    pub fn len(self: *Self) usize {
        return self.contents.items.len;
    }

    pub fn append(self: *Self, item: *Types.HeapedWord) Allocator.Error!void {
        return try self.contents.append(item);
    }
};

test {
    std.testing.refAllDecls(@This());
}
