const Self = @This();

const std = @import("std");
const proto = @import("protocol.zig");

const mem = std.mem;
const net = std.net;
const posix = std.posix;

const Allocator = mem.Allocator;

const Player = @import("Player.zig");
const StreamReader = @import("StreamReader.zig");
const ServerConnection = @import("ServerConnection.zig");

allocator: Allocator,

polls: []posix.pollfd,

connected: usize,
connections: []ServerConnection,
connection_polls: []posix.pollfd,

eid: u32 = 0,

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

pub fn deinit(self: *Self) void {
    self.allocator.free(self.polls);
    self.allocator.free(self.connections);
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
                var moved = false;

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
                    try client.writeMessage(.{ .keep_alive = .{} });
                }

                if (packet == .handshake) {
                    try client.writeMessage(.{ .handshake = .{ .data = "-" } });
                }

                if (packet == .login) {
                    // crap
                    const player = try self.allocator.create(Player);
                    errdefer self.allocator.destroy(player);
                    player.* = Player.init(client, self.nextEid());
                    std.mem.copyForwards(u8, &player.username_str, packet.login.username);
                    player.username_len = packet.login.username.len;
                    client.player = player;

                    player.x = 60.0;
                    player.y = 32.0;
                    player.z = 60.0;

                    try client.writeMessage(.{ .login = .{
                        .data = player.eid,
                        .username = &.{},
                        .map_seed = 0,
                        .dimension = 0,
                    } });

                    try client.writeMessage(.{ .spawn_position = .{
                        .x = 120,
                        .y = 64,
                        .z = 120,
                    } });

                    try client.writeMessage(.{ .time_update = .{
                        .time = 6_000,
                    } });

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
                            0x00, k, k, 0x00, 0x00,
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
                                @truncate(chunk_data_compressed.len >> 24), // chunk data
                                @truncate(chunk_data_compressed.len >> 16),
                                @truncate(chunk_data_compressed.len >> 8),
                                @truncate(chunk_data_compressed.len),
                            });
                            const b = try posix.write(client.socket, chunk_data_compressed);
                            std.debug.print("{} - {} - {}\n", .{ chunk_data_compressed.len, a, b });
                        }
                    }

                    try client.writeMessage(.{ .player_position_and_look = .{
                        .x = player.x,
                        .y = player.y,
                        .z = player.z,
                        .stance = 33.5,
                        .yaw = 0.0,
                        .pitch = 0.0,
                        .on_ground = false,
                    } });

                    try client.writeMessage(.{
                        .chat_message = .ofString("Hello from Zig!"),
                    });

                    for (self.connections[0..self.connected]) |*target| {
                        if (target.player) |target_player| {
                            if (target_player.eid != player.eid) {
                                try target.writeMessage(.{ .named_entity_spawn = .{
                                    .entity_id = player.eid,
                                    .username = player.username(),
                                    .x = @intFromFloat(player.x),
                                    .y = @intFromFloat(player.y),
                                    .z = @intFromFloat(player.z),
                                    .yaw = 0,
                                    .pitch = 0,
                                    .current_item = 0,
                                } });

                                try client.writeMessage(.{ .named_entity_spawn = .{
                                    .entity_id = target_player.eid,
                                    .username = target_player.username(),
                                    .x = @intFromFloat(target_player.x),
                                    .y = @intFromFloat(target_player.y),
                                    .z = @intFromFloat(target_player.z),
                                    .yaw = 0,
                                    .pitch = 0,
                                    .current_item = 0,
                                } });
                            }
                        }
                    }
                }

                if (packet == .player_position_and_look) {
                    if (client.player) |player| {
                        moved = true;
                        player.x = packet.player_position_and_look.x;
                        player.y = packet.player_position_and_look.y;
                        player.z = packet.player_position_and_look.z;
                    }
                }

                if (packet == .player_position) {
                    if (client.player) |player| {
                        moved = true;
                        player.x = packet.player_position.x;
                        player.y = packet.player_position.y;
                        player.z = packet.player_position.z;
                    }
                }

                // TODO: REMOVE JANK
                if (moved) {
                    if (client.player) |player| {
                        for (self.connections[0..self.connected]) |*target| {
                            if (target.player) |target_player| {
                                if (target_player.eid != player.eid) {
                                    try target.writeMessage(.{ .entity_teleport = .{
                                        .entity_id = player.eid,
                                        .x = @intFromFloat(player.x * 32.0),
                                        .y = @intFromFloat(player.y * 32.0),
                                        .z = @intFromFloat(player.z * 32.0),
                                        .yaw = 0.0,
                                        .pitch = 0.0,
                                    } });
                                }
                            }
                        }
                    }
                }

                if (packet == .chat_message) {
                    const value = packet.chat_message.message;
                    defer self.allocator.free(value);

                    if (value[0] == '/') {
                        var parts = mem.splitScalar(u8, value[1..], ' ');
                        const command = parts.next() orelse "help";

                        if (mem.eql(u8, command, "help")) {
                            inline for (.{ "--- Help ---", "wowwie" }) |msg| {
                                try client.writeMessage(.{ .chat_message = .ofString(msg) });
                            }
                        } else if (mem.startsWith(u8, command, "npc")) {
                            if (client.player) |player| {
                                const npcEid = self.nextEid();

                                var username: [5]u8 = undefined;
                                @memcpy(&username, "NPC00");
                                username[3] = @as(u8, @intCast(npcEid >> 4)) + '0';
                                username[4] = @as(u8, @intCast(npcEid & 0xF)) + '0';

                                try client.writeMessage(.{ .named_entity_spawn = .{
                                    .entity_id = npcEid,
                                    .username = &username,
                                    .x = @intFromFloat(player.x * 32.0),
                                    .y = @intFromFloat(player.y * 32.0),
                                    .z = @intFromFloat(player.z * 32.0),
                                    .yaw = 0,
                                    .pitch = 0,
                                    .current_item = 0,
                                } });

                                try client.writeMessage(.{ .entity_teleport = .{
                                    .entity_id = npcEid,
                                    .x = @intFromFloat(player.x * 32.0),
                                    .y = @intFromFloat(player.y * 32.0),
                                    .z = @intFromFloat(player.z * 32.0),
                                    .yaw = 0,
                                    .pitch = 0,
                                } });

                                try client.writeMessage(.{
                                    .chat_message = .ofString("Spawned a NPC with ID " ++
                                        .{@as(u8, @intCast(npcEid >> 4)) + '0'} ++
                                        .{@as(u8, @intCast(npcEid & 0xF)) + '0'}),
                                });
                            }
                        } else {
                            try client.writeMessage(.{
                                .chat_message = .ofString("&4Unknown command. Check /help"),
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

fn nextEid(self: *Self) u32 {
    const eid = self.eid;
    self.eid += 1;
    return eid;
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
