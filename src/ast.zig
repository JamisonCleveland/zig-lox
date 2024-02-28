const std = @import("std");
const Token = @import("lexer.zig").Token;

const LoxValue = union(Tag) {
    const Tag = enum { number, string, bool, nil };
    number: f32,
    string: []const u8,
    bool: bool,
    nil: struct {},
};

const Expr = union(Tag) {
    const Self = @This();
    binary: Binary,
    grouping: Grouping,
    literal: LoxValue,
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
            try writer.print("({s} ", .{b.operator.lexeme});
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
            try writer.print("({s} ", .{u.operator.lexeme});
            try ast_print(u.right, writer);
            _ = try writer.write(")");
        },
    }
}

const Parser = struct {
    const Self = @This();
    tokens: []Token,
    pos: usize,

    fn parseLoxValue(p: *Self) !LoxValue {
        const t = p.tokens[p.pos];
        switch (t.tag) {
            .NUMBER => {
                p.pos += 1;
                const n = std.fmt.parseFloat(f32, t.lexeme) catch unreachable;
                return LoxValue{ .number = n };
            },
            .STRING => {
                p.pos += 1;
                return LoxValue{ .string = t.lexeme[1 .. t.lexeme.len - 1] };
            },
            .TRUE, .FALSE => {
                p.pos += 1;
                return LoxValue{ .bool = t.tag == .TRUE };
            },
            .NIL => {
                p.pos += 1;
                return LoxValue{ .nil = .{} };
            },
            else => return error.UnexpectedToken,
        }
    }
};

test "asdf" {
    var toks = [4]Token{
        .{ .tag = Token.Tag.NUMBER, .lexeme = "123", .loc = undefined },
        .{ .tag = Token.Tag.STRING, .lexeme = "\"asdf\"", .loc = undefined },
        .{ .tag = Token.Tag.TRUE, .lexeme = "true", .loc = undefined },
        .{ .tag = Token.Tag.NIL, .lexeme = "nil", .loc = undefined },
        .{ .tag = Token.Tag.PLUS, .lexeme = "nil", .loc = undefined },
    };
    var p = Parser{ .tokens = &toks, .pos = 0 };
    const a = try p.parseLoxValue();
    const b = try p.parseLoxValue();
    const c = try p.parseLoxValue();
    const d = try p.parseLoxValue();
    const e = try p.parseLoxValue();
    std.debug.print("{d}\n", .{a.number});
    std.debug.print("'{s}'\n", .{b.string});
    std.debug.print("{?}\n", .{c});
    std.debug.print("{?}\n", .{d});
    std.debug.print("{?}\n", .{e});
}
