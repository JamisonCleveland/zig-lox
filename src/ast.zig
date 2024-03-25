const std = @import("std");
const Token = @import("lexer.zig").Token;

// TODO:
// * Cleanup pratt parser.
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

pub fn ast_print(expr: *const Expr, writer: anytype) !void {
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
            switch (l) {
                .bool => |lit| try std.fmt.format(writer, "{?}", .{lit}),
                .nil => try std.fmt.format(writer, "nil", .{}),
                .number => |lit| try std.fmt.format(writer, "{d}", .{lit}),
                .string => |lit| try std.fmt.format(writer, "\"{s}\"", .{lit}),
            }
        },
        .unary => |u| {
            try writer.print("({s} ", .{u.operator.lexeme});
            try ast_print(u.right, writer);
            _ = try writer.write(")");
        },
    }
}

pub const Parser = struct {
    const Self = @This();
    tokens: []Token,
    pos: usize,
    allocator: std.mem.Allocator,

    const Error = error{
        UnexpectedToken,
        OutOfMemory,
    };

    pub fn isOperator(t: Token.Tag) bool {
        return switch (t) {
            .bang_equal,
            .equal_equal,
            .greater,
            .greater_equal,
            .less,
            .less_equal,
            .plus,
            .minus,
            .star,
            .slash,
            => true,
            else => false,
        };
    }

    pub fn infixLeftBP(t: Token.Tag) u8 {
        return switch (t) {
            .bang_equal, .equal_equal => 1,
            .greater, .greater_equal, .less, .less_equal => 3,
            .plus, .minus => 5,
            .star, .slash => 7,
            else => unreachable,
        };
    }

    pub fn prefixRightBP(t: Token.Tag) u8 {
        return switch (t) {
            .bang => 3,
            .minus => 9,
            else => unreachable,
        };
    }

    pub fn parseExpression(p: *Self) Error!*Expr {
        return try p.parsePratt(0);
    }

    fn parsePrimary(p: *Self) Error!*Expr {
        const t = p.tokens[p.pos];
        switch (t.tag) {
            .left_paren => {
                p.pos += 1;
                var e = try p.parseExpression();
                if (p.tokens[p.pos].tag != .right_paren) return error.UnexpectedToken;
                p.pos += 1;

                var res = try p.allocator.create(Expr);
                res.* = .{ .grouping = .{ .expression = e } };
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

    fn parseUnary(p: *Self) Error!*Expr {
        const t = p.tokens[p.pos];
        switch (t.tag) {
            .bang, .minus => {
                p.pos += 1;
                const r_bp: u8 = prefixRightBP(t.tag);
                var u = try p.parsePratt(r_bp);

                var res = try p.allocator.create(Expr);
                res.* = .{ .unary = .{ .operator = t, .right = u } };
                return res;
            },
            else => return try p.parsePrimary(),
        }
    }

    fn parsePratt(p: *Self, min_bp: u8) Error!*Expr {
        var lhs = try p.parseUnary();

        while (p.pos < p.tokens.len) {
            const op = p.tokens[p.pos];

            if (!isOperator(op.tag)) break;

            const l_bp: u8 = infixLeftBP(op.tag);
            const r_bp = l_bp + 1;

            if (l_bp < min_bp) break;
            p.pos += 1;

            var rhs = try p.parsePratt(r_bp);

            var res = try p.allocator.create(Expr);
            res.* = .{ .binary = .{ .left = lhs, .operator = op, .right = rhs } };
            lhs = res;
        }
        return lhs;
    }

    fn parseLoxValue(p: *Self) Error!LoxValue {
        const t = p.tokens[p.pos];
        switch (t.tag) {
            .number => {
                p.pos += 1;
                const n = std.fmt.parseFloat(f32, t.lexeme) catch unreachable;
                return LoxValue{ .number = n };
            },
            .string => {
                p.pos += 1;
                return LoxValue{ .string = t.lexeme[1 .. t.lexeme.len - 1] };
            },
            .true_, .false_ => {
                p.pos += 1;
                return LoxValue{ .bool = t.tag == .true_ };
            },
            .nil => {
                p.pos += 1;
                return LoxValue.nil;
            },
            else => return error.UnexpectedToken,
        }
    }
};

pub fn eval(e: *const Expr) LoxValue {
    switch (e.*) {
        .binary => |b| {
            const left = eval(b.left);
            const right = eval(b.right);
            switch (b.operator.tag) {
                .plus => return .{ .number = left.number + right.number },
                .minus => return .{ .number = left.number - right.number },
                .slash => return .{ .number = left.number / right.number },
                .star => return .{ .number = left.number * right.number },
                else => unreachable,
            }
        },
        .grouping => |g| {
            return eval(g.expression);
        },
        .literal => |l| {
            return l;
        },
        .unary => |u| {
            const right = eval(u.right);
            switch (u.operator.tag) {
                .minus => return .{ .number = -right.number },
                else => unreachable,
            }
            unreachable;
        },
    }
}

test "asdf" {
    var lexer = @import("lexer.zig").Lexer.init("2 / (2 * (3 * 2))");
    var toks = std.ArrayList(Token).init(std.testing.allocator);
    defer toks.deinit();
    lexer.scanAll(&toks) catch unreachable;

    var aa = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer aa.deinit();

    var p = Parser{ .tokens = toks.items, .pos = 0, .allocator = aa.allocator() };
    const a = try p.parseExpression();
    std.debug.print("\n", .{});
    try ast_print(a, std.io.getStdErr().writer());
    std.debug.print("\n", .{});
    std.debug.print("val = {d}\n", .{eval(a).number});
}
