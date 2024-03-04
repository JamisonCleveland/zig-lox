const std = @import("std");

pub const Token = struct {
    tag: Tag,
    loc: Loc,
    lexeme: []const u8,

    pub const Loc = struct {
        start: usize,
        end: usize,
        line: usize,
    };

    const keywords = std.ComptimeStringMap(Token.Tag, .{
        .{ "and", Token.Tag.and_ },
        .{ "class", Token.Tag.class },
        .{ "else", Token.Tag.else_ },
        .{ "false", Token.Tag.false_ },
        .{ "fun", Token.Tag.fun },
        .{ "for", Token.Tag.for_ },
        .{ "if", Token.Tag.if_ },
        .{ "nil", Token.Tag.nil },
        .{ "or", Token.Tag.or_ },
        .{ "print", Token.Tag.print },
        .{ "return", Token.Tag.return_ },
        .{ "super", Token.Tag.super },
        .{ "this", Token.Tag.this },
        .{ "true", Token.Tag.true_ },
        .{ "var", Token.Tag.var_ },
        .{ "while", Token.Tag.while_ },
    });

    pub const Tag = enum {
        // Single-character tokens.
        left_paren,
        right_paren,
        left_brace,
        right_brace,
        comma,
        dot,
        minus,
        plus,
        semicolon,
        slash,
        star,

        // One or two character tokens.
        bang,
        bang_equal,
        equal,
        equal_equal,
        greater,
        greater_equal,
        less,
        less_equal,

        // Literals.
        identifier,
        string,
        number,

        // Keywords.
        and_,
        class,
        else_,
        false_,
        fun,
        for_,
        if_,
        nil,
        or_,
        print,
        return_,
        super,
        this,
        true_,
        var_,
        while_,

        eof,
    };
};

