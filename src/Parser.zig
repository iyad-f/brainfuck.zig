// SPDX-FileCopyrightText: 2026 Iyad
//
// SPDX-License-Identifier: Apache-2.0

//! A parser producing an abstract syntax tree from tokens.
//!
//! Grammar:
//!
//! program = item*
//! item    = simple | loop
//! simple  = '>' | '<' | '+' | '-' | ',' | '.'
//! loop    = '[' item* ']'

const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const Lexer = @import("Lexer.zig");
const Ast = @import("Ast.zig");

const Parser = @This();

_lexer: *Lexer,
_allocator: Allocator,

/// A syntax error in the source.
pub const SyntaxError = error{
    /// A `[` was never closed.
    MissingRightBracket,

    /// A `]` appeared with no `[` to match.
    UnexpectedRightBracket,
};

/// An error raised while parsing.
pub const Error = SyntaxError || Allocator.Error;

/// Parses the token stream produced by `lexer` into an `Ast`.
///
/// The result should be freed with `Ast.deinit`.
pub fn parse(allocator: Allocator, lexer: *Lexer) Error!Ast {
    var parser = Parser{
        ._lexer = lexer,
        ._allocator = allocator,
    };

    const root = try parser.parseItems(false);

    return .{ .root = root };
}

/// Parses items until the sequence ends, recursing on `[`.
///
/// `in_loop` decides which token ends the sequence, at the top level the source
/// must end, inside a loop a `]` must close it.
fn parseItems(self: *Parser, in_loop: bool) Error![]const Ast.Node {
    var nodes = std.ArrayList(Ast.Node).empty;
    errdefer {
        for (nodes.items) |node| node.deinit(self._allocator);
        nodes.deinit(self._allocator);
    }

    while (true) {
        const token = self._lexer.next();

        switch (token.kind) {
            .angle_bracket_right => try nodes.append(self._allocator, .move_right),
            .angle_bracket_left => try nodes.append(self._allocator, .move_left),
            .plus => try nodes.append(self._allocator, .increment),
            .minus => try nodes.append(self._allocator, .decrement),
            .comma => try nodes.append(self._allocator, .read),
            .dot => try nodes.append(self._allocator, .write),
            .l_bracket => try nodes.append(
                self._allocator,
                .{ .loop = try self.parseItems(true) },
            ),
            .r_bracket => {
                if (!in_loop) return error.UnexpectedRightBracket;
                return nodes.toOwnedSlice(self._allocator);
            },
            .eof => {
                if (in_loop) return error.MissingRightBracket;
                return nodes.toOwnedSlice(self._allocator);
            },
        }
    }
}

fn expectTree(expected: []const Ast.Node, source: []const u8) !void {
    const allocator = testing.allocator;

    var lexer = Lexer.init(source);
    var ast = try Parser.parse(allocator, &lexer);
    defer ast.deinit(allocator);

    try testing.expectEqualDeep(expected, ast.root);
}

test "empty source parses to no nodes" {
    try expectTree(&.{}, "");
}

test "repeated commands parse in order" {
    try expectTree(
        &.{ .increment, .increment, .increment },
        "+++",
    );
}

test "each command parses to its node" {
    try expectTree(
        &.{ .move_right, .move_left, .increment, .decrement, .read, .write },
        "><+-,.",
    );
}

test "empty loop parses with an empty body" {
    try expectTree(
        &.{
            .{ .loop = &.{} },
        },
        "[]",
    );
}

test "loop contains its body" {
    try expectTree(
        &.{
            .{ .loop = &.{ .move_right, .increment } },
        },
        "[>+]",
    );
}

test "loop parses alongside sibling commands" {
    try expectTree(
        &.{
            .increment,
            .{ .loop = &.{ .move_right, .increment } },
            .decrement,
        },
        "+[>+]-",
    );
}

test "nested loops nest in the tree" {
    try expectTree(
        &.{
            .{
                .loop = &.{
                    .move_right,
                    .{ .loop = &.{.decrement} },
                    .move_left,
                },
            },
        },
        "[>[-]<]",
    );
}

test "unclosed loop is an error" {
    const allocator = testing.allocator;

    var lexer = Lexer.init("+++[");
    try testing.expectError(
        error.MissingRightBracket,
        Parser.parse(allocator, &lexer),
    );

    lexer = Lexer.init("[[+]");
    try testing.expectError(
        error.MissingRightBracket,
        Parser.parse(allocator, &lexer),
    );
}

test "unopened loop is an error" {
    const allocator = testing.allocator;

    var lexer = Lexer.init("+]");
    try testing.expectError(
        error.UnexpectedRightBracket,
        Parser.parse(allocator, &lexer),
    );

    lexer = Lexer.init("[+]]");
    try testing.expectError(
        error.UnexpectedRightBracket,
        Parser.parse(allocator, &lexer),
    );
}
