const std = @import("std");

const mem = std.mem;
const net = std.net;
const posix = std.posix;

const Thread = std.Thread;
const Allocator = mem.Allocator;

const StreamReader = @import("StreamReader.zig");
const Chunk = @import("world/Chunk.zig");
const Server = @import("Server.zig");
const ServerConnection = @import("ServerConnection.zig");

const proto = @import("protocol.zig");

const BUFFER_SIZE = 16_384;

pub fn main() !void {
    const args = parseArgs() catch {
        std.process.exit(0);
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Making an arena allocator for packets
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const alloc = arena.allocator();

    const address = try net.Address.parseIp("127.0.0.1", 25565);

    var server = try Server.init(alloc, 1023);
    server.world_seed = args.world_seed;
    defer server.deinit();
    try server.run(address);
}

const CliArguments = struct {
    world_seed: u64 = 0,
};

const CliParserStage = enum {
    base,
    help,
    world_seed,
};

fn parseArgs() !CliArguments {
    const flags = std.StaticStringMap(CliParserStage).initComptime(.{
        .{ "--help", .help },
        .{ "-h", .help },
        .{ "--seed", .world_seed },
        .{ "-s", .world_seed },
    });

    var iter = std.process.args();
    var args: CliArguments = .{};

    const exe_path = iter.next() orelse unreachable;

    parse: switch (CliParserStage.base) {
        .base => {
            const flag = iter.next() orelse break :parse;
            const target_stage = flags.get(flag) orelse {
                std.debug.print("Unknown flag {s}\n", .{flag});
                return error.Terminate;
            };

            continue :parse target_stage;
        },
        .help => {
            std.debug.print(
                \\Usage: {s} [options]
                \\
                \\Options:
                \\
                \\  -h, --help            Print command-line usage
                \\  -s, --seed [integer]  Set the world seed
                \\
            , .{exe_path});
            return error.Terminate;
        },
        .world_seed => {
            const str_value = iter.next() orelse break :parse;
            args.world_seed = try std.fmt.parseInt(u64, str_value, 10);
            continue :parse .base;
        },
    }

    return args;
}

test {
    _ = @import("jvm/Random.zig");
}