// TODO:
// * Track line offsets for each token.
// * Better error messages for lexing.
// * have a standard format for lexing w/out the current helper functions.
pub const Lexer = struct {
    pos: usize,
    line: usize,
    src: [:0]const u8,

    const Self = @This();

    pub const Error = error{
        UnexpectedCharacter,
        UnterminatedString,
    };

    pub fn init(src: [:0]const u8) Self {
        return .{ .pos = 0, .line = 0, .src = src };
    }

    pub fn scanAll(l: *Self, a: *std.ArrayList(Token)) (Error || error{OutOfMemory})!void {
        while (try l.scan()) |t| {
            try a.append(t);
        }
        try a.append(Token{
            .tag = Token.Tag.eof,
            .loc = .{ .start = l.pos, .end = l.pos, .line = l.line },
            .lexeme = &[0]u8{}, // a little hacky. Is there a better way?
        });
    }

    pub fn scan(l: *Lexer) Error!?Token {
        while (l.whitespace() and l.lineComment()) {}

        if (l.atEnd(l.pos)) return null;

        const start = l.pos;
        var result = Token{
            .tag = undefined,
            .loc = .{
                .start = start,
                .end = undefined,
                .line = undefined,
            },
            .lexeme = undefined,
        };

        if (l.identifier()) {
            result.tag = Token.keywords.get(l.src[start..l.pos]) orelse Token.Tag.identifier;
            result.loc.end = l.pos;
            result.loc.line = l.line;
            result.lexeme = l.src[start..l.pos];
            return result;
        } else if (try l.string()) {
            result.tag = Token.Tag.string;
            result.loc.end = l.pos;
            result.loc.line = l.line;
            result.lexeme = l.src[start..l.pos];
            return result;
        } else if (l.number()) {
            result.tag = Token.Tag.number;
            result.loc.end = l.pos;
            result.loc.line = l.line;
            result.lexeme = l.src[start..l.pos];
            return result;
        }

        const c = l.src[l.pos];
        l.pos += 1;
        switch (c) {
            '(' => {
                result.tag = Token.Tag.left_paren;
            },
            ')' => {
                result.tag = Token.Tag.right_paren;
            },
            '{' => {
                result.tag = Token.Tag.left_brace;
            },
            '}' => {
                result.tag = Token.Tag.right_brace;
            },
            ',' => {
                result.tag = Token.Tag.comma;
            },
            '.' => {
                result.tag = Token.Tag.dot;
            },
            '-' => {
                result.tag = Token.Tag.minus;
            },
            '+' => {
                result.tag = Token.Tag.plus;
            },
            ';' => {
                result.tag = Token.Tag.semicolon;
            },
            '/' => {
                result.tag = Token.Tag.slash;
            },
            '*' => {
                result.tag = Token.Tag.star;
            },
            '!' => {
                if (l.consume('=')) {
                    result.tag = Token.Tag.bang_equal;
                } else {
                    result.tag = Token.Tag.bang;
                }
            },
            '=' => {
                if (l.consume('=')) {
                    result.tag = Token.Tag.equal_equal;
                } else {
                    result.tag = Token.Tag.equal;
                }
            },
            '>' => {
                if (l.consume('=')) {
                    result.tag = Token.Tag.greater_equal;
                } else {
                    result.tag = Token.Tag.greater;
                }
            },
            '<' => {
                if (l.consume('=')) {
                    result.tag = Token.Tag.less_equal;
                } else {
                    result.tag = Token.Tag.less;
                }
            },
            else => {
                l.pos -= 1; // kinda hacky
                return Error.UnexpectedCharacter;
            },
        }
        result.loc.end = l.pos;
        result.loc.line = l.line;
        result.lexeme = l.src[start..l.pos];
        return result;
    }

    // lexemes

    fn whitespace(l: *Lexer) bool {
        if (l.atEnd(l.pos) or !std.ascii.isWhitespace(l.src[l.pos])) return false;
        while (!l.atEnd(l.pos) and std.ascii.isWhitespace(l.src[l.pos])) : (l.pos += 1) {
            if (l.src[l.pos] == '\n') l.line += 1;
        }
        return true;
    }

    fn lineComment(l: *Lexer) bool {
        if (!l.consumeChunk("//")) return false;
        while (l.consumeExcept('\n')) {}
        l.line += 1;
        l.pos += 1;
        return true;
    }

    fn identifier(l: *Lexer) bool {
        if (!std.ascii.isAlphabetic(l.src[l.pos]) and l.src[l.pos] != '_') return false;
        while (!l.atEnd(l.pos) and (std.ascii.isAlphanumeric(l.src[l.pos]) or l.src[l.pos] == '_')) : (l.pos += 1) {}
        return true;
    }

    fn string(l: *Lexer) !bool {
        if (!l.consume('"')) return false;

        while (!l.atEnd(l.pos) and l.src[l.pos] != '"') : (l.pos += 1) {
            if (l.src[l.pos] == '\n') l.line += 1;
        }
        if (!l.consume('"')) return Error.UnterminatedString;

        return true;
    }

    fn number(l: *Lexer) bool {
        if (!l.consumeIf(std.ascii.isDigit)) return false;

        while (l.consumeIf(std.ascii.isDigit)) {}

        if (!l.atEnd(l.pos + 1) and l.src[l.pos] == '.' and std.ascii.isDigit(l.src[l.pos + 1])) {
            l.pos += 1;
            while (l.consumeIf(std.ascii.isDigit)) {}
        }

        return true;
    }

    // Helpers

    fn atEnd(l: *Self, i: usize) bool {
        return i >= l.src.len or l.src[i] == 0;
    }

    fn consume(l: *Lexer, comptime c: u8) bool {
        if (l.atEnd(l.pos) or l.src[l.pos] != c) return false;
        l.pos += 1;
        return true;
    }

    fn consumeChunk(l: *Self, comptime a: []const u8) bool {
        for (0..a.len) |j| {
            if (l.atEnd(j) or l.src[l.pos + j] != a[j]) {
                return false;
            }
        }
        l.pos += a.len;
        return true;
    }

    fn consumeExcept(l: *Lexer, comptime c: u8) bool {
        if (l.atEnd(l.pos) or l.src[l.pos] == c) return false;
        l.pos += 1;
        return true;
    }

    fn consumeIf(l: *Lexer, comptime f: fn (u8) bool) bool {
        if (l.atEnd(l.pos) or !f(l.src[l.pos])) return false;
        l.pos += 1;
        return true;
    }
};
