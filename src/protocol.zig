const std = @import("std");
const io = std.io;

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

pub const ChatMessage = struct {
    message: String16,

    pub fn encode(self: ChatMessage, writer: io.AnyWriter) !void {
        try self.message.encode(writer);
    }

    pub fn decode(reader: io.AnyReader, alloc: std.mem.Allocator) !ChatMessage {
        var self: ChatMessage = undefined;
        self.message = try String16.decode(reader, alloc);
        return self;
    }

    pub fn fromUtfString(string: []const u8, alloc: std.mem.Allocator) !ChatMessage {
        var value = try alloc.alloc(u16, string.len);
        for (string, 0..) |char, i| {
            value[i] = if (char == '&') 0x00A7 else char;
            // if (char == '&') {
            //
            // } else {
            //     value[i] = char;
            // }
        }
        return ChatMessage{
            .message = String16{
                .length = @intCast(value.len),
                .value = value,
            }
        };
    }

    pub fn toUtfString(self: ChatMessage, alloc: std.mem.Allocator) ![]const u8 {
        var string = try alloc.alloc(u8, self.message.length);
        for (self.message.value, 0..) |char, i| {
            string[i] = @truncate(char);
        }
        return string;
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

pub fn readPacket(reader: io.AnyReader, alloc: std.mem.Allocator) !ServerboundPacket {
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
