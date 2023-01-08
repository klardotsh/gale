// gluumy's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

const Runtime = @import("./runtime.zig").Runtime;

pub fn push_one(runtime: *Runtime) anyerror!void {
    try runtime.stack_push_uint(1);
}

pub fn push_two(runtime: *Runtime) anyerror!void {
    try runtime.stack_push_uint(2);
}
