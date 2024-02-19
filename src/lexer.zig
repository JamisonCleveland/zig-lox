const std = @import("std");

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
        line: usize,
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
        try a.append(.{ .tag = Token.Tag.EOF, .loc = .{ .start = l.pos, .end = l.pos, .line = l.line } });
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
        };

        if (l.identifier()) {
            result.tag = Token.keywords.get(l.src[start..l.pos]) orelse Token.Tag.IDENTIFIER;
            result.loc.end = l.pos;
            result.loc.line = l.line;
            return result;
        } else if (try l.string()) {
            result.tag = Token.Tag.STRING;
            result.loc.end = l.pos;
            result.loc.line = l.line;
            return result;
        } else if (l.number()) {
            result.tag = Token.Tag.NUMBER;
            result.loc.end = l.pos;
            result.loc.line = l.line;
            return result;
        }

        const c = l.src[l.pos];
        l.pos += 1;
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
                if (l.consume('=')) {
                    result.tag = Token.Tag.BANG_EQUAL;
                } else {
                    result.tag = Token.Tag.BANG;
                }
            },
            '=' => {
                if (l.consume('=')) {
                    result.tag = Token.Tag.EQUAL_EQUAL;
                } else {
                    result.tag = Token.Tag.EQUAL;
                }
            },
            '>' => {
                if (l.consume('=')) {
                    result.tag = Token.Tag.GREATER_EQUAL;
                } else {
                    result.tag = Token.Tag.GREATER;
                }
            },
            '<' => {
                if (l.consume('=')) {
                    result.tag = Token.Tag.LESS_EQUAL;
                } else {
                    result.tag = Token.Tag.LESS;
                }
            },
            else => {
                l.pos -= 1; // kinda hacky
                return Error.UnexpectedCharacter;
            },
        }
        result.loc.end = l.pos;
        result.loc.line = l.line;
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
