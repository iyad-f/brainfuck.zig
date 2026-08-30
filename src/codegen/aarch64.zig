// SPDX-FileCopyrightText: 2026 Iyad
//
// SPDX-License-Identifier: Apache-2.0

//! A backend emitting aarch64 machine code for an `Ir`.
//!
//!    x19  index of the current cell
//!    x20  tape base
//!    x21  tape length
//!    x22  the runtime
//!
//! Those are callee saved, so they survive the calls into zig that `read` and `write`
//! make.
//!
//! Encodings are written as hex beside the instruction they assemble to, taken from
//! `zig cc -c` and read back with `objdump -d`.

const builtin = @import("builtin");
const std = @import("std");
const debug = std.debug;
const Allocator = std.mem.Allocator;
const Ir = @import("../Ir.zig");

comptime {
    if (builtin.cpu.arch != .aarch64) @compileError("this backend emits aarch64 only");
}

/// Saves the callee saved registers, fills them from the arguments, then jumps
/// over `error_exit`.
const prologue = [_]u32{
    0xa9bd53f3, // stp x19, x20, [sp, #-48]!
    0xa9015bf5, // stp x21, x22, [sp, #16]
    0xf90013fe, // str x30, [sp, #32]
    0xaa0003f4, // mov x20, x0 tape base
    0xaa0103f5, // mov x21, x1 tape length
    0xaa0203f6, // mov x22, x2 runtime
    0xd2800013, // mov x19, #0 index
    0x14000009, // b +9, over the error_exit
};

/// Sets a failing status and returns. Only reached by branching to it.
const error_exit = [_]u32{
    0xf100027f, // cmp x19, #0
    0x52800020, // mov w0, #1, Status.pointer_overflow
    0x52800041, // mov w1, #2, Status.pointer_underflow
    0x1a80b020, // csel w0, w1, w0, lt, a negative index underflowed
    0xf94013fe, // ldr x30, [sp, #32]
    0xa9415bf5, // ldp x21, x22, [sp, #16]
    0xa8c353f3, // ldp x19, x20, [sp], #48
    0xd65f03c0, // ret
};

/// Sets an ok status and returns.
const epilogue = [_]u32{
    0x52800000, // mov w0, #0
    0xf94013fe, // ldr x30, [sp, #32]
    0xa9415bf5, // ldp x21, x22, [sp, #16]
    0xa8c353f3, // ldp x19, x20, [sp], #48
    0xd65f03c0, // ret
};

/// Where `error_exit` starts in the emitted code, every bounds check branches to it.
const error_exit_index: comptime_int = prologue.len;

comptime {
    // The branch ending the prologue has to land just past the error exit.
    debug.assert(prologue[prologue.len - 1] == 0x14000000 | (error_exit.len + 1));
}

/// Generates aarch64 machine code for `ir`, one instruction per `u32`.
///
/// The result should be freed with `allocator.free`.
pub fn generate(allocator: Allocator, ir: Ir) Allocator.Error![]u32 {
    var code = std.ArrayList(u32).empty;
    errdefer code.deinit(allocator);

    try code.appendSlice(allocator, &prologue);
    try code.appendSlice(allocator, &error_exit);

    const starts = try allocator.alloc(u32, ir.instructions.len + 1);
    defer allocator.free(starts);

    for (ir.instructions, 0..) |instruction, i| {
        starts[i] = @intCast(code.items.len);

        switch (instruction) {
            .move => |n| {
                const magnitude = @abs(n);

                if (magnitude <= 0xfff) {
                    // add x19, x19, #n, or sub x19, x19, #n moving left.
                    const base: u32 = if (n < 0) 0xd1000273 else 0x91000273;
                    try code.append(allocator, base | (magnitude << 10));
                } else {
                    // The immediate is only 12 bits wide, so anything longer has
                    // to be built up in a register first.
                    try code.append(
                        allocator,
                        0xd2800008 | ((magnitude & 0xffff) << 5), // movz x8, #n
                    );
                    if (magnitude > 0xffff) {
                        try code.append(
                            allocator,
                            0xf2a00008 | ((magnitude >> 16) << 5), // movk x8, #n, lsl #16
                        );
                    }

                    // add x19, x19, x8, or sub x19, x19, x8 moving left.
                    try code.append(allocator, if (n < 0) 0xcb080273 else 0x8b080273);
                }

                try code.append(
                    allocator,
                    0xeb15027f, // cmp x19, x21
                );

                // An unsigned compare catches both ends, a negative index reads
                // as a very large one.
                const offset: i32 = error_exit_index - @as(i32, @intCast(code.items.len));
                try code.append(
                    allocator,
                    // b.hs error_exit
                    0x54000002 | ((@as(u32, @bitCast(offset)) & 0x7ffff) << 5),
                );
            },
            .add => |n| try code.appendSlice(
                allocator,
                &.{
                    0x38736a88, // ldrb w8, [x20, x19]
                    0x11000108 | (@as(u32, n) << 10), // add w8, w8, #n
                    0x38336a88, // strb w8, [x20, x19]
                },
            ),
            .write => try code.appendSlice(
                allocator,
                &.{
                    0xf94002c9, // ldr  x9, [x22], the Runtime.write function
                    0xaa1603e0, // mov  x0, x22, the Runtime
                    0x38736a81, // ldrb w1, [x20, x19], the cell value
                    0xd63f0120, // blr  x9
                },
            ),
            .read => try code.appendSlice(
                allocator,
                &.{
                    0xf94006c9, // ldr  x9, [x22, #8], the Runtime.read function
                    0xaa1603e0, // mov  x0, x22, the Runtime
                    0xd63f0120, // blr  x9
                    0x38336a80, // strb w0, [x20, x19]
                },
            ),
            .jump_if_zero => try code.appendSlice(
                allocator,
                &.{
                    0x38736a88, // ldrb w8, [x20, x19]
                    0x34000008, // cbz  w8, patched later
                },
            ),
            .jump_if_nonzero => try code.appendSlice(
                allocator,
                &.{
                    0x38736a88, // ldrb w8, [x20, x19]
                    0x35000008, // cbnz w8, patched later
                },
            ),
        }
    }

    starts[ir.instructions.len] = @intCast(code.items.len);

    // A loop's target is only known once everything after it is emitted, so the branches
    // go out with a zero offset and get filled in here.
    for (ir.instructions, 0..) |instruction, i| {
        const target = switch (instruction) {
            .jump_if_zero, .jump_if_nonzero => |t| t,
            else => continue,
        };
        const branch = starts[i] + 1;
        const offset: i32 = @intCast(@as(i64, starts[target]) - @as(i64, branch));
        code.items[branch] |= (@as(u32, @bitCast(offset)) & 0x7ffff) << 5;
    }

    try code.appendSlice(allocator, &epilogue);

    return code.toOwnedSlice(allocator);
}
