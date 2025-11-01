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

const Chunk = @import("world/Chunk.zig");
const overworld_gen = @import("world/gen/overworld.zig");

const mc = @import("mc.zig");

allocator: Allocator,

running: bool = true,

connected: usize,
connections_pool: std.heap.MemoryPool(ServerConnection),
connections: []*ServerConnection,

eid: u32 = 0,

world_seed: u64,
chunks: std.ArrayList(Chunk),

pub fn init(allocator: Allocator, max_clients: usize, world_seed: u64, world_size: u64) !Self {
    const connections = try allocator.alloc(*ServerConnection, max_clients);
    errdefer allocator.free(connections);

    var connections_pool = std.heap.MemoryPool(ServerConnection).init(allocator);
    errdefer connections_pool.deinit();

    var chunks = std.ArrayList(Chunk).init(allocator);
    errdefer chunks.deinit();

    // Generate the chunks
    var timer = try std.time.Timer.start();
    overworld_gen.initializeGenerator(world_seed);
    for (0..world_size * world_size) |i| {
        const x = @as(i32, @intCast(i % world_size)) - @as(i32, @intCast(world_size / 2));
        const z = @as(i32, @intCast(i / world_size)) - @as(i32, @intCast(world_size / 2));
        const chunk = try chunks.addOne();
        chunk.* = try Chunk.init(allocator, x, z);
        errdefer chunk.deinit();
        overworld_gen.generateChunk(chunk);
    }

    const time = timer.read();
    std.debug.print("Time to generate chunks: {}.{}ms\n", .{time / 1_000_000, time % 1000});

    return Self{
        .allocator = allocator,
        .connected = 0,
        .connections_pool = connections_pool,
        .connections = connections,
        .world_seed = world_seed,
        .chunks = chunks,
    };
}

pub fn deinit(self: *Self) void {
    for (self.connections[0..self.connected]) |conn| {
        if (conn.player) |player| {
            self.allocator.destroy(player);
        }
        conn.deinit();
    }

    for (self.chunks.items) |*chunk| {
        chunk.deinit();
    }

    self.chunks.deinit();
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

    var packet_arena = std.heap.ArenaAllocator.init(self.allocator);
    defer packet_arena.deinit();

    while (self.running) {
        const ready_events = b: {
            var ev_buf: [1024]linux.epoll_event = undefined;
            const len = posix.epoll_wait(epfd, &ev_buf, 500);
            break :b ev_buf[0..len];
        };

        if (ready_events.len == 0) {
            std.debug.print("Timeout\n", .{});
            continue;
        }

        events: for (ready_events) |ready| {
            switch (ready.data.ptr) {
                0 => try self.acceptClient(listener, epfd),
                else => |ptr| {
                    // const events = ready.events;
                    const client: *ServerConnection = @ptrFromInt(ptr);

                    while (true) {
                        const packet = client.readMessage(packet_arena.allocator()) catch |err| switch (err) {
                            error.NettyProtocol => {
                                std.debug.print("Client {} is running a modern version of MC\n", .{client.address.getPort()});
                                self.removeClient(client);
                                continue :events;
                            },
                            error.Disconnected => {
                                std.debug.print("Client {} disconnected\n", .{client.address.getPort()});
                                self.removeClient(client);
                                continue :events;
                            },
                            error.InvalidPacket => {
                                std.debug.print("Client {} sent invalid packet\n", .{client.address.getPort()});
                                const nb = client.serverbound_buffer;
                                printBytes(nb.buffer[nb.read_head..nb.write_head]);
                                self.removeClient(client);
                                continue :events;
                            },
                            error.EndOfStream => break,
                            else => {
                                std.debug.print("Client {} had error {}\n", .{
                                    client.address.getPort(),
                                    err,
                                });
                                continue :events;
                            },
                        };

                        try self.processPacket(packet, client);
                    }
                },
            }
        }

        for (self.connections[0..self.connected]) |connection| {
            connection.writeMessage(.{ .keep_alive = .{} }) catch {
                std.debug.print("Error sending keep alive to client {}\n", .{
                    connection.address.getPort(),
                });
                continue;
            };
        }

        // Reset the packet memory arena
        _ = packet_arena.reset(.retain_capacity);
    }
}

