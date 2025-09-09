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

pub const PacketBuffer = struct {
    data: [BUFFER_SIZE]u8 = undefined,
    items: []u8 = &[_]u8{},
    pos: usize = 0,

    const Writer = std.io.Writer(*PacketBuffer, anyerror, write);
    const Reader = std.io.Reader(*PacketBuffer, anyerror, read);

    pub fn write(self: *PacketBuffer, data: []const u8) !usize {
        if (self.items.len + data.len > self.data.len) {
            return error.EndOfBuffer;
        }

        @memcpy(self.data[self.items.len..][0..data.len], data);
        self.items = self.data[0 .. self.items.len + data.len];
        return data.len;
    }

    pub fn written(self: *PacketBuffer, amount: usize) void {
        self.items = self.data[0 .. self.items.len + amount];
    }

    pub fn writer(self: *PacketBuffer) Writer {
        return .{ .context = self };
    }

    pub fn read(self: *PacketBuffer, buffer: []u8) !usize {
        const remainingBytes = self.items.len - self.pos;
        const len = @min(remainingBytes, buffer.len);

        if (len < 0) {
            return error.EndOfBuffer;
        }

        @memcpy(buffer[0..len], self.items[self.pos .. self.pos + len]);
        self.pos += len;
        return len;
    }

    pub fn reader(self: *PacketBuffer) Reader {
        return .{ .context = self };
    }

    pub fn reset(self: *PacketBuffer) void {
        self.items = &[_]u8{};
        self.pos = 0;
    }
};

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

fn writeMessage(allocator: Allocator, socket: posix.socket_t, messages: []const []const u8) !void {
    var vec = try allocator.alloc(posix.iovec_const, messages.len + 1);
    for (messages, 0..) |msg, i| {
        vec[i] = .{ .len = msg.len, .base = msg.ptr };
    }
    vec[messages.len] = .{ .len = 1, .base = &[1]u8{0} };

    try writeAllVectorized(socket, vec);
}

fn writeAllVectorized(socket: posix.socket_t, vec: []posix.iovec_const) !void {
    var i: usize = 0;
    while (true) {
        var n = try posix.writev(socket, vec[i..]);
        while (n >= vec[i].len) {
            n -= vec[i].len;
            i += 1;
            if (i >= vec.len) return;
        }
        vec[i].base += n;
        vec[i].len -= n;
    }
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

