const std = @import("std");
const io = std.io;

pub const Direction = enum {
    Universal,
    Serverbound,
    Clientbound,

    fn isServerbound(self: Direction) bool {
        return self != .Clientbound;
    }

    fn isClientbound(self: Direction) bool {
        return self != .Serverbound;
    }
};

pub const String16 = struct {
    length: u16,
    value: []u16,

    pub fn encode(self: String16, writer: io.AnyWriter) !void {
        try writer.writeInt(u16, self.length, .big);
        for (0..self.length) |i| {
            try writer.writeInt(u16, self.value[i], .big);
        }
    }

    pub fn decode(reader: io.AnyReader, alloc: std.mem.Allocator) !String16 {
        var self: String16 = undefined;
        self.length = try reader.readInt(u16, .big);
        self.value = try alloc.alloc(u16, self.length);

        for (0..self.length) |i| {
            self.value[i] = try reader.readInt(u16, .big);
        }
        return self;
    }
};

// Packets
pub const KeepAlive = struct {};

pub const ServerboundLogin = struct {
    pub const ID = 0x01;

    protocol_version: u32,
    username: String16,
    map_seed: u64,
    dimension: u8,

    pub fn decode(reader: io.AnyReader, alloc: std.mem.Allocator) !ServerboundLogin {
        var self: ServerboundLogin = undefined;
        self.protocol_version = try reader.readInt(u32, .big);
        self.username = try String16.decode(reader, alloc);
        self.map_seed = try reader.readInt(u64, .big);
        self.dimension = try reader.readByte();
        return self;
    }
};

pub const ClientboundLogin = struct {
    entity_id: u32,
    username: String16,
    map_seed: u64,
    dimension: u8,

    pub fn encode(self: ClientboundLogin, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.entity_id, .big);
        try self.username.encode(writer);
        try writer.writeInt(u64, self.map_seed, .big);
        try writer.writeByte(self.dimension);
    }
};

pub const ServerboundHandshake = struct {
    username: String16,

    pub fn decode(reader: io.AnyReader, alloc: std.mem.Allocator) !ServerboundHandshake {
        var self: ServerboundHandshake = undefined;
        self.username = try String16.decode(reader, alloc);
        return self;
    }
};

pub const ClientboundHandshake = struct {
    connection_hash: String16,

    pub fn encode(self: ClientboundHandshake, writer: io.AnyWriter) !void {
        try self.connection_hash.encode(writer);
    }
};

pub const ClientboundPlayerPositionAndLook = struct {
    x: f64,
    y: f64,
    stance: f64,
    z: f64,
    yaw: f32,
    pitch: f32,
    on_ground: bool,
};

pub const PacketId = enum(u8) {
    keep_alive = 0x00,
    login = 0x01,
    handshake = 0x02,
};

pub const ServerboundPacket = union(PacketId) {
    keep_alive: KeepAlive,
    login: ServerboundLogin,
    handshake: ServerboundHandshake,
};

pub const ClientboundPacket = union(PacketId) {
    keep_alive: KeepAlive,
    login: ClientboundLogin,
    handshake: ClientboundHandshake,
};

pub fn readPacket(reader: io.AnyReader, alloc: std.mem.Allocator) !ServerboundPacket {
    const packet_id = try reader.readByte();

    return switch (packet_id) {
        0x00 => .{ .keep_alive = .{} },
        0x01 => .{ .login = try ServerboundLogin.decode(reader, alloc) },
        0x02 => .{ .handshake = try ServerboundHandshake.decode(reader, alloc) },
        else => error.InvalidPacket,
    };
}

pub fn writePacket(writer: io.AnyWriter, packet: ClientboundPacket) !void {
    try writer.writeByte(@intFromEnum(packet));

    switch (packet) {
        .keep_alive => {},
        .login => |p| try p.encode(writer),
        .handshake => {},
    }
}
