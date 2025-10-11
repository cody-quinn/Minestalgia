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

    const address = net.Address.initIp4(args.host, args.port);

    var server = try Server.init(gpa.allocator(), 1023, args.world_seed, args.world_size);
    defer server.deinit();
    try server.run(address);
}

const CliArguments = struct {
    host: [4]u8 = [_]u8{ 127, 0, 0, 1 },
    port: u16 = 25565,
    world_seed: u64 = 0,
    world_size: u64 = 8,
};

const CliParserStage = enum {
    base,
    help,
    bind,
    port,
    world_seed,
    world_size,
};

fn parseArgs() !CliArguments {
    const flags = std.StaticStringMap(CliParserStage).initComptime(.{
        .{ "--help", .help },
        .{ "-h", .help },
        .{ "--bind", .bind },
        .{ "-b", .bind },
        .{ "--port", .port },
        .{ "-p", .port },
        .{ "--seed", .world_seed },
        .{ "-s", .world_seed },
        .{ "--size", .world_size },
        .{ "-S", .world_size },
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
                \\  -b, --bind [address]  Bind the server to a IP       (default: 127.0.0.1)
                \\  -p, --port [integer]  Bind the server to a port     (default: 25565)
                \\
                \\World Options:
                \\
                \\  -s, --seed [integer]  Set the world seed            (default: 0)
                \\  -S, --size [integer]  Set the world size in chunks
                \\
            , .{exe_path});
            return error.Terminate;
        },
        .bind => {
            const address = iter.next() orelse break :parse;
            var address_iter = std.mem.splitScalar(u8, address, '.');
            for (0..4) |i| {
                const address_part = address_iter.next() orelse {
                    std.debug.print("IP address must contain 4 parts\n", .{});
                    return error.Terminate;
                };

                args.host[i] = std.fmt.parseInt(u8, address_part, 10) catch {
                    std.debug.print("IP address must be a valid IPv4 address\n", .{});
                    return error.Terminate;
                };
            }

            if (address_iter.next() != null) {
                std.debug.print("IP address must contain exactly 4 parts\n", .{});
                return error.Terminate;
            }

            continue :parse .base;
        },
        .port => {
            const str_value = iter.next() orelse break :parse;
            args.port = std.fmt.parseInt(u16, str_value, 10) catch {
                std.debug.print("Port must be a valid number between 0 and 65535\n", .{});
                return error.Terminate;
            };
            continue :parse .base;
        },
        .world_seed => {
            const str_value = iter.next() orelse break :parse;
            args.world_seed = try std.fmt.parseInt(u64, str_value, 10);
            continue :parse .base;
        },
        .world_size => {
            const str_value = iter.next() orelse break :parse;
            args.world_size = try std.fmt.parseInt(u64, str_value, 10);
            continue :parse .base;
        },
    }

    return args;
}

test {
    _ = @import("jvm/Random.zig");
}
