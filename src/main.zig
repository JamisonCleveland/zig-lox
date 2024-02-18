const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;

pub fn repl() !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    try stdout.print("The Lox Interpreter REPL\n", .{});

    var buff = std.mem.zeroes([128]u8);
    var buff_stream = std.io.fixedBufferStream(&buff);
    while (true) {
        buff_stream.reset();
        @memset(buff_stream.buffer, 0);

        _ = try stdout.write("> ");
        try stdin.streamUntilDelimiter(buff_stream.writer(), '\n', null);
        if (buff_stream.pos == 1) break;

        var lexer = Lexer.init(buff_stream.getWritten());

        var toks = std.ArrayList(Token).init(alloc);
        defer toks.deinit();

        lexer.scanAll(&toks) catch |err| switch (err) {
            error.UnterminatedString => try stdout.print("ERROR: Unterminated string literal\n", .{}),
            error.UnexpectedCharacter => try stdout.print("ERROR: Unexpected character\n", .{}),
            else => return err,
        };

        for (toks.items) |t| {
            std.debug.print("'{s}' {?}\n", .{ lexer.src[t.loc.start..t.loc.end], t.tag });
        }
    }
}

pub fn main() !void {
    try repl();
}
