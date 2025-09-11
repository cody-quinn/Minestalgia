// Minecraft Beta 1.7.3 Packets Info:
// - https://minecraft.wiki/w/Minecraft_Wiki:Projects/wiki.vg_merge/Protocol?oldid=2769763

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
    pub const ID = 0x00;
};

pub const Login = struct {
    pub const ID = 0x01;

    /// - Serverbound: Protocol Version
    /// - Clientbound: Player's Entity ID
    data: u32,
    username: []const u8,
    map_seed: u64,
    dimension: u8,

    pub fn decode(reader: *StreamReader, alloc: std.mem.Allocator) !Login {
        return Login{
            .data = try reader.readInt(u32, .big),
            .username = try reader.readStringUtf16BE(alloc),
            .map_seed = try reader.readInt(u64, .big),
            .dimension = try reader.readByte(),
        };
    }

    pub fn encode(self: Login, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.data, .big);
        try writeString16(self.username, writer);
        try writer.writeInt(u64, self.map_seed, .big);
        try writer.writeByte(self.dimension);
    }
};

pub const Handshake = struct {
    pub const ID = 0x02;

    /// - Serverbound: Username
    /// - Clientbound: Connection Hash
    data: []const u8,

    pub fn decode(reader: *StreamReader, alloc: std.mem.Allocator) !Handshake {
        return Handshake{
            .data = try reader.readStringUtf16BE(alloc),
        };
    }

    pub fn encode(self: Handshake, writer: io.AnyWriter) !void {
        try writeString16(self.data, writer);
    }
};

pub const ChatMessage = struct {
    pub const ID = 0x03;

    message: []const u8,

    pub fn ofString(message: []const u8) ChatMessage {
        return ChatMessage{
            .message = message,
        };
    }

    pub fn decode(reader: *StreamReader, alloc: std.mem.Allocator) !ChatMessage {
        return ChatMessage{
            .message = try reader.readStringUtf16BE(alloc),
        };
    }

    pub fn encode(self: ChatMessage, writer: io.AnyWriter) !void {
        try writeString16(self.message, writer);
    }
};

pub const TimeUpdate = struct {
    pub const ID = 0x04;

    time: u64,

    pub fn decode(reader: *StreamReader) !TimeUpdate {
        return TimeUpdate{
            .time = try reader.readInt(u64, .big),
        };
    }

    pub fn encode(self: TimeUpdate, writer: io.AnyWriter) !void {
        try writer.writeInt(u64, self.time, .big);
    }
};

pub const EntityEquipment = struct {
    pub const ID = 0x05;

    entity_id: u32,
    /// 0. Held
    /// 1. Armor
    /// 2. Armor
    /// 3. Armor
    /// 4. Armor
    slot: u16,
    item_id: u16,
    unknown: u16,

    pub fn decode(reader: *StreamReader) !EntityEquipment {
        return EntityEquipment{
            .entity_id = try reader.readInt(u32, .big),
            .slot = try reader.readInt(u16, .big),
            .item_id = try reader.readInt(u16, .big),
            .unknown = try reader.readInt(u16, .big),
        };
    }

    pub fn encode(self: EntityEquipment, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.entity_id, .big);
        try writer.writeInt(u16, self.slot, .big);
        try writer.writeInt(u16, self.item_id, .big);
        try writer.writeInt(u16, self.unknown, .big);
    }
};

pub const SpawnPosition = struct {
    pub const ID = 0x06;

    x: i32,
    y: i32,
    z: i32,

    pub fn decode(reader: *StreamReader) !SpawnPosition {
        return SpawnPosition{
            .x = try reader.readInt(i32, .big),
            .y = try reader.readInt(i32, .big),
            .z = try reader.readInt(i32, .big),
        };
    }

    pub fn encode(self: SpawnPosition, writer: io.AnyWriter) !void {
        try writer.writeInt(i32, self.x, .big);
        try writer.writeInt(i32, self.y, .big);
        try writer.writeInt(i32, self.z, .big);
    }
};

pub const PlayerOnGround = struct {
    pub const ID = 0x0A;

    on_ground: bool,

    pub fn decode(reader: *StreamReader) !PlayerOnGround {
        return PlayerOnGround{
            .on_ground = try reader.readBoolean(),
        };
    }
};

pub const PlayerPosition = struct {
    pub const ID = 0x0B;

    x: f64,
    y: f64,
    stance: f64,
    z: f64,
    on_ground: bool,

    pub fn decode(reader: *StreamReader) !PlayerPosition {
        return PlayerPosition{
            .x = try reader.readFloat(f64),
            .y = try reader.readFloat(f64),
            .stance = try reader.readFloat(f64),
            .z = try reader.readFloat(f64),
            .on_ground = try reader.readBoolean(),
        };
    }
};

pub const PlayerLook = struct {
    pub const ID = 0x0C;

    yaw: f32,
    pitch: f32,
    on_ground: bool,

    pub fn decode(reader: *StreamReader) !PlayerLook {
        return PlayerLook{
            .yaw = try reader.readFloat(f32),
            .pitch = try reader.readFloat(f32),
            .on_ground = try reader.readBoolean(),
        };
    }
};

