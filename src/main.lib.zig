// gluumy's canonical implementation and standard library is released under the
// Zero-Clause BSD License, distributed alongside this source in a file called
// COPYING.

// TODO: this file should be <root>/lib/main.zig, and the library called
// "libgluumy" in build.zig et. al.

pub const InternalError = @import("./internal_error.zig");
pub const Runtime = @import("./runtime.zig").Runtime;
