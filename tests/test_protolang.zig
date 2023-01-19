// Gale's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

const std = @import("std");
const Allocator = std.mem.Allocator;
const testAllocator: Allocator = std.testing.allocator;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const gale = @import("gale");
const Runtime = gale.Runtime;

test "push primitives" {
    var rt = try Runtime.init(testAllocator);
    defer rt.deinit_guard_for_empty_stack();

    // Push four numbers to the stack individually
    try rt.eval("1");
    try rt.eval("2/i");
    try rt.eval("3.14");
    try rt.eval("4");

    // Push a symbol for giggles
    try rt.eval(":something");

    // Now push several more in one library call
    try rt.eval("5/u 6/i 7.5");

    var float_signed_unsigned = try rt.stack_pop_trio();
    defer {
        rt.release_heaped_object_reference(&float_signed_unsigned.near);
        rt.release_heaped_object_reference(&float_signed_unsigned.far);
        rt.release_heaped_object_reference(&float_signed_unsigned.farther);
    }
    try expectApproxEqAbs(
        @as(f64, 7.5),
        float_signed_unsigned.near.Float,
        @as(f64, 0.0000001),
    );
    try expectEqual(@as(isize, 6), float_signed_unsigned.far.SignedInt);
    try expectEqual(@as(usize, 5), float_signed_unsigned.farther.UnsignedInt);

    var something_symbol = try rt.stack_pop();
    defer {
        // TODO: uncomment this once Runtime.get_or_put_symbol is fixed to
        // increment refcount correctly, this *should* be leaking RAM as-is but
        // is not, unearthing a whole class of bugs (5 addresses leaking in 1
        // test in libgale alone)
        //
        // rt.release_heaped_object_reference(&something_symbol);
    }
    try expectEqualStrings("something", something_symbol.Symbol.value.?);

    var inferunsigned_float_signed = try rt.stack_pop_trio();
    defer {
        rt.release_heaped_object_reference(&inferunsigned_float_signed.near);
        rt.release_heaped_object_reference(&inferunsigned_float_signed.far);
        rt.release_heaped_object_reference(&inferunsigned_float_signed.farther);
    }
    try expectEqual(@as(isize, 4), inferunsigned_float_signed.near.SignedInt);
    try expectApproxEqAbs(
        @as(f64, 3.14),
        inferunsigned_float_signed.far.Float,
        @as(f64, 0.0000001),
    );
    try expectEqual(@as(isize, 2), inferunsigned_float_signed.farther.SignedInt);

    var bottom = try rt.stack_pop();
    defer rt.release_heaped_object_reference(&bottom);
    try expectEqual(@as(isize, 1), bottom.SignedInt);
}