fn processPacket(self: *Self, packet: proto.Packet, client: *ServerConnection) !void {
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

            player.x = 0.0;
            player.y = 128.0;
            player.z = 0.0;

            try client.writeMessage(.{ .login = .{
                .data = player.eid,
                .username = &.{},
                .map_seed = 0,
                .dimension = 0,
            } });

            try client.writeMessage(.{ .spawn_position = .{
                .x = @intFromFloat(player.x),
                .y = @intFromFloat(player.y),
                .z = @intFromFloat(player.z),
            } });

            try client.writeMessage(.{ .time_update = .{
                .time = 6_000,
            } });

            try client.writeMessage(.{ .update_health = .{
                .health = 20
            } });

            // Window items
            const items = [_]?mc.Item{ null } ** 9 ++ [_]?mc.Item{
                mc.Item.stack(.stone_block),
                mc.Item.stack(.cobblestone_block),
            };

            try client.writeMessage(.{ .window_initialize = .{
                .window_id = 0,
                .items = &items,
            } });

            var timer = try std.time.Timer.start();
            for (self.chunks.items) |*chunk| {
                try client.writeMessage(.{ .prepare_chunk = .{
                    .chunk_x = chunk.chunk_x,
                    .chunk_z = chunk.chunk_z,
                    .action = .load,
                } });
                try client.writeMessage(.{ .map_chunk = .ofChunk(chunk) });
            }
            const time = timer.read();
            std.debug.print("Time to send all chunk packets: {}.{}ms\n", .{time / 1_000_000, time % 1000});

            try client.writeMessage(.{ .player_position_and_look = .{
                .x = player.x,
                .y = player.y,
                .z = player.z,
                .stance = player.y + 0.62,
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
                            .x = @intFromFloat(player.x * 32.0),
                            .y = @intFromFloat(player.y * 32.0),
                            .z = @intFromFloat(player.z * 32.0),
                            .yaw = 0,
                            .pitch = 0,
                            .current_item = 0,
                        } });

                        try client.writeMessage(.{ .named_entity_spawn = .{
                            .entity_id = target_player.eid,
                            .username = target_player.username(),
                            .x = @intFromFloat(target_player.x * 32.0),
                            .y = @intFromFloat(target_player.y * 32.0),
                            .z = @intFromFloat(target_player.z * 32.0),
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
    var updated_position = false;

    switch (packet) {
        .keep_alive, .handshake, .login => unreachable,
        .chat_message => |chat_message| {
            const raw_message = chat_message.message;

            if (raw_message[0] == '/') {
                try self.processCommand(player, raw_message);
                return;
            }

            var message_buf: [256]u8 = undefined;
            const message = try std.fmt.bufPrint(&message_buf, "{s}: {s}", .{ player.username(), raw_message });

            for (self.connections[0..self.connected]) |target| {
                try target.writeMessage(.{ .chat_message = .ofString(message) });
            }
        },
        .player_position => |pos| {
            updated_position = true;
            player.x = pos.x;
            player.y = pos.y;
            player.z = pos.z;
        },
        .player_position_and_look => |pos| {
            updated_position = true;
            player.x = pos.x;
            player.y = pos.y;
            player.z = pos.z;
        },
        else => {},
    }

    for (self.connections[0..self.connected]) |target| {
        if (target.player) |target_player| {
            if (target_player.eid != player.eid) {
                try target.writeMessage(.{ .entity_teleport = .{
                    .entity_id = player.eid,
                    .x = @intFromFloat(player.x * 32.0),
                    .y = @intFromFloat(player.y * 32.0),
                    .z = @intFromFloat(player.z * 32.0),
                    .yaw = 0,
                    .pitch = 0,
                } });
            }
        }
    }
}

fn processCommand(self: *Self, player: *Player, raw_command: []const u8) !void {
    var parts = mem.splitScalar(u8, raw_command[1..], ' ');

    const command_str = parts.next() orelse "unknown";
    const command = std.meta.stringToEnum(enum {
        unknown,
        help,
        npc,
        stop,
    }, command_str) orelse .unknown;

    switch (command) {
        .unknown => {
            try player.connection.writeMessage(.{
                .chat_message = .ofString("Unknown command! Use /help to see all commands."),
            });
        },
        .help => {
            try player.connection.writeMessage(.{
                .chat_message = .ofString("Available commands: unknown, help, npc, stop"),
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
        .stop => {
            try player.connection.writeMessage(.{
                .chat_message = .ofString("Stopping the server"),
            });

            self.running = false;
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
