const std = @import("std");

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    const keywords = std.ComptimeStringMap(Token.Tag, .{
        .{ "and", Token.Tag.AND },
        .{ "class", Token.Tag.CLASS },
        .{ "else", Token.Tag.ELSE },
        .{ "false", Token.Tag.FALSE },
        .{ "fun", Token.Tag.FUN },
        .{ "for", Token.Tag.FOR },
        .{ "if", Token.Tag.IF },
        .{ "nil", Token.Tag.NIL },
        .{ "or", Token.Tag.OR },
        .{ "print", Token.Tag.PRINT },
        .{ "return", Token.Tag.RETURN },
        .{ "super", Token.Tag.SUPER },
        .{ "this", Token.Tag.THIS },
        .{ "true", Token.Tag.TRUE },
        .{ "var", Token.Tag.VAR },
        .{ "while", Token.Tag.WHILE },
    });

    pub const Tag = enum {
        // Single-character tokens.
        LEFT_PAREN,
        RIGHT_PAREN,
        LEFT_BRACE,
        RIGHT_BRACE,
        COMMA,
        DOT,
        MINUS,
        PLUS,
        SEMICOLON,
        SLASH,
        STAR,

        // One or two character tokens.
        BANG,
        BANG_EQUAL,
        EQUAL,
        EQUAL_EQUAL,
        GREATER,
        GREATER_EQUAL,
        LESS,
        LESS_EQUAL,

        // Literals.
        IDENTIFIER,
        STRING,
        NUMBER,

        // Keywords.
        AND,
        CLASS,
        ELSE,
        FALSE,
        FUN,
        FOR,
        IF,
        NIL,
        OR,
        PRINT,
        RETURN,
        SUPER,
        THIS,
        TRUE,
        VAR,
        WHILE,

        EOF,
    };
};

pub const Lexer = struct {
    i: usize,
    src: []const u8,

    const Self = @This();

    pub const Error = error{
        UnexpectedCharacter,
        UnterminatedString,
    };

    pub fn init(src: []const u8) Self {
        return .{ .i = 0, .src = src };
    }

    pub fn scanAll(l: *Self, a: *std.ArrayList(Token)) (Error || error{OutOfMemory})!void {
        while (try l.scan()) |t| {
            try a.append(t);
        }
        try a.append(.{ .tag = Token.Tag.EOF, .loc = .{ .start = l.i, .end = l.i } });
    }

    fn chunk(l: *Self, comptime a: []const u8) bool {
        for (0..a.len) |j| {
            if ((l.i + j) >= l.src.len or l.src[l.i + j] != a[j]) {
                return false;
            }
        }
        l.i += a.len;
        return true;
    }

    pub fn scan(l: *Lexer) Error!?Token {
        while (l.i < l.src.len) {
            if (std.ascii.isWhitespace(l.src[l.i])) {
                while (l.i < l.src.len and std.ascii.isWhitespace(l.src[l.i])) : (l.i += 1) {}
            } else if (l.chunk("//")) {
                while (l.i < l.src.len and l.src[l.i] != '\n') : (l.i += 1) {}
            } else {
                break;
            }
        }

        if (l.i >= l.src.len) {
            return null;
        }

        const start = l.i;
        const c = l.src[l.i];
        var result = Token{
            .tag = Token.Tag.EOF,
            .loc = .{
                .start = start,
                .end = undefined,
            },
        };

        if (std.ascii.isAlphabetic(c) or c == '_') {
            while (l.i < l.src.len and (std.ascii.isAlphanumeric(l.src[l.i]) or l.src[l.i] == '_')) : (l.i += 1) {}
            result.tag = Token.keywords.get(l.src[start..l.i]) orelse Token.Tag.IDENTIFIER;
            result.loc.end = l.i;
            return result;
        } else if (c == '"') {
            l.i += 1;
            while (l.i < l.src.len and l.src[l.i] != '"') : (l.i += 1) {}
            if (l.i >= l.src.len or l.src[l.i] != '"') {
                return Error.UnterminatedString;
            }
            l.i += 1;
            result.tag = Token.Tag.STRING;
            result.loc.end = l.i;
            return result;
        } else if (std.ascii.isDigit(c)) {
            while (l.i < l.src.len and std.ascii.isDigit(l.src[l.i])) : (l.i += 1) {}

            if (l.i + 1 < l.src.len and l.src[l.i] == '.' and std.ascii.isDigit(l.src[l.i + 1])) {
                l.i += 1;

                while (l.i < l.src.len and std.ascii.isDigit(l.src[l.i])) : (l.i += 1) {}
            }

            result.tag = Token.Tag.NUMBER;
            result.loc.end = l.i;
            return result;
        }

        l.i += 1;
        switch (c) {
            '(' => {
                result.tag = Token.Tag.LEFT_PAREN;
            },
            ')' => {
                result.tag = Token.Tag.RIGHT_PAREN;
            },
            '{' => {
                result.tag = Token.Tag.LEFT_BRACE;
            },
            '}' => {
                result.tag = Token.Tag.RIGHT_BRACE;
            },
            ',' => {
                result.tag = Token.Tag.COMMA;
            },
            '.' => {
                result.tag = Token.Tag.DOT;
            },
            '-' => {
                result.tag = Token.Tag.MINUS;
            },
            '+' => {
                result.tag = Token.Tag.PLUS;
            },
            ';' => {
                result.tag = Token.Tag.SEMICOLON;
            },
            '/' => {
                result.tag = Token.Tag.SLASH;
            },
            '*' => {
                result.tag = Token.Tag.STAR;
            },
            '!' => {
                if (l.src[l.i] == '=') {
                    l.i += 1;
                    result.tag = Token.Tag.BANG_EQUAL;
                } else {
                    result.tag = Token.Tag.BANG;
                }
            },
            '=' => {
                if (l.src[l.i] == '=') {
                    l.i += 1;
                    result.tag = Token.Tag.EQUAL_EQUAL;
                } else {
                    result.tag = Token.Tag.EQUAL;
                }
            },
            '>' => {
                if (l.src[l.i] == '=') {
                    l.i += 1;
                    result.tag = Token.Tag.GREATER_EQUAL;
                } else {
                    result.tag = Token.Tag.GREATER;
                }
            },
            '<' => {
                if (l.src[l.i] == '=') {
                    l.i += 1;
                    result.tag = Token.Tag.LESS_EQUAL;
                } else {
                    result.tag = Token.Tag.LESS;
                }
            },
            else => {
                return Error.UnexpectedCharacter;
            },
        }
        result.loc.end = l.i;
        return result;
    }
};
