// SPDX-FileCopyrightText: 2026 Iyad
//
// SPDX-License-Identifier: Apache-2.0

//! Collapse runs of `add` and `move` into single instructions.

const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const Ir = @import("../Ir.zig");
const Lexer = @import("../Lexer.zig");
const Parser = @import("../Parser.zig");
const Lowering = @import("../Lowering.zig");

/// Collapse runs in `ir`, rewriting it in place.
///
/// Returns whether anything changed.
pub fn foldRuns(allocator: Allocator, ir: *Ir) Allocator.Error!bool {
    // A jump can target one past the last instruction, so instructions.len + 1.
    const remap = try allocator.alloc(usize, ir.instructions.len + 1);
    defer allocator.free(remap);

    var read: usize = 0;
    var write: usize = 0;
    const instructions = ir.instructions;

    while (read < instructions.len) {
        switch (instructions[read]) {
            .add => {
                var sum: u8 = 0;

                while (read < instructions.len and instructions[read] == .add) : (read += 1) {
                    remap[read] = write;
                    sum +%= instructions[read].add;
                }

                // A run can cancel out, e.g. `+-` sums to zero, so emit nothing.
                if (sum != 0) {
                    instructions[write] = .{ .add = sum };
                    write += 1;
                }
            },
            .move => {
                var sum: i32 = 0;

                while (read < instructions.len and instructions[read] == .move) : (read += 1) {
                    remap[read] = write;
                    sum += instructions[read].move;
                }

                // A run can cancel out, e.g. `><` results in zero movement, so emit nothing.
                if (sum != 0) {
                    instructions[write] = .{ .move = sum };
                    write += 1;
                }
            },
            else => {
                remap[read] = write;
                instructions[write] = instructions[read];
                read += 1;
                write += 1;
            },
        }
    }

    remap[instructions.len] = write;

    // Removing instructions shifted everything after them, so jump targets no
    // longer point where they did.
    for (instructions[0..write]) |*instruction| {
        switch (instruction.*) {
            .jump_if_zero => |t| instruction.* = .{ .jump_if_zero = remap[t] },
            .jump_if_nonzero => |t| instruction.* = .{ .jump_if_nonzero = remap[t] },
            else => {},
        }
    }

    const changed = write != ir.instructions.len;
    ir.instructions = try allocator.realloc(ir.instructions, write);
    return changed;
}

fn expectFolded(expected: []const Ir.Instruction, source: []const u8) !void {
    const allocator = testing.allocator;

    var lexer = Lexer.init(source);

    var ast = try Parser.parse(allocator, &lexer);
    defer ast.deinit(allocator);

    var ir = try Lowering.lower(allocator, ast);
    defer ir.deinit(allocator);

    _ = try foldRuns(allocator, &ir);

    try testing.expectEqualDeep(expected, ir.instructions);
}

fn expectFoldedIr(expected: []const Ir.Instruction, input: []const Ir.Instruction) !void {
    const allocator = testing.allocator;

    var ir = Ir{
        .instructions = try allocator.dupe(Ir.Instruction, input),
    };
    defer ir.deinit(allocator);

    _ = try foldRuns(allocator, &ir);

    try testing.expectEqualDeep(expected, ir.instructions);
}

fn expectChanged(expected: bool, source: []const u8) !void {
    const allocator = testing.allocator;

    var lexer = Lexer.init(source);

    var ast = try Parser.parse(allocator, &lexer);
    defer ast.deinit(allocator);

    var ir = try Lowering.lower(allocator, ast);
    defer ir.deinit(allocator);

    try testing.expectEqual(
        expected,
        try foldRuns(allocator, &ir),
    );
}

test "a run of adds collapses into one" {
    try expectFolded(
        &.{
            .{ .add = 3 },
        },
        "+++",
    );
}

test "a run of moves collapses into one" {
    try expectFolded(
        &.{
            .{ .move = 3 },
        },
        ">>>",
    );
}

test "a run of adds that cancels is removed" {
    try expectFolded(&.{}, "+-");
}

test "a run of moves that cancels is removed" {
    try expectFolded(&.{}, "><");
}

test "jump targets follow the shift" {
    try expectFolded(
        &.{
            .{ .add = 3 },
            .{ .jump_if_zero = 5 },
            .{ .move = 1 },
            .{ .add = 1 },
            .{ .jump_if_nonzero = 2 },
        },
        "+++[>+]",
    );
}

test "a run of adds wraps past 255" {
    try expectFoldedIr(
        &.{
            .{ .add = 44 },
        },
        &.{
            .{ .add = 200 },
            .{ .add = 100 },
        },
    );
}

test "a run of adds that wraps to zero is removed" {
    try expectFoldedIr(
        &.{},
        &.{
            .{ .add = 200 },
            .{ .add = 56 },
        },
    );
}

test "folding reports a change" {
    try expectChanged(true, "+++");
}

test "nothing to fold reports no change" {
    try expectChanged(false, "[+]");
}
