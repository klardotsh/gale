// gluumy's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

const std = @import("std");
const Allocator = std.mem.Allocator;
const testAllocator: Allocator = std.testing.allocator;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;
const expectEqual = std.testing.expectEqual;

const gluumy = @import("gluumy");
const Runtime = gluumy.Runtime;

test "push primitives" {
    var rt = try Runtime.init(testAllocator);
    defer rt.deinit_guard_for_empty_stack();

    // Push three numbers to the stack individually
    try rt.run_input("1");
    try rt.run_input("2/i");
    try rt.run_input("3.14");

    // Now push several more in one library call
    try rt.run_input("4 5/u 6/i 7.5");

    const float_signed_unsigned = try rt.stack_pop_trio();
    defer {
        float_signed_unsigned.near.deinit();
        float_signed_unsigned.far.deinit();
        float_signed_unsigned.farther.deinit();
    }
    try expectApproxEqAbs(
        @as(f64, 7.5),
        float_signed_unsigned.near.Float,
        @as(f64, 0.0000001),
    );
    try expectEqual(@as(isize, 6), float_signed_unsigned.far.SignedInt);
    try expectEqual(@as(usize, 5), float_signed_unsigned.farther.SignedInt);

    const inferunsigned_float_signed = try rt.stack_pop_trio();
    defer {
        inferunsigned_float_signed.near.deinit();
        inferunsigned_float_signed.far.deinit();
        inferunsigned_float_signed.farther.deinit();
    }
    try expectEqual(@as(usize, 4), inferunsigned_float_signed.near.UnsignedInt);
    try expectApproxEqAbs(
        @as(f64, 3.14),
        inferunsigned_float_signed.far.Float,
        @as(f64, 0.0000001),
    );
    try expectEqual(@as(isize, 2), inferunsigned_float_signed.farther.SignedInt);

    const bottom = try rt.stack_pop();
    defer bottom.deinit();
    try expectEqual(@as(usize, 1), bottom.SignedInt);
}
