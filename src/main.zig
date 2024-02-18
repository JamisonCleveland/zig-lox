const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const stdout = std.io.getStdOut().writer();

    if (args.len > 2) {
        try stdout.print("Usage: ziglox [script]\n", .{});
        std.process.exit(64);
    } else if (args.len == 2) {
        try runFile(args[1]);
    } else {
        try repl();
    }
}

pub fn repl() !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    try stdout.print("The Lox Interpreter REPL\n", .{});

    var buff: [128:0]u8 = undefined;
    @memset(&buff, 0);
    var buff_stream = std.io.fixedBufferStream(&buff);
    while (true) {
        buff_stream.reset();
        @memset(buff_stream.buffer, 0);

        _ = try stdout.write("> ");
        try stdin.streamUntilDelimiter(buff_stream.writer(), '\n', null);
        if (buff_stream.pos == 1) break;

        try run(&buff);
    }
}

pub fn runFile(path: [:0]const u8) !void {
    var file = try std.fs.cwd().openFileZ(path, .{});
    defer file.close();

    var src_buff: [4096:0]u8 = undefined;
    @memset(&src_buff, 0);
    _ = try file.readAll(&src_buff);

    try run(&src_buff); // thats a lot ...
}

pub fn run(src: [:0]const u8) !void {
    const stderr = std.io.getStdErr().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var lexer = Lexer.init(src);

    var toks = std.ArrayList(Token).init(allocator);
    defer toks.deinit();

    lexer.scanAll(&toks) catch |err| switch (err) {
        error.UnterminatedString => try stderr.print("ERROR: Unterminated string literal\n", .{}),
        error.UnexpectedCharacter => try stderr.print("ERROR: Unexpected character\n", .{}),
        else => return err,
    };

    for (toks.items) |t| {
        std.debug.print("'{s}' {?}\n", .{ lexer.src[t.loc.start..t.loc.end], t.tag });
    }
}
