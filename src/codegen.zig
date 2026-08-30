// SPDX-FileCopyrightText: 2026 Iyad
//
// SPDX-License-Identifier: Apache-2.0

//! Machine code generation, dispatched on the target architecture.
//!
//! Every backend emits machine code that is called as a c function, taking the
//! tape, its length and a `Runtime`, and returning a `Status`.

const builtin = @import("builtin");

/// An error the generated code reports through its `Status`.
pub const Error = error{
    /// A move took the pointer past the last cell.
    PointerOverflow,

    /// A move took the pointer before the first cell.
    PointerUnderflow,
};

/// The value generated code leaves behind when it returns.
pub const Status = enum(u32) {
    ok,
    pointer_overflow,
    pointer_underflow,

    /// Returns the error this status stands for.
    pub fn toError(self: Status) Error!void {
        return switch (self) {
            .ok => {},
            .pointer_overflow => error.PointerOverflow,
            .pointer_underflow => error.PointerUnderflow,
        };
    }
};

/// Generates machine code for the target architecture, one instruction per `u32`.
pub const generate = switch (builtin.cpu.arch) {
    .aarch64 => @import("codegen/aarch64.zig").generate,
    else => @compileError("no backend for this architecture"),
};
