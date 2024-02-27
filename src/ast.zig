const std = @import("std");
const Token = @import("lexer.zig").Token;

const Literal = union(Tag) {
    const Tag = enum { number };
    number: f32,
    //string: [:0]const u8,
};

const Expr = union(Tag) {
    const Self = @This();
    binary: Binary,
    grouping: Grouping,
    literal: Literal,
    unary: Unary,
    const Tag = enum { binary, grouping, literal, unary };
    const Binary = struct {
        left: *Self,
        operator: Token,
        right: *Self,
    };
    const Grouping = struct {
        expression: *Self,
    };
    const Unary = struct {
        operator: Token,
        right: *Self,
    };
};

fn ast_print(expr: *const Expr, writer: anytype) !void {
    switch (expr.*) {
        .binary => |b| {
            _ = try writer.write("(+ ");
            try ast_print(b.left, writer);
            _ = try writer.write(" ");
            try ast_print(b.right, writer);
            _ = try writer.write(")");
        },
        .grouping => |g| {
            _ = try writer.write("(group ");
            try ast_print(g.expression, writer);
            _ = try writer.write(")");
        },
        .literal => |l| {
            _ = try std.fmt.format(writer, "{d}", .{l.number});
        },
        .unary => |u| {
            _ = try writer.write("(- ");
            try ast_print(u.right, writer);
            _ = try writer.write(")");
        },
    }
}

test "asdf" {
    var lit1 = Expr{ .literal = Literal{ .number = 2.0 } };
    var lit2 = Expr{ .literal = Literal{ .number = 2.0 } };
    var add1 = Expr{ .binary = Expr.Binary{
        .left = &lit1,
        .operator = .{ .tag = .PLUS, .loc = undefined },
        .right = &lit2,
    } };
    const stdout = std.io.getStdOut().writer();
    try ast_print(&add1, stdout);
    _ = try stdout.write("\n");
}
