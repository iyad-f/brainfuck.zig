// SPDX-FileCopyrightText: 2026 Iyad
//
// SPDX-License-Identifier: Apache-2.0

//! An abstract syntax tree representing a brainfuck program.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Ast = @This();

/// The syntactic constructs of the program, in order.
root: []const Node,

/// A syntactic construct of a brainfuck program.
pub const Node = union(enum) {
    /// Moves the pointer one cell right.
    move_right,

    /// Moves the pointer one cell left.
    move_left,

    /// Increments the cell under the pointer.
    increment,

    /// Decrements the cell under the pointer.
    decrement,

    /// Reads a byte into the cell under the pointer.
    read,

    /// Writes out the cell under the pointer.
    write,

    /// Runs the body while the cell under the pointer is non-zero. Owns the slice.
    loop: []const Node,

    /// Frees the memory owned by this node and everything underneath it.
    ///
    /// Only `loop` owns memory, this is a no-op for every other node.
    pub fn deinit(self: Node, allocator: Allocator) void {
        switch (self) {
            .loop => |body| {
                for (body) |child| child.deinit(allocator);
                allocator.free(body);
            },
            else => {},
        }
    }
};

/// Frees all allocated memory and invalidates this tree.
pub fn deinit(self: *Ast, allocator: Allocator) void {
    for (self.root) |node| node.deinit(allocator);
    allocator.free(self.root);
    self.* = undefined;
}
