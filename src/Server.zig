const Self = @This();

const std = @import("std");
const proto = @import("protocol.zig");

const mem = std.mem;
const net = std.net;
const posix = std.posix;

const Allocator = mem.Allocator;

const StreamReader = @import("StreamReader.zig");
const ServerConnection = @import("ServerConnection.zig");

allocator: Allocator,

polls: []posix.pollfd,

connected: usize,
connections: []ServerConnection,
connection_polls: []posix.pollfd,

pub fn init(allocator: Allocator, max_clients: usize) !Self {
    const polls = try allocator.alloc(posix.pollfd, max_clients + 1);
    errdefer allocator.free(polls);

    const connections = try allocator.alloc(ServerConnection, max_clients);
    errdefer allocator.free(connections);

    return Self{
        .allocator = allocator,
        .polls = polls,
        .connected = 0,
        .connections = connections,
        .connection_polls = polls[1..],
    };
}

pub fn run(self: *Self, address: net.Address) !void {
    const tpe: u32 = posix.SOCK.STREAM | posix.SOCK.NONBLOCK;
    const protocol = posix.IPPROTO.TCP;
    const listener = try posix.socket(address.any.family, tpe, protocol);
    defer posix.close(listener);

    try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &mem.toBytes(@as(c_int, 1)));
    try posix.bind(listener, &address.any, address.getOsSockLen());
    try posix.listen(listener, 128);

    self.polls[0] = posix.pollfd{
        .fd = listener,
        .revents = 0,
        .events = posix.POLL.IN,
    };

    const chunk_data_compressed = @import("main.zig").chunk_data_compressed;

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
            const revents = self.connection_polls[i].revents;
            if (revents == 0) {
                i += 1;
                continue;
            }

            const client = &self.connections[i];
            if (revents & posix.POLL.IN == posix.POLL.IN) {
                const packet = client.readMessage() catch |err| switch (err) {
                    error.Disconnected => {
                        std.debug.print("Client {} disconnected\n", .{client.address.getPort()});
                        self.removeClient(i);
                        i += 1;
                        continue;
                    },
                    error.InvalidPacket => {
                        std.debug.print("Client {} sent invalid packet\n", .{client.address.getPort()});
                        const nb = client.serverbound_buffer;
                        printBytes(nb.buffer[nb.read_head..nb.write_head]);
                        self.removeClient(i);
                        i += 1;
                        continue;
                    },
                    error.EndOfStream => {
                        i += 1;
                        continue;
                    },
                    else => {
                        std.debug.print("Client {} had error {}\n", .{
                            client.address.getPort(),
                            err,
                        });
                        continue;
                    },
                };

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
                    });

                    for (1..45) |j| {
                        const k: u8 = @intCast(j);
                        _ = try posix.write(client.socket, &.{
                            0x00, k, k, 0x00, 0x00
                        });
                    }

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

                    try client.writeMessage(.{
                        .chat_message = .ofString("Hello from Zig!"),
                    });
                }

                if (packet == .chat_message) {
                    const value = packet.chat_message.message;
                    defer self.allocator.free(value);

                    if (value[0] == '/') {
                        var parts = mem.splitScalar(u8, value[1..], ' ');
                        const command = parts.next() orelse "help";

                        if (mem.eql(u8, command, "help")) {
                            inline for (.{
                                "--- Help ---",
                                "wowwie"
                            }) |msg| {
                                try client.writeMessage(.{
                                    .chat_message = .ofString(msg)
                                });
                            }
                        } else if (mem.startsWith(u8, command, "utf")) {
                            var from: u16 = 0;

                            var msg: [18]u8 = .{'&', 'a', 'F', 'r', 'o', 'm', ':', ' ', '0', 'x'} ++ [_]u8{' '} ** 8;
                            _ = std.fmt.bufPrintIntToSlice(msg[10..18], from, 16, .upper, .{.alignment = .left});
                            try client.writeMessage(.{
                                .chat_message = .ofString(&msg),
                            });

                            msg = .{'&', 'a', 'T', 'o', ':', ' ', '0', 'x'} ++ [_]u8{' '} ** 10;
                            _ = std.fmt.bufPrintIntToSlice(msg[8..16], from + 16 * 16, 16, .upper, .{.alignment = .left});
                            try client.writeMessage(.{
                                .chat_message = proto.ChatMessage.ofString(&msg),
                            });

                            for (0..16) |offset| {
                                const start: u8 = @intCast(from + offset * 16);
                                try client.writeMessage(.{
                                    .chat_message = .{
                                        .message = &[16]u8 {
                                            start, start + 1, start + 2, start + 3,
                                            start + 4, start + 5, start + 6, start + 7,
                                            start + 8, start + 9, start + 10, start + 11,
                                            start + 12, start + 13, start + 14, start + 15,
                                        },
                                    },
                                });
                            }
                            from += 16 * 16;
                        } else {
                            try client.writeMessage(.{
                                .chat_message = proto.ChatMessage.ofString("&4Unknown command. Check /help")
                            });
                        }
                    } else {
                        for (self.connections[0..self.connected]) |*target| {
                            try target.writeMessage(.{ .chat_message = .ofString(value) });
                        }
                    }
                }
            }
        }

        // Handle broadcasting messages to clients
    }
}

fn acceptClients(self: *Self, listener: posix.socket_t) !void {
    while (true) {
        self.acceptClient(listener) catch |err| switch (err) {
            error.WouldBlock => return,
            else => return err,
        };
    }
}

fn acceptClient(self: *Self, listener: posix.socket_t) !void {
    var address: net.Address = undefined;
    var address_len: posix.socklen_t = @sizeOf(net.Address);

    const socket = try posix.accept(listener, &address.any, &address_len, posix.SOCK.NONBLOCK);
    const client = try ServerConnection.init(self.allocator, socket, address);

    self.connections[self.connected] = client;
    self.connection_polls[self.connected] = posix.pollfd{
        .fd = socket,
        .revents = 0,
        .events = posix.POLL.IN,
    };

    self.connected += 1;

    std.debug.print("Client {} connected\n", .{address});
}

fn removeClient(self: *Self, index: usize) void {
    var client = self.connections[index];
    posix.close(client.socket);
    client.deinit();

    const last_index = self.connected - 1;
    self.connections[index] = self.connections[last_index];
    self.connection_polls[index] = self.connection_polls[last_index];

    self.connected = last_index;
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.polls);
    self.allocator.free(self.connections);
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
