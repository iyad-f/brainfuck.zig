// SPDX-FileCopyrightText: 2026 Iyad
//
// SPDX-License-Identifier: Apache-2.0

//! A page of executable memory holding compiled machine code.
//!
//! Apple Silicon enforces W^X, a page is never writable and executable at the same time,
//! so the code is written with write protection off and run with it on.

const builtin = @import("builtin");
const std = @import("std");
const heap = std.heap;
const mem = std.mem;
const posix = std.posix;
const testing = std.testing;

comptime {
    if (!builtin.os.tag.isDarwin()) @compileError("JitBuffer is Darwin only as of now");
}

const JitBuffer = @This();

_memory: []align(heap.page_size_min) u8,

/// Maps a page, copies `code` into it and makes it executable.
///
/// `code` is aarch64 machine code, one instruction per `u32`.
pub fn init(code: []const u32) posix.MMapError!JitBuffer {
    const code_bytes = mem.sliceAsBytes(code);

    const memory = try posix.mmap(
        null,
        code_bytes.len,
        .{
            .READ = true,
            .WRITE = true,
            .EXEC = true,
        },
        .{
            .TYPE = .PRIVATE,
            .ANONYMOUS = true,
            .JIT = true,
        },
        -1,
        0,
    );

    // 0 disables write protection, 1 re-enables it. Writing to MAP_JIT page without
    // this faults.
    pthread_jit_write_protect_np(0);
    @memcpy(memory[0..code_bytes.len], code_bytes);
    pthread_jit_write_protect_np(1);

    // ARM's instruction and data caches are not coherent, so the CPU may still hold
    // stale instructions for these addresses.
    sys_icache_invalidate(memory.ptr, code_bytes.len);

    return .{ ._memory = memory };
}

/// Unmaps the page and invalidates this buffer.
pub fn deinit(self: *JitBuffer) void {
    posix.munmap(self._memory);
    self.* = undefined;
}

/// Runs the code with `tape` as its argument and returns the status it left behind.
///
/// The code must follow the C calling convention, which puts `tape` in `x0` and
/// the status in `w0`. The status is returned raw, the caller gives it meaning.
pub fn call(self: JitBuffer, tape: []u8, context: *anyopaque) u32 {
    const f: *const fn ([*]u8, usize, *anyopaque) callconv(.c) u32 = @ptrCast(self._memory.ptr);
    return f(tape.ptr, tape.len, context);
}

extern "c" fn pthread_jit_write_protect_np(enabled: c_int) void;
extern "c" fn sys_icache_invalidate(start: *anyopaque, len: usize) void;

test "runs jitted code against the tape" {
    var buffer = try JitBuffer.init(&.{
        0x52800861, // mov w1, #67
        0x39000001, // strb w1, [x0]
        0x52800000, // mov w0, #0
        0xd65f03c0, // ret
    });
    defer buffer.deinit();

    var tape: [30000]u8 = @splat(0);
    const status = buffer.call(&tape, undefined);

    try testing.expectEqual(0, status);
    try testing.expectEqual(67, tape[0]);
}
