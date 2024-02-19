const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const stdout = std.io.getStdOut().writer();

    if (args.len > 2) {
        try stdout.print("Usage: ziglox [script]\n", .{});
        std.process.exit(64);
    } else if (args.len == 2) {
        try runFile(allocator, args[1]);
    } else {
        try repl(allocator);
    }
}

pub fn repl(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    try stdout.print("The Lox Interpreter REPL\n", .{});

    while (true) {
        _ = try stdout.write("> ");

        var array_list = std.ArrayList(u8).init(allocator);
        defer array_list.deinit();
        try stdin.streamUntilDelimiter(array_list.writer(), '\n', 256);
        const buff = try array_list.toOwnedSliceSentinel(0);
        defer allocator.free(buff);

        if (buff.len == 1) break;

        try run(allocator, buff);
    }
}

pub fn runFile(allocator: std.mem.Allocator, path: [:0]const u8) !void {
    var file = try std.fs.cwd().openFileZ(path, .{});
    defer file.close();

    const src_buff = try file.readToEndAllocOptions(allocator, 4096, null, @alignOf(u8), 0);
    defer allocator.free(src_buff);

    try run(allocator, src_buff);
}

pub fn run(allocator: std.mem.Allocator, src: [:0]const u8) !void {
    const stderr = std.io.getStdErr().writer();

    var lexer = Lexer.init(src);

    var toks = std.ArrayList(Token).init(allocator);
    defer toks.deinit();

    lexer.scanAll(&toks) catch |err| switch (err) {
        error.UnterminatedString => {
            try stderr.print("[line {d}] Error: Unterminated string literal\n", .{lexer.line + 1});
        },
        error.UnexpectedCharacter => {
            try stderr.print("[line {d}] Error: Unexpected character\n", .{lexer.line + 1});
        },
        else => return err,
    };

    for (toks.items) |t| {
        std.debug.print("'{s}', line: {d}, tag: {?}\n", .{ lexer.src[t.loc.start..t.loc.end], t.loc.line, t.tag });
    }
}
