const std = @import("std");

const StreamReader = @import("StreamReader.zig");
const io = std.io;

fn writeString16(str: []const u8, writer: io.AnyWriter) !void {
    try writer.writeInt(u16, @intCast(str.len), .big);
    for (str) |c| {
        try writer.writeInt(u16, c, .big);
    }
}

// Packets
pub const KeepAlive = struct {};

pub const ServerboundLogin = struct {
    protocol_version: u32,
    username: []const u8,
    map_seed: u64,
    dimension: u8,

    pub fn decode(reader: *StreamReader, alloc: std.mem.Allocator) !ServerboundLogin {
        var self: ServerboundLogin = undefined;
        self.protocol_version = try reader.readInt(u32, .big);
        self.username = try reader.readStringUtf16BE(alloc);
        self.map_seed = try reader.readInt(u64, .big);
        self.dimension = try reader.readByte();
        return self;
    }
};

pub const ClientboundLogin = struct {
    entity_id: u32,
    username: []const u8,
    map_seed: u64,
    dimension: u8,

    pub fn encode(self: ClientboundLogin, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.entity_id, .big);
        try writeString16(self.username, writer);
        try writer.writeInt(u64, self.map_seed, .big);
        try writer.writeByte(self.dimension);
    }
};

pub const ServerboundHandshake = struct {
    username: []const u8,

    pub fn decode(reader: *StreamReader, alloc: std.mem.Allocator) !ServerboundHandshake {
        var self: ServerboundHandshake = undefined;
        self.username = try reader.readStringUtf16BE(alloc);
        return self;
    }
};

pub const ClientboundHandshake = struct {
    connection_hash: []const u8,

    pub fn encode(self: ClientboundHandshake, writer: io.AnyWriter) !void {
        try writeString16(self.connection_hash, writer);
    }
};

pub const ChatMessage = struct {
    message: []const u8,

    pub fn encode(self: ChatMessage, writer: io.AnyWriter) !void {
        try writeString16(self.message, writer);
    }

    pub fn decode(reader: *StreamReader, alloc: std.mem.Allocator) !ChatMessage {
        var self: ChatMessage = undefined;
        self.message = try reader.readStringUtf16BE(alloc);
        return self;
    }

    pub fn init(message: []const u8) ChatMessage {
        return ChatMessage{
            .message = message,
        };
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

pub const ServerboundPacket = union(enum) {
    keep_alive: KeepAlive,
    login: ServerboundLogin,
    handshake: ServerboundHandshake,
    chat_message: ChatMessage,
};

pub const ClientboundPacketId = enum(u8) {
    keep_alive = 0x00,
    login = 0x01,
    handshake = 0x02,
    chat_message = 0x03,
};

pub const ClientboundPacket = union(ClientboundPacketId) {
    keep_alive: KeepAlive,
    login: ClientboundLogin,
    handshake: ClientboundHandshake,
    chat_message: ChatMessage,
};

pub fn readPacket(reader: *StreamReader, alloc: std.mem.Allocator) !ServerboundPacket {
    const packet_id = try reader.readByte();

    return switch (packet_id) {
        0x00 => .{ .keep_alive = .{} },
        0x01 => .{ .login = try ServerboundLogin.decode(reader, alloc) },
        0x02 => .{ .handshake = try ServerboundHandshake.decode(reader, alloc) },
        0x03 => .{ .chat_message = try ChatMessage.decode(reader, alloc) },
        else => error.InvalidPacket,
    };
}

pub fn writePacket(writer: io.AnyWriter, packet: ClientboundPacket) !void {
    try writer.writeByte(@intFromEnum(packet));

    switch (packet) {
        .keep_alive => {},
        .login => |p| try p.encode(writer),
        .handshake => {},
        .chat_message => |p| try p.encode(writer),
    }
}
