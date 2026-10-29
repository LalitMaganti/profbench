// Copyright 2026 The Profbench Authors.
// SPDX-License-Identifier: Apache-2.0

//! A small, generic command-line library: commands and flags are data, help is
//! generated from them, and output is styled through semantic color roles.
//! Nothing in here knows about profbench.

pub const App = @import("app.zig").App;
pub const run = @import("app.zig").run;
pub const Command = @import("command.zig").Command;
pub const Context = @import("command.zig").Context;
pub const Flag = @import("command.zig").Flag;
pub const Group = @import("command.zig").Group;
pub const Parsed = @import("args.zig").Parsed;
pub const color = @import("color.zig");

test {
    _ = @import("args.zig");
    _ = @import("color.zig");
    _ = @import("help.zig");
    _ = @import("suggest.zig");
}
