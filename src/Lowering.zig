// SPDX-FileCopyrightText: 2026 Iyad
//
// SPDX-License-Identifier: Apache-2.0

//! Lowers an abstract syntax tree into an intermediate representation.

const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const Ir = @import("Ir.zig");
const Ast = @import("Ast.zig");
const Lexer = @import("Lexer.zig");
const Parser = @import("Parser.zig");

const Lowering = @This();

_allocator: Allocator,
_instructions: std.ArrayList(Ir.Instruction),

/// Lowers `ast` into an `Ir`.
///
/// The result should be freed with `Ir.deinit`.
pub fn lower(allocator: Allocator, ast: Ast) Allocator.Error!Ir {
    var lowering = Lowering{
        ._allocator = allocator,
        ._instructions = .empty,
    };
    errdefer lowering._instructions.deinit(allocator);

    try lowering.lowerNodes(ast.root);

    return .{
        .instructions = try lowering._instructions.toOwnedSlice(allocator),
    };
}

/// Lowers each node in order, recursing into loop bodies.
///
/// A loop's forward jump cannot know its target until the body has been lowered,
/// so it is emitted as a placeholder and backpatched afterwards.
fn lowerNodes(self: *Lowering, nodes: []const Ast.Node) Allocator.Error!void {
    for (nodes) |node| {
        switch (node) {
            .move_right => try self._instructions.append(
                self._allocator,
                .{ .move = 1 },
            ),
            .move_left => try self._instructions.append(
                self._allocator,
                .{ .move = -1 },
            ),
            .increment => try self._instructions.append(
                self._allocator,
                .{ .add = 1 },
            ),
            .decrement => try self._instructions.append(
                self._allocator,
                .{ .add = -1 },
            ),
            .read => try self._instructions.append(
                self._allocator,
                .read,
            ),
            .write => try self._instructions.append(
                self._allocator,
                .write,
            ),
            .loop => |body| {
                const start = self._instructions.items.len;
                try self._instructions.append(
                    self._allocator,
                    .{ .jump_if_zero = undefined },
                );
                try self.lowerNodes(body);
                try self._instructions.append(
                    self._allocator,
                    .{ .jump_if_nonzero = start + 1 },
                );
                self._instructions.items[start] = .{
                    .jump_if_zero = self._instructions.items.len,
                };
            },
        }
    }
}

fn expectIr(expected: []const Ir.Instruction, source: []const u8) !void {
    const allocator = testing.allocator;

    var lexer = Lexer.init(source);
    var ast = try Parser.parse(allocator, &lexer);
    defer ast.deinit(allocator);

    var ir = try Lowering.lower(allocator, ast);
    defer ir.deinit(allocator);

    try testing.expectEqualDeep(expected, ir.instructions);
}

test "each command lowers to its instructions" {
    try expectIr(
        &.{
            .{ .move = 1 },
            .{ .move = -1 },
            .{ .add = 1 },
            .{ .add = -1 },
            .read,
            .write,
        },
        "><+-,.",
    );
}

test "empty program lowers to no instructions" {
    try expectIr(&.{}, "");
}

test "empty loop lowers to a jump pair" {
    try expectIr(
        &.{
            .{ .jump_if_zero = 2 },
            .{ .jump_if_nonzero = 1 },
        },
        "[]",
    );
}

test "loop jumps past its body and back" {
    try expectIr(
        &.{
            .{ .add = 1 },
            .{ .jump_if_zero = 5 },
            .{ .move = 1 },
            .{ .add = 1 },
            .{ .jump_if_nonzero = 2 },
            .{ .add = -1 },
        },
        "+[>+]-",
    );
}

test "nested loops get their own jump targets" {
    try expectIr(
        &.{
            .{ .jump_if_zero = 5 },
            .{ .jump_if_zero = 4 },
            .{ .add = 1 },
            .{ .jump_if_nonzero = 2 },
            .{ .jump_if_nonzero = 1 },
        },
        "[[+]]",
    );
}
