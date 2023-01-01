// gluumy's canonical implementation and standard library is released to the
// public domain (or your jurisdiction's closest legal equivalent) under the
// Creative Commons Zero 1.0 dedication, distributed alongside this source in a
// file called COPYING.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Types = @import("./types.zig");

/// A managed std.ArrayList of Types.GluumyWords.
pub const WordList = struct {
    const Self = @This();
    const Inner = std.ArrayList(Types.GluumyWord);

    contents: Inner,

    pub fn init(alloc: Allocator) Self {
        return Self{
            .contents = Inner.init(alloc),
        };
    }

    /// Destroy all contents of self (following the nested garbage collection
    /// rules discussed in `Rc.decrement_and_prune_deinit_with_alloc_inner`'s
    /// documentation) and any overhead metadata incurred along the way.
    pub fn deinit(self: *Self, alloc: Allocator) void {
        while (self.contents.popOrNull()) |entry| {
            _ = entry.decrement_and_prune_deinit_with_alloc_inner(alloc);
        }
        self.contents.deinit();
    }

    pub fn items(self: *Self) []Types.GluumyWord {
        return self.contents.items;
    }

    pub fn len(self: *Self) usize {
        return self.contents.items.len;
    }

    pub fn append(self: *Self, item: Types.GluumyWord) Allocator.Error!void {
        return try self.contents.append(item);
    }
};
