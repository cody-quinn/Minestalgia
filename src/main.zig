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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Making an arena allocator for packets
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const alloc = arena.allocator();

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

test {
    _ = @import("jvm/Random.zig");
}
