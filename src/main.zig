const std = @import("std");

const net = std.net;
const posix = std.posix;

const Thread = std.Thread;
const Allocator = std.mem.Allocator;

const proto = @import("protocol.zig");

const BUFFER_SIZE = 16_384;

var chunk_data: [81_920]u8 = undefined;
var chunk_data_compressed: []u8 = undefined;

const PacketBuffer = struct {
    data: [BUFFER_SIZE]u8 = undefined,
    items: []u8 = &[_]u8{},
    pos: usize = 0,

    const Writer = std.io.Writer(*PacketBuffer, anyerror, write);
    const Reader = std.io.Reader(*PacketBuffer, anyerror, read);

    fn write(self: *PacketBuffer, data: []const u8) !usize {
        if (self.items.len + data.len > self.data.len) {
            return error.EndOfBuffer;
        }

        @memcpy(self.data[self.items.len..][0..data.len], data);
        self.items = self.data[0 .. self.items.len + data.len];
        return data.len;
    }

    fn written(self: *PacketBuffer, amount: usize) void {
        self.items = self.data[0 .. self.items.len + amount];
    }

    fn writer(self: *PacketBuffer) Writer {
        return .{ .context = self };
    }

    fn read(self: *PacketBuffer, buffer: []u8) !usize {
        const remainingBytes = self.items.len - self.pos;
        const len = @min(remainingBytes, buffer.len);

        if (len < 0) {
            return error.EndOfBuffer;
        }

        @memcpy(buffer[0..len], self.items[self.pos .. self.pos + len]);
        self.pos += len;
        return len;
    }

    fn reader(self: *PacketBuffer) Reader {
        return .{ .context = self };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Making an arena allocator for packets
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const alloc = arena.allocator();

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
    defer egress.deinit();
    try std.compress.zlib.compress(ingress.reader(), egress.writer(), .{ .level = .default });
    chunk_data_compressed = egress.items;

    const address = try net.Address.parseIp("127.0.0.1", 25565);

    var server = try Server.init(alloc, 1023);
    defer server.deinit();
    try server.run(address);
}

const Server = struct {
    allocator: Allocator,

    polls: []posix.pollfd,

    connected: usize,
    clients: []Client,
    client_polls: []posix.pollfd,

    fn init(allocator: Allocator, max_clients: usize) !Server {
        const polls = try allocator.alloc(posix.pollfd, max_clients + 1);
        errdefer allocator.free(polls);

        const clients = try allocator.alloc(Client, max_clients);
        errdefer allocator.free(clients);

        return Server{
            .allocator = allocator,
            .polls = polls,
            .connected = 0,
            .clients = clients,
            .client_polls = polls[1..],
        };
    }

    fn run(self: *Server, address: net.Address) !void {
        const tpe: u32 = posix.SOCK.STREAM | posix.SOCK.NONBLOCK;
        const protocol = posix.IPPROTO.TCP;
        const listener = try posix.socket(address.any.family, tpe, protocol);
        defer posix.close(listener);

        try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try posix.bind(listener, &address.any, address.getOsSockLen());
        try posix.listen(listener, 128);

        self.polls[0] = posix.pollfd{
            .fd = listener,
            .revents = 0,
            .events = posix.POLL.IN,
        };

        while (true) {
            std.debug.print("Looped\n", .{});

            _ = try posix.poll(self.polls[0 .. self.connected + 1], -1);

            // Accept new clients
            if (self.polls[0].revents != 0) {
                self.acceptClients(listener) catch |err| {
                    std.debug.print("Error accepting client:\n{}\n", .{err});
                };
            }

            // Handle new messages from clients
            var i: usize = 0;
            while (i < self.connected) {
                const revents = self.client_polls[i].revents;
                if (revents == 0) {
                    i += 1;
                    continue;
                }

                const client = &self.clients[i];
                if (revents & posix.POLL.IN == posix.POLL.IN) {
                    // Read message
                    var buffer = PacketBuffer{};
                    while (true) {
                        const length = posix.read(client.socket, &buffer.data) catch |err| {
                            if (err == error.WouldBlock) {
                                i += 1;
                                break;
                            }

                            std.debug.print("Error reading from client:\n{}\n", .{err});
                            break;
                        };

                        buffer.written(length);

                        if (length == 0) {
                            self.removeClient(i);
                            break;
                        }

                        printBytes(buffer.data[0..length]);
                    }

                    const packet = proto.readPacket(buffer.reader().any(), self.allocator) catch |err| {
                        if (err == error.InvalidPacket) {
                            std.debug.print("Got unknown packet\n", .{});
                            _ = try posix.write(client.socket, &.{0x00});
                        }
                        continue;
                    };

                    std.debug.print("{}\n", .{packet});

                    if (packet == .keep_alive) {
                        _ = try posix.write(client.socket, &.{0x00});
                    }

                    if (packet == .handshake) {
                        _ = try posix.write(client.socket, &.{ 0x02, 0x00, 0x01, 0x00, '-' });
                    }

                    if (packet == .login) {
                        _ = try posix.write(client.socket, &.{
                            0x01,
                            0x00, 0x00, 0x00, 0x0F, // id
                            0x00, 0x00,//
                            0x00,          //
                            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // seed
                            0x00, // level
                        });

                        // Spawn position
                        _ = try posix.write(client.socket, &.{
                            0x06,
                            0x00, 0x00, 0x00, 120, // x
                            0x00, 0x00, 0x00, 64, // y
                            0x00, 0x00, 0x00, 120, // z
                        });

                        // Time update
                        _ = try posix.write(client.socket, &.{
                            0x04,
                            0x00,
                            0x00,
                            0x00,
                            0x00,
                            0x00,
                            0x00,
                            0x18,
                            0x00,
                        });

                        // Update health
                        _ = try posix.write(client.socket, &.{
                            0x08,
                            0x00,
                            0x10,
                        });

                        // Window items
                        _ = try posix.write(client.socket, &.{
                            0x68,
                            0x00, // inv id
                            0x00, 44, // item count
                            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 1
                            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 2
                            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 3
                            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 4
                            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 5
                            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 6
                            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 7
                            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 8
                            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 9
                            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 10
                            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // 11
                        });

                        for (0..15) |x| {
                            for (0..15) |y| {
                                _ = try posix.write(client.socket, &.{
                                    0x32,
                                    0x00, 0x00, 0x00, @as(u8, @intCast(x)), // x
                                    0x00, 0x00, 0x00, @as(u8, @intCast(y)), // y
                                    0x01,
                                });
                            }
                        }

                        for (0..15) |x| {
                            for (0..15) |y| {
                                const a = try posix.write(client.socket, &.{
                                    0x33,
                                    0x00, 0x00, 0x00, @as(u8, @intCast(x)) * 16, // x
                                    0x00, 0x00, // y
                                    0x00, 0x00, 0x00, @as(u8, @intCast(y)) * 16, // z
                                    15, 127, 15, // size
                                    @truncate(chunk_data_compressed.len >> 24),
                                    @truncate(chunk_data_compressed.len >> 16),
                                    @truncate(chunk_data_compressed.len >> 8),
                                    @truncate(chunk_data_compressed.len),
                                });
                                const b = try posix.write(client.socket, chunk_data_compressed);
                                std.debug.print("{} - {} - {}\n", .{chunk_data_compressed.len, a, b});
                            }
                        }

                        _ = try posix.write(client.socket, &.{
                            0x0D,
                            0x40, 0x60, 0xE0, 0x00, 0x00, 0x00, 0x00, 0x00, // x
                                0x40, 0x52, 0x53, 0x33, 0x33, 0x33, 0x33, 0x33, // stance
                                0x40, 0x52, 0x53, 0x33, 0x33, 0x33, 0x33, 0x33, // y
                                0x40, 0x60, 0xE0, 0x00, 0x00, 0x00, 0x00, 0x00, // z
                                0x00, 0x00, 0x00, 0x00, // yaw
                                0x00, 0x00, 0x00, 0x00, // pitch
                                0x00,
                        });

                        const msg = "Hello from Zig!";
                        _ = try posix.write(client.socket, &.{
                            0x03, 0x00, msg.len
                        });
                        for (msg) |c| {
                            _ = try posix.write(client.socket, &.{
                                0x00, c
                            });
                        }
                    }
                }
            }

            // Handle broadcasting messages to clients
        }
    }

    fn acceptClients(self: *Server, listener: posix.socket_t) !void {
        while (true) {
            self.acceptClient(listener) catch |err| switch (err) {
                error.WouldBlock => return,
                else => return err,
            };
        }
    }

    fn acceptClient(self: *Server, listener: posix.socket_t) !void {
        var address: net.Address = undefined;
        var address_len: posix.socklen_t = @sizeOf(net.Address);

        const socket = try posix.accept(listener, &address.any, &address_len, posix.SOCK.NONBLOCK);
        const client = try Client.init(self.allocator, socket, address);

        self.clients[self.connected] = client;
        self.client_polls[self.connected] = posix.pollfd{
            .fd = socket,
            .revents = 0,
            .events = posix.POLL.IN,
        };

        self.connected += 1;

        std.debug.print("Client {} connected\n", .{address});
    }

    fn removeClient(self: *Server, index: usize) void {
        var client = self.clients[index];
        posix.close(client.socket);
        client.deinit();

        const last_index = self.connected - 1;
        self.clients[index] = self.clients[last_index];
        self.client_polls[index] = self.client_polls[last_index];

        self.connected = last_index;
    }

    fn deinit(self: *Server) void {
        self.allocator.free(self.polls);
        self.allocator.free(self.clients);
    }
};

const Client = struct {
    allocator: Allocator,

    socket: posix.socket_t,
    address: net.Address,

    read_buffer: []u8,

    fn init(allocator: Allocator, socket: posix.socket_t, address: net.Address) !Client {
        const read_buffer = try allocator.alloc(u8, BUFFER_SIZE);
        errdefer allocator.free(read_buffer);

        return Client{
            .allocator = allocator,
            .socket = socket,
            .address = address,
            .read_buffer = read_buffer,
        };
    }

    fn readMessage(self: *Client) !proto.ClientboundPacket {
        _ = self;
    }

    fn writeMessage(self: *Client, packet: proto.ServerboundPacket) !void {
        _ = self;
        _ = packet;
    }

    fn deinit(self: *Client) void {
        self.allocator.free(self.read_buffer);
    }
};

// pub const Reader = struct {
//     buf: []u8,

//     pos: usize = 0,
//     start: usize = 0,

//     socket: posix.socket_t,

//     pub fn readByte() !void {
//         //
//     }
// };

fn readMessage(socket: posix.socket_t, buf: []u8) ![]u8 {
    var pos: usize = 0;
    while (true) {
        const n = try posix.read(socket, buf[pos..]);
        if (n == 0) {
            return error.Closed;
        }
        const end = pos + n;
        const index = std.mem.indexOfScalar(u8, buf[pos..end], 0) orelse {
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