pub const PlayerPositionAndLook = struct {
    pub const ID = 0x0D;

    x: f64,
    y: f64,
    z: f64,
    stance: f64,
    yaw: f32,
    pitch: f32,
    on_ground: bool,

    pub fn decode(reader: *StreamReader) !PlayerPositionAndLook {
        return PlayerPositionAndLook{
            .x = try reader.readFloat(f64),
            .y = try reader.readFloat(f64),
            .stance = try reader.readFloat(f64),
            .z = try reader.readFloat(f64),
            .yaw = try reader.readFloat(f32),
            .pitch = try reader.readFloat(f32),
            .on_ground = try reader.readBoolean(),
        };
    }

    pub fn encode(self: PlayerPositionAndLook, writer: io.AnyWriter) !void {
        try writer.writeInt(u64, @bitCast(self.x), .big);
        // Position of stance is different when writing than from reading
        try writer.writeInt(u64, @bitCast(self.stance), .big);
        try writer.writeInt(u64, @bitCast(self.y), .big);
        try writer.writeInt(u64, @bitCast(self.z), .big);
        try writer.writeInt(u32, @bitCast(self.yaw), .big);
        try writer.writeInt(u32, @bitCast(self.pitch), .big);
        try writer.writeByte(@intFromBool(self.on_ground));
    }
};

pub const HoldingChange = struct {
    pub const ID = 0x10;

    slot: u16,

    pub fn decode(reader: *StreamReader) !HoldingChange {
        return HoldingChange{
            .slot = try reader.readInt(u16, .big),
        };
    }
};

pub const PacketId = enum(u8) {
    keep_alive = KeepAlive.ID,
    login = Login.ID,
    handshake = Handshake.ID,
    chat_message = ChatMessage.ID,
    time_update = TimeUpdate.ID,
    entity_equipment = EntityEquipment.ID,
    spawn_position = SpawnPosition.ID,
    player_on_ground = PlayerOnGround.ID,
    player_position = PlayerPosition.ID,
    player_look = PlayerLook.ID,
    player_position_and_look = PlayerPositionAndLook.ID,
    holding_change = HoldingChange.ID,
};

pub const Packet = union(PacketId) {
    keep_alive: KeepAlive,
    login: Login,
    handshake: Handshake,
    chat_message: ChatMessage,
    time_update: TimeUpdate,
    entity_equipment: EntityEquipment,
    spawn_position: SpawnPosition,
    player_on_ground: PlayerOnGround,
    player_position: PlayerPosition,
    player_look: PlayerLook,
    player_position_and_look: PlayerPositionAndLook,
    holding_change: HoldingChange,
};

comptime {
    if (@sizeOf(Packet) > 128) {
        @compileError("Packet size over 128!");
    }
}

pub fn readPacket(reader: *StreamReader, alloc: std.mem.Allocator) !Packet {
    const packet_id = try reader.readByte();

    return switch (packet_id) {
        KeepAlive.ID => .{ .keep_alive = .{} },
        Login.ID => .{ .login = try Login.decode(reader, alloc) },
        Handshake.ID => .{ .handshake = try Handshake.decode(reader, alloc) },
        ChatMessage.ID => .{ .chat_message = try ChatMessage.decode(reader, alloc) },
        TimeUpdate.ID => .{ .time_update = try TimeUpdate.decode(reader) },
        EntityEquipment.ID => .{ .entity_equipment = try EntityEquipment.decode(reader) },
        SpawnPosition.ID => .{ .spawn_position = try SpawnPosition.decode(reader) },
        PlayerOnGround.ID => .{ .player_on_ground = try PlayerOnGround.decode(reader) },
        PlayerPosition.ID => .{ .player_position = try PlayerPosition.decode(reader) },
        PlayerLook.ID => .{ .player_look = try PlayerLook.decode(reader) },
        PlayerPositionAndLook.ID => .{ .player_position_and_look = try PlayerPositionAndLook.decode(reader) },
        HoldingChange.ID => .{ .holding_change = try HoldingChange.decode(reader) },
        else => {
            std.debug.print("Read packet ID 0x{0X:0>2} ({0d})\n", .{packet_id});
            return error.InvalidPacket;
        },
    };
}

pub fn writePacket(writer: io.AnyWriter, packet: Packet) !void {
    try writer.writeByte(@intFromEnum(packet));

    switch (packet) {
        .keep_alive => {},
        .login => try packet.login.encode(writer),
        .handshake => try packet.handshake.encode(writer),
        .chat_message => try packet.chat_message.encode(writer),
        .player_position_and_look => try packet.player_position_and_look.encode(writer),
        else => {
            std.debug.print("Write packet ID 0x{0X:0>2} ({0d})\n", .{@intFromEnum(packet)});
            return error.InvalidPacket;
        },
    }
}
