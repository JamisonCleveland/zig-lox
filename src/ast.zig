const std = @import("std");
const Token = @import("lexer.zig").Token;

// TODO:
// * Pratt parsing for the whole expression language.
// * Cleaner interface to heap allocate expressions.

const LoxValue = union(Tag) {
    const Tag = enum { number, string, bool, nil };
    number: f32,
    string: []const u8,
    bool: bool,
    nil,
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
    allocator: std.mem.Allocator,

    fn parseUnary(p: *Self) !*Expr {
        const t = p.tokens[p.pos];
        switch (t.tag) {
            .BANG, .MINUS => {
                p.pos += 1;
                var u = try p.parseUnary();

                var res = try p.allocator.create(Expr);
                res.* = .{ .unary = .{ .operator = t, .right = u } };
                return res;
            },
            else => {
                const v = try p.parseLoxValue();

                var res = try p.allocator.create(Expr);
                res.* = .{ .literal = v };
                return res;
            },
        }
    }

    fn parseFactor(p: *Self) !*Expr {
        var lhs = try p.parseUnary();

        while (p.pos < p.tokens.len) {
            const t = p.tokens[p.pos];
            switch (t.tag) {
                .SLASH, .STAR => {
                    p.pos += 1;
                    var rhs = try p.parseUnary();

                    var res = try p.allocator.create(Expr);
                    res.* = .{ .binary = .{ .left = lhs, .operator = t, .right = rhs } };
                    lhs = res;
                },
                else => break,
            }
        }
        return lhs;
    }

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
                return LoxValue.nil;
            },
            else => return error.UnexpectedToken,
        }
    }
};

test "asdf" {
    var lexer = @import("lexer.zig").Lexer.init("true * 0");
    var toks = std.ArrayList(Token).init(std.testing.allocator);
    defer toks.deinit();
    lexer.scanAll(&toks) catch unreachable;

    var aa = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer aa.deinit();

    var p = Parser{ .tokens = toks.items, .pos = 0, .allocator = aa.allocator() };
    const a = try p.parseFactor();

    std.debug.print("\n{?} {s} {?}\n", .{
        a.binary.left.literal.bool,
        a.binary.operator.lexeme,
        a.binary.right.literal.number,
    });
}
