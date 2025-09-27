const Self = @This();

const std = @import("std");
const proto = @import("protocol.zig");

const mem = std.mem;
const net = std.net;
const posix = std.posix;
const linux = std.os.linux;

const Allocator = mem.Allocator;

const Player = @import("Player.zig");
const StreamReader = @import("StreamReader.zig");
const ServerConnection = @import("ServerConnection.zig");

allocator: Allocator,

connected: usize,

connections_pool: std.heap.MemoryPool(ServerConnection),
connections: []*ServerConnection,

eid: u32 = 0,

pub fn init(allocator: Allocator, max_clients: usize) !Self {
    const connections = try allocator.alloc(*ServerConnection, max_clients);
    errdefer allocator.free(connections);

    return Self{
        .allocator = allocator,
        .connected = 0,
        .connections_pool = .init(allocator),
        .connections = connections,
    };
}

pub fn deinit(self: *Self) void {
    self.connections_pool.deinit();
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

    const epfd = try posix.epoll_create1(0);
    defer posix.close(epfd);

    // Add the server socket listener to the EPOLL
    {
        var events = linux.epoll_event{ .events = linux.EPOLL.IN, .data = .{ .ptr = 0 } };
        try posix.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, listener, &events);
    }

    while (true) {
        std.debug.print("Looped\n", .{});

        const ready_events = b: {
            var ev_buf: [1024]linux.epoll_event = undefined;
            const len = posix.epoll_wait(epfd, &ev_buf, 500);
            break :b ev_buf[0..len];
        };

        if (ready_events.len == 0) {
            std.debug.print("Timeout\n", .{});
            continue;
        }

        for (ready_events) |ready| {
            switch (ready.data.ptr) {
                0 => try self.acceptClient(listener, epfd),
                else => |ptr| {
                    // const events = ready.events;
                    const client: *ServerConnection = @ptrFromInt(ptr);

                    const packet = client.readMessage() catch |err| switch (err) {
                        error.NettyProtocol => {
                            std.debug.print("Client {} is running a modern version of MC\n", .{client.address.getPort()});
                            self.removeClient(client);
                            continue;
                        },
                        error.Disconnected => {
                            std.debug.print("Client {} disconnected\n", .{client.address.getPort()});
                            self.removeClient(client);
                            continue;
                        },
                        error.InvalidPacket => {
                            std.debug.print("Client {} sent invalid packet\n", .{client.address.getPort()});
                            const nb = client.serverbound_buffer;
                            printBytes(nb.buffer[nb.read_head..nb.write_head]);
                            self.removeClient(client);
                            continue;
                        },
                        error.EndOfStream => continue,
                        else => {
                            std.debug.print("Client {} had error {}\n", .{
                                client.address.getPort(),
                                err,
                            });
                            continue;
                        },
                    };

                    try self.processPacket(packet, client);
                }
            }
        }
    }
}

