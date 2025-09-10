const std = @import("std");

const mem = std.mem;
const net = std.net;
const posix = std.posix;

const Thread = std.Thread;
const Allocator = mem.Allocator;

const StreamReader = @import("StreamReader.zig");

const Server = @import("Server.zig");
const ServerConnection = @import("ServerConnection.zig");

const proto = @import("protocol.zig");

const BUFFER_SIZE = 16_384;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Making an arena allocator for packets
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const alloc = arena.allocator();

    try hacky_create_chunk_data(alloc);

    const address = try net.Address.parseIp("127.0.0.1", 25565);

    var server = try Server.init(alloc, 1023);
    defer server.deinit();
    try server.run(address);
}

fn readMessage(socket: posix.socket_t, buf: []u8) ![]u8 {
    var pos: usize = 0;
    while (true) {
        const n = try posix.read(socket, buf[pos..]);
        if (n == 0) {
            return error.Closed;
        }
        const end = pos + n;
        const index = mem.indexOfScalar(u8, buf[pos..end], 0) orelse {
            pos = end;
            continue;
        };
        return buf[0 .. pos + index];
    }
}

// ----

var chunk_data: [81_920]u8 = undefined;
pub var chunk_data_compressed: []u8 = undefined;
fn hacky_create_chunk_data(alloc: Allocator) !void {
    @memset(&chunk_data, 0);
    @memset(chunk_data[49152..81920], 0xFF);

    for (0..16) |x| {
        for (0..10) |y| {
            for (0..16) |z| {
                const index = y + (z * 128) + (x * 128 * 16);
                chunk_data[index] = 1;
            }
        }
    }

    for (3..13, 0..) |x, i| {
        for (3..13, 0..) |z, j| {
            const index = 10 + (z * 128) + (x * 128 * 16);
            chunk_data[index] = @min(96, (@as(u8, @intCast(i)) * 10) + @as(u8, @intCast(j)) % 10);
            chunk_data[index + 1] = 68;
        }
    }

    var ingress = std.io.fixedBufferStream(&chunk_data);
    var egress = try std.ArrayList(u8).initCapacity(alloc, 16 * 128 * 16);
    try std.compress.zlib.compress(ingress.reader(), egress.writer(), .{ .level = .default });
    chunk_data_compressed = try egress.toOwnedSlice();
}

fn printBytes(bytes: []const u8) void {
    std.debug.print("Length: {}", .{bytes.len});
    for (bytes, 0..) |b, i| {
        if (i % 16 == 0) {
            std.debug.print("\n{x:0>4}: ", .{i});
        }
        std.debug.print("{x:0>2} ", .{b});
    }
    std.debug.print("(EOF) \n", .{});
}
