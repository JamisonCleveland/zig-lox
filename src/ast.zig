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

    pub fn format(
        self: LoxValue,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;

        switch (self) {
            .bool => |b| try writer.print("{}", .{b}),
            .nil => try writer.print("nil", .{}),
            .number => |n| try writer.print("{d}", .{n}),
            .string => |s| try writer.print("\"{s}\"", .{s}),
        }
    }
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

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;

        switch (self) {
            .binary => |b| {
                try writer.print("({s} {} {})", .{ b.operator.lexeme, b.left, b.right });
            },
            .grouping => |g| {
                try writer.print("(group {})", .{g.expression});
            },
            .literal => |l| {
                try writer.print("{}", .{l});
            },
            .unary => |u| {
                try writer.print("({s} {})", .{ u.operator.lexeme, u.right });
            },
        }
    }
};

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
                .greater => {
                    return .{ .bool = left.number > right.number };
                },
                .greater_equal => {
                    return .{ .bool = left.number >= right.number };
                },
                .less => {
                    return .{ .bool = left.number < right.number };
                },
                .less_equal => {
                    return .{ .bool = left.number <= right.number };
                },
                .equal_equal => {
                    return .{ .bool = isEqual(left, right) };
                },
                .bang_equal => {
                    return .{ .bool = !isEqual(left, right) };
                },
                .plus => {
                    // I don't think there is an alternative ...
                    switch (left) {
                        .number => |l_num| {
                            switch (right) {
                                .number => |r_num| {
                                    return .{ .number = l_num + r_num };
                                },
                                else => unreachable,
                            }
                        },
                        .string => |l_str| {
                            _ = l_str;
                            switch (right) {
                                .string => |r_str| {
                                    _ = r_str;
                                    // return nothing for now
                                    return .{ .string = "" };
                                },
                                else => unreachable,
                            }
                        },
                        else => unreachable,
                    }
                },
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
                .bang => return .{ .bool = !isTruthy(right) },
                else => unreachable,
            }
        },
    }
}

fn isTruthy(l: LoxValue) bool {
    return switch (l) {
        .nil => false,
        .bool => |b| b,
        else => true,
    };
}

fn isEqual(a: LoxValue, b: LoxValue) bool {
    return switch (a) {
        .nil => switch (b) {
            .nil => true,
            else => false,
        },
        else => std.meta.eql(a, b),
    };
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
    std.debug.print("{}\n", .{a});
    std.debug.print("val = {d}\n", .{eval(a).number});
}