fn processPacket(self: *Self, packet: proto.Packet, client: *ServerConnection) !void {
    const chunk_data_compressed = @import("main.zig").chunk_data_compressed;

    switch (packet) {
        .keep_alive => try client.writeMessage(.{ .keep_alive = .{} }),
        .handshake => {
            try client.writeMessage(.{ .handshake = .{ .data = "-" } });
            client.stage = .play;
        },
        .login => |login| {
            const player = try self.allocator.create(Player);
            errdefer self.allocator.destroy(player);
            player.* = Player.init(client, self.nextEid());
            std.mem.copyForwards(u8, &player.username_str, login.username);
            player.username_len = login.username.len;
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
                    _ = try posix.write(client.socket, &.{
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
                    _ = try posix.write(client.socket, chunk_data_compressed);
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

            for (self.connections[0..self.connected]) |target| {
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
        },
        else => {
            if (client.player) |player| {
                try self.processPlayPacket(packet, player);
            } else {
                std.debug.print("Process play-stage packet ID 0x{0X:0>2} ({0d}) without player\n", .{@intFromEnum(packet)});
            }
        },
    }
}

fn processPlayPacket(self: *Self, packet: proto.Packet, player: *Player) !void {
    switch (packet) {
        .keep_alive, .handshake, .login => unreachable,
        .chat_message => |chat_message| {
            const message = chat_message.message;

            if (message[0] == '/') {
                try self.processCommand(player, message);
                return;
            }

            for (self.connections[0..self.connected]) |target| {
                try target.writeMessage(.{ .chat_message = .ofString(message) });
            }
        },
        .player_position => |pos| {
            player.x = pos.x;
            player.y = pos.y;
            player.z = pos.z;
        },
        .player_position_and_look => |pos| {
            player.x = pos.x;
            player.y = pos.y;
            player.z = pos.z;
        },
        else => {},
    }
}

fn processCommand(self: *Self, player: *Player, raw_command: []const u8) !void {
    var parts = mem.splitScalar(u8, raw_command[1..], ' ');

    const command_str = parts.next() orelse "unknown";
    const command = std.meta.stringToEnum(enum {
        unknown,
        help,
        npc,
    }, command_str) orelse .unknown;

    switch (command) {
        .unknown => {
            try player.connection.writeMessage(.{
                .chat_message = .ofString("Unknown command! Use /help to see all commands."),
            });
        },
        .help => {
            try player.connection.writeMessage(.{
                .chat_message = .ofString("Available commands: unknown, help, npc"),
            });
        },
        .npc => {
            const npcEid = self.nextEid();

            var username: [5]u8 = undefined;
            @memcpy(&username, "NPC00");
            username[3] = @as(u8, @intCast(npcEid >> 4)) + '0';
            username[4] = @as(u8, @intCast(npcEid & 0xF)) + '0';

            try player.connection.writeMessage(.{ .named_entity_spawn = .{
                .entity_id = npcEid,
                .username = &username,
                .x = @intFromFloat(player.x * 32.0),
                .y = @intFromFloat(player.y * 32.0),
                .z = @intFromFloat(player.z * 32.0),
                .yaw = 0,
                .pitch = 0,
                .current_item = 0,
            } });

            try player.connection.writeMessage(.{ .entity_teleport = .{
                .entity_id = npcEid,
                .x = @intFromFloat(player.x * 32.0),
                .y = @intFromFloat(player.y * 32.0),
                .z = @intFromFloat(player.z * 32.0),
                .yaw = 0,
                .pitch = 0,
            } });

            for (0..5) |slot| {
                try player.connection.writeMessage(.{ .entity_equipment = .{
                    .entity_id = npcEid,
                    .item_id = @intCast(42 + 256 + 3 * slot),
                    .slot = @enumFromInt(slot),
                    .metadata = 0,
                } });
            }

            try player.connection.writeMessage(.{
                .chat_message = .ofString("Spawned a NPC with ID " ++
                    .{@as(u8, @intCast(npcEid >> 4)) + '0'} ++
                    .{@as(u8, @intCast(npcEid & 0xF)) + '0'}),
            });
        },
    }
}

fn acceptClient(self: *Self, listener: posix.socket_t, epfd: posix.fd_t) !void {
    var address: net.Address = undefined;
    var address_len: posix.socklen_t = @sizeOf(net.Address);

    const socket = try posix.accept(listener, &address.any, &address_len, posix.SOCK.NONBLOCK);
    errdefer posix.close(socket);

    var client: *ServerConnection = try self.connections_pool.create();
    client.* = try ServerConnection.init(self.allocator, socket, address);
    errdefer client.deinit();

    const ptr: usize = @intFromPtr(client);
    var epev = linux.epoll_event{ .events = linux.EPOLL.IN, .data = .{ .ptr = ptr } };
    try posix.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, socket, &epev);

    self.connections[self.connected] = client;
    self.connected += 1;
}

fn removeClient(self: *Self, client: *ServerConnection) void {
    posix.close(client.socket);
    client.deinit();

    const idx = for (0..self.connected) |i| {
        const target = self.connections[i];
        if (target == client) {
            break i;
        }
    } else {
        std.debug.print("Client wasn't in array. Wtf\n", .{});
        return;
    };

    self.connected -= 1;
    self.connections[idx] = self.connections[self.connected];
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
