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
pub const KeepAlive = struct {
    pub const Name = "keep_alive";
    pub const ID = 0x00;

    pub fn decode(reader: *StreamReader) !KeepAlive {
        // noop
        _ = reader;
    }

    pub fn encode(self: KeepAlive, writer: io.AnyWriter) !void {
        // noop
        _ = self;
        _ = writer;
    }
};

pub const Login = struct {
    pub const Name = "login";
    pub const ID = 0x01;

    /// - Serverbound: Protocol Version
    /// - Clientbound: Player's Entity ID
    data: u32,
    username: []const u8,
    map_seed: u64,
    dimension: u8,

    pub fn decode(reader: *StreamReader, alloc: std.mem.Allocator) !Login {
        var self: Login = undefined;
        self.data = try reader.readInt(u32, .big);
        self.username = try reader.readStringUtf16BE(alloc);
        self.map_seed = try reader.readInt(u64, .big);
        self.dimension = try reader.readByte();
        return self;
    }

    pub fn encode(self: Login, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.data, .big);
        try writeString16(self.username, writer);
        try writer.writeInt(u64, self.map_seed, .big);
        try writer.writeByte(self.dimension);
    }
};

pub const Handshake = struct {
    pub const Name = "handshake";
    pub const ID = 0x02;

    /// - Serverbound: Username
    /// - Clientbound: Connection Hash
    data: []const u8,

    pub fn decode(reader: *StreamReader, alloc: std.mem.Allocator) !Handshake {
        var self: Handshake = undefined;
        self.data = try reader.readStringUtf16BE(alloc);
        return self;
    }

    pub fn encode(self: Handshake, writer: io.AnyWriter) !void {
        try writeString16(self.data, writer);
    }
};

pub const ChatMessage = struct {
    pub const Name = "chat_message";
    pub const ID = 0x03;

    message: []const u8,

    pub fn ofString(message: []const u8) ChatMessage {
        return ChatMessage{
            .message = message,
        };
    }

    pub fn encode(self: ChatMessage, writer: io.AnyWriter) !void {
        try writeString16(self.message, writer);
    }

    pub fn decode(reader: *StreamReader, alloc: std.mem.Allocator) !ChatMessage {
        var self: ChatMessage = undefined;
        self.message = try reader.readStringUtf16BE(alloc);
        return self;
    }
};

pub const PlayerOnGround = struct {
    pub const Name = "player_on_ground";
    pub const ID = 0x0A;

    on_ground: bool,

    pub fn decode(reader: *StreamReader) !PlayerOnGround {
        var self: PlayerOnGround = undefined;
        self.on_ground = try reader.readBoolean();
        return self;
    }
};

pub const PlayerPosition = struct {
    pub const Name = "player_position";
    pub const ID = 0x0B;

    x: f64,
    y: f64,
    stance: f64,
    z: f64,
    on_ground: bool,

    pub fn decode(reader: *StreamReader) !PlayerPosition {
        var self: PlayerPosition = undefined;
        self.x = try reader.readFloat(f64);
        self.y = try reader.readFloat(f64);
        self.stance = try reader.readFloat(f64);
        self.z = try reader.readFloat(f64);
        self.on_ground = try reader.readBoolean();
        return self;
    }
};

pub const PlayerLook = struct {
    pub const Name = "player_look";
    pub const ID = 0x0C;

    yaw: f32,
    pitch: f32,
    on_ground: bool,

    pub fn decode(reader: *StreamReader) !PlayerLook {
        var self: PlayerLook = undefined;
        self.yaw = try reader.readFloat(f32);
        self.pitch = try reader.readFloat(f32);
        self.on_ground = try reader.readBoolean();
        return self;
    }
};

pub const PlayerPositionAndLook = struct {
    pub const Name = "player_position_and_look";
    pub const ID = 0x0D;

    x: f64,
    y: f64,
    stance: f64,
    z: f64,
    yaw: f32,
    pitch: f32,
    on_ground: bool,

    pub fn decode(reader: *StreamReader) !PlayerPositionAndLook {
        var self: PlayerPositionAndLook = undefined;
        self.x = try reader.readFloat(f64);
        self.y = try reader.readFloat(f64);
        self.stance = try reader.readFloat(f64);
        self.z = try reader.readFloat(f64);
        self.yaw = try reader.readFloat(f32);
        self.pitch = try reader.readFloat(f32);
        self.on_ground = try reader.readBoolean();
        return self;
    }
};

pub const HoldingChange = struct {
    pub const Name = "holding_change";
    pub const ID = 0x10;

    slot: u16,

    pub fn decode(reader: *StreamReader) !HoldingChange {
        var self: HoldingChange = undefined;
        self.slot = try reader.readInt(u16, .big);
        return self;
    }
};

// Silly comptime stuff :3
const packets = [_]type{
    KeepAlive,
    Login,
    Handshake,
    ChatMessage,
    PlayerOnGround,
    PlayerPosition,
    PlayerLook,
    PlayerPositionAndLook,
    HoldingChange,
};

pub const PacketId: type = t: {
    var fields: [packets.len]std.builtin.Type.EnumField = undefined;

    for (packets, 0..) |packet, i| {
        fields[i] = std.builtin.Type.EnumField{
            .name = packet.Name,
            .value = packet.ID,
        };
    }

    break :t @Type(.{ .@"enum" = std.builtin.Type.Enum{
        .decls = &.{},
        .fields = &fields,
        .tag_type = u8,
        .is_exhaustive = true,
    } });
};

pub const Packet: type = t: {
    var fields: [packets.len]std.builtin.Type.UnionField = undefined;

    for (packets, 0..) |packet, i| {
        fields[i] = std.builtin.Type.UnionField{
            .alignment = 0,
            .name = packet.Name,
            .type = packet,
        };
    }

    break :t @Type(.{ .@"union" = std.builtin.Type.Union{
        .decls = &.{},
        .fields = &fields,
        .layout = .auto,
        .tag_type = PacketId,
    } });
};

comptime {
    if (@sizeOf(Packet) > 128) {
        @compileError("Packet size over 128!");
    }
}

pub fn readPacket(reader: *StreamReader, alloc: std.mem.Allocator) !Packet {
    const packet_id = try reader.readByte();

    return switch (packet_id) {
        0x00 => .{ .keep_alive = .{} },
        0x01 => .{ .login = try Login.decode(reader, alloc) },
        0x02 => .{ .handshake = try Handshake.decode(reader, alloc) },
        0x03 => .{ .chat_message = try ChatMessage.decode(reader, alloc) },
        0x0A => .{ .player_on_ground = try PlayerOnGround.decode(reader) },
        0x0B => .{ .player_position = try PlayerPosition.decode(reader) },
        0x0C => .{ .player_look = try PlayerLook.decode(reader) },
        0x0D => .{ .player_position_and_look = try PlayerPositionAndLook.decode(reader) },
        0x10 => .{ .holding_change = try HoldingChange.decode(reader) },
        else => {
            std.debug.print("Read packet ID 0x{0X:0>2} ({0d})\n", .{packet_id});
            return error.InvalidPacket;
        },
    };
}

pub fn writePacket(writer: io.AnyWriter, anyPacket: Packet) !void {
    try writer.writeByte(@intFromEnum(anyPacket));
    switch (anyPacket) {
        inline else => |packet| {
            if (@hasDecl(@TypeOf(packet), "encode")) {
                try packet.encode(writer);
            }
        },
    }
}
