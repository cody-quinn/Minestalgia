// Minecraft Beta 1.7.3 Packets Info:
// - https://minecraft.wiki/w/Minecraft_Wiki:Projects/wiki.vg_merge/Protocol?oldid=2769763

const std = @import("std");

const StreamReader = @import("StreamReader.zig");
const io = std.io;

const mc = @import("mc.zig");

const Chunk = @import("world/Chunk.zig");

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

pub const EquipmentSlot = enum(u16) {
    hand = 0,
    boots = 1,
    leggings = 2,
    chestplate = 3,
    helmet = 4,
};

pub const EntityEquipment = struct {
    pub const ID = 0x05;

    entity_id: u32,
    slot: EquipmentSlot,
    item_id: u16,
    metadata: u16,

    pub fn decode(reader: *StreamReader) !EntityEquipment {
        return EntityEquipment{
            .entity_id = try reader.readInt(u32, .big),
            .slot = @enumFromInt(try reader.readInt(u16, .big)),
            .item_id = try reader.readInt(u16, .big),
            .metadata = try reader.readInt(u16, .big),
        };
    }

    pub fn encode(self: EntityEquipment, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.entity_id, .big);
        try writer.writeInt(u16, @intFromEnum(self.slot), .big);
        try writer.writeInt(u16, self.item_id, .big);
        try writer.writeInt(u16, self.metadata, .big);
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

pub const EntityInteraction = struct {
    pub const ID = 0x07;

    entity_id: u32,
    target_id: u32,
    left_click: bool,

    pub fn decode(reader: *StreamReader) !EntityInteraction {
        return EntityInteraction{
            .entity_id = try reader.readInt(u32, .big),
            .target_id = try reader.readInt(u32, .big),
            .left_click = try reader.readBoolean(),
        };
    }

    pub fn encode(self: EntityInteraction, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.entity_id, .big);
        try writer.writeInt(u32, self.target_id, .big);
        try writer.writeByte(@intFromBool(self.left_click));
    }
};

pub const UpdateHealth = struct {
    pub const ID = 0x08;

    health: u16,

    pub fn decode(reader: *StreamReader) !UpdateHealth {
        return UpdateHealth{
            .health = try reader.readInt(u16, .big),
        };
    }

    pub fn encode(self: UpdateHealth, writer: io.AnyWriter) !void {
        try writer.writeInt(u16, self.health, .big);
    }
};

pub const PlayerRespawn = struct {
    pub const ID = 0x09;

    dimension: u8,

    pub fn decode(reader: *StreamReader) !PlayerRespawn {
        return PlayerRespawn{
            .dimension = try reader.readByte(),
        };
    }

    pub fn encode(self: PlayerRespawn, writer: io.AnyWriter) !void {
        try writer.writeByte(self.dimension);
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
            .x = try reader.readDouble(),
            .y = try reader.readDouble(),
            .stance = try reader.readDouble(),
            .z = try reader.readDouble(),
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
            .yaw = try reader.readFloat(),
            .pitch = try reader.readFloat(),
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
            .x = try reader.readDouble(),
            .y = try reader.readDouble(),
            .stance = try reader.readDouble(),
            .z = try reader.readDouble(),
            .yaw = try reader.readFloat(),
            .pitch = try reader.readFloat(),
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

pub const PlayerDigging = struct {
    pub const ID = 0x0E;

    status: u8,
    x: i32,
    y: u8,
    z: i32,
    face: u8,

    pub fn decode(reader: *StreamReader) !PlayerDigging {
        return PlayerDigging{
            .status = try reader.readByte(),
            .x = try reader.readInt(i32, .big),
            .y = try reader.readByte(),
            .z = try reader.readInt(i32, .big),
            .face = try reader.readByte(),
        };
    }

    pub fn encode(self: PlayerDigging, writer: io.AnyWriter) !void {
        try writer.writeByte(self.status);
        try writer.writeInt(i32, self.x, .big);
        try writer.writeByte(self.y);
        try writer.writeInt(i32, self.z, .big);
        try writer.writeByte(self.face);
    }
};

pub const PlayerPlaceBlock = struct {
    pub const ID = 0x0F;

    x: i32,
    y: u8,
    z: i32,
    direction: u8,
    item: ?mc.ItemId = null,
    amount: ?u8 = null,
    damage: ?u16 = null,

    pub fn decode(reader: *StreamReader) !PlayerPlaceBlock {
        var packet = PlayerPlaceBlock{
            .x = try reader.readInt(i32, .big),
            .y = try reader.readByte(),
            .z = try reader.readInt(i32, .big),
            .direction = try reader.readByte(),
        };

        const item = try reader.readInt(i16, .big);
        if (item < 0) {
            return packet;
        }

        packet.item = @enumFromInt(item);
        packet.amount = try reader.readByte();
        packet.damage = try reader.readInt(u16, .big);
        return packet;
    }

    pub fn encode(self: PlayerPlaceBlock, writer: io.AnyWriter) !void {
        try writer.writeInt(i32, self.x, .big);
        try writer.writeByte(self.y);
        try writer.writeInt(i32, self.z, .big);
        try writer.writeByte(self.direction);
        if (self.item) |item| {
            try writer.writeInt(u16, @intFromEnum(item), .big);
            try writer.writeByte(self.amount.?);
            try writer.writeInt(u16, self.damage.?, .big);
        } else {
            try writer.writeInt(i16, -1, .big);
        }
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

pub const UseBed = struct {
    pub const ID = 0x11;

    entity_id: u32,
    unknown: u8,
    x: i32,
    y: u8,
    z: i32,

    pub fn decode(reader: *StreamReader) !UseBed {
        return UseBed{
            .entity_id = try reader.readInt(u32, .big),
            .unknown = try reader.readByte(),
            .x = try reader.readInt(i32, .big),
            .y = try reader.readByte(),
            .z = try reader.readInt(i32, .big),
        };
    }

    pub fn encode(self: UseBed, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.entity_id, .big);
        try writer.writeByte(self.unknown);
        try writer.writeInt(i32, self.x, .big);
        try writer.writeByte(self.y);
        try writer.writeInt(i32, self.z, .big);
    }
};

pub const EntityAnimation = struct {
    pub const ID = 0x12;

    entity_id: u32,
    animation: enum(u8) {
        none = 0,
        swing = 1,
        damage = 2,
        leave_bed = 3,
        crouch = 104,
        uncrouch = 105,
    },

    pub fn decode(reader: *StreamReader) !EntityAnimation {
        return EntityAnimation{
            .entity_id = try reader.readInt(u32, .big),
            .animation = @enumFromInt(try reader.readByte()),
        };
    }

    pub fn encode(self: EntityAnimation, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.entity_id, .big);
        try writer.writeByte(@intFromEnum(self.animation));
    }
};

pub const EntityAction = struct {
    pub const ID = 0x13;

    entity_id: u32,
    action: enum(u8) {
        crouch = 1,
        uncrouch = 2,
        leave_bed = 3,
    },

    pub fn decode(reader: *StreamReader) !EntityAction {
        return EntityAction{
            .entity_id = try reader.readInt(u32, .big),
            .action = @enumFromInt(try reader.readByte()),
        };
    }
};

pub const NamedEntitySpawn = struct {
    pub const ID = 0x14;

    entity_id: u32,
    username: []const u8,
    x: i32,
    y: i32,
    z: i32,
    yaw: u8,
    pitch: u8,
    current_item: u16,

    pub fn decode(reader: *StreamReader, alloc: std.mem.Allocator) !NamedEntitySpawn {
        return NamedEntitySpawn{
            .entity_id = try reader.readInt(u32, .big),
            .username = try reader.readStringUtf16BE(alloc),
            .x = try reader.readInt(i32, .big),
            .y = try reader.readInt(i32, .big),
            .z = try reader.readInt(i32, .big),
            .yaw = try reader.readByte(),
            .pitch = try reader.readByte(),
            .current_item = try reader.readInt(u16, .big),
        };
    }

    pub fn encode(self: NamedEntitySpawn, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.entity_id, .big);
        try writeString16(self.username, writer);
        try writer.writeInt(i32, self.x, .big);
        try writer.writeInt(i32, self.y, .big);
        try writer.writeInt(i32, self.z, .big);
        try writer.writeByte(self.yaw);
        try writer.writeByte(self.pitch);
        try writer.writeInt(u16, self.current_item, .big);
    }
};

pub const ItemEntitySpawn = struct {
    pub const ID = 0x15;

    entity_id: u32,
    item: mc.ItemId,
    count: u8,
    damage: u16,
    x: i32,
    y: i32,
    z: i32,
    yaw: u8,
    pitch: u8,
    roll: u8,

    pub fn decode(reader: *StreamReader) !ItemEntitySpawn {
        return ItemEntitySpawn{
            .entity_id = try reader.readInt(u32, .big),
            .item = @enumFromInt(try reader.readInt(u16, .big)),
            .count = try reader.readByte(),
            .damage = try reader.readInt(u16, .big),
            .x = try reader.readInt(i32, .big),
            .y = try reader.readInt(i32, .big),
            .z = try reader.readInt(i32, .big),
            .yaw = try reader.readByte(),
            .pitch = try reader.readByte(),
            .roll = try reader.readByte(),
        };
    }

    pub fn encode(self: ItemEntitySpawn, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.entity_id, .big);
        try writer.writeInt(u16, @intFromEnum(self.item), .big);
        try writer.writeInt(u8, self.count, .big);
        try writer.writeInt(u16, self.damage, .big);
        try writer.writeInt(i32, self.x, .big);
        try writer.writeInt(i32, self.y, .big);
        try writer.writeInt(i32, self.z, .big);
        try writer.writeByte(self.yaw);
        try writer.writeByte(self.pitch);
        try writer.writeByte(self.roll);
    }
};

pub const ItemEntityCollect = struct {
    pub const ID = 0x16;

    collected_eid: u32,
    collector_eid: u32,

    pub fn decode(reader: *StreamReader) !ItemEntityCollect {
        return ItemEntityCollect{
            .collected_eid = try reader.readInt(u32, .big),
            .collector_eid = try reader.readInt(u32, .big),
        };
    }

    pub fn encode(self: ItemEntityCollect, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.collected_eid, .big);
        try writer.writeInt(u32, self.collector_eid, .big);
    }
};

pub const GenericEntitySpawn = struct {
    pub const ID = 0x17;

    entity_id: u32,
    type: mc.GenericEntityType,
    x: i32,
    y: i32,
    z: i32,
    unknown1: u32 = 0,
    unknown2: ?u16 = null,
    unknown3: ?u16 = null,
    unknown4: ?u16 = null,

    pub fn encode(self: GenericEntitySpawn, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.entity_id, .big);
        try writer.writeInt(u8, @intFromEnum(self.type), .big);
        try writer.writeInt(i32, self.x, .big);
        try writer.writeInt(i32, self.y, .big);
        try writer.writeInt(i32, self.z, .big);
        try writer.writeInt(u32, self.unknown1, .big);

        if (self.unknown1 > 0) {
            try writer.writeInt(u16, self.unknown2 orelse 0, .big);
            try writer.writeInt(u16, self.unknown3 orelse 0, .big);
            try writer.writeInt(u16, self.unknown4 orelse 0, .big);
        }
    }
};

pub const LivingEntitySpawn = struct {
    pub const ID = 0x18;

    entity_id: u32,
    type: mc.LivingEntityType,
    x: i32,
    y: i32,
    z: i32,
    yaw: u8,
    pitch: u8,
    // TODO: metadata

    pub fn encode(self: LivingEntitySpawn, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.entity_id, .big);
        try writer.writeInt(u8, @intFromEnum(self.type), .big);
        try writer.writeInt(i32, self.x, .big);
        try writer.writeInt(i32, self.y, .big);
        try writer.writeInt(i32, self.z, .big);
        try writer.writeByte(self.yaw);
        try writer.writeByte(self.pitch);
        try writer.writeByte(0x7F);
    }
};

pub const PaintingEntitySpawn = struct {
    pub const ID = 0x19;

    entity_id: u32,
    title: []const u8,
    x: i32,
    y: i32,
    z: i32,
    direction: i32,

    pub fn encode(self: PaintingEntitySpawn, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.entity_id, .big);
        try writeString16(self.title, writer);
        try writer.writeInt(i32, self.x, .big);
        try writer.writeInt(i32, self.y, .big);
        try writer.writeInt(i32, self.z, .big);
        try writer.writeInt(i32, self.direction, .big);
    }
};

pub const EntityDestroy = struct {
    pub const ID = 0x1D;

    entity_id: u32,

    pub fn decode(reader: *StreamReader) !EntityDestroy {
        return EntityDestroy{
            .entity_id = try reader.readInt(u32, .big),
        };
    }

    pub fn encode(self: EntityDestroy, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.entity_id, .big);
    }
};

pub const EntityMove = struct {
    pub const ID = 0x1F;

    entity_id: u32,
    delta_x: u8,
    delta_y: u8,
    delta_z: u8,

    pub fn decode(reader: *StreamReader) !EntityMove {
        return EntityMove{
            .entity_id = try reader.readInt(u32, .big),
            .delta_x = try reader.readByte(),
            .delta_y = try reader.readByte(),
            .delta_z = try reader.readByte(),
        };
    }

    pub fn encode(self: EntityMove, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.entity_id, .big);
        try writer.writeByte(self.delta_x);
        try writer.writeByte(self.delta_y);
        try writer.writeByte(self.delta_z);
    }
};

pub const EntityLook = struct {
    pub const ID = 0x20;

    entity_id: u32,
    yaw: u8,
    pitch: u8,

    pub fn decode(reader: *StreamReader) !EntityLook {
        return EntityLook{
            .entity_id = try reader.readInt(u32, .big),
            .yaw = try reader.readByte(),
            .pitch = try reader.readByte(),
        };
    }

    pub fn encode(self: EntityLook, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.entity_id, .big);
        try writer.writeByte(self.yaw);
        try writer.writeByte(self.pitch);
    }
};

pub const EntityMoveAndLook = struct {
    pub const ID = 0x21;

    entity_id: u32,
    delta_x: u8,
    delta_y: u8,
    delta_z: u8,
    yaw: u8,
    pitch: u8,

    pub fn decode(reader: *StreamReader) !EntityMoveAndLook {
        return EntityMoveAndLook{
            .entity_id = try reader.readInt(u32, .big),
            .delta_x = try reader.readByte(),
            .delta_y = try reader.readByte(),
            .delta_z = try reader.readByte(),
            .yaw = try reader.readByte(),
            .pitch = try reader.readByte(),
        };
    }

    pub fn encode(self: EntityMoveAndLook, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.entity_id, .big);
        try writer.writeByte(self.delta_x);
        try writer.writeByte(self.delta_y);
        try writer.writeByte(self.delta_z);
        try writer.writeByte(self.yaw);
        try writer.writeByte(self.pitch);
    }
};

pub const EntityTeleport = struct {
    pub const ID = 0x22;

    entity_id: u32,
    x: i32,
    y: i32,
    z: i32,
    yaw: u8,
    pitch: u8,

    pub fn decode(reader: *StreamReader) !EntityTeleport {
        return EntityTeleport{
            .entity_id = try reader.readInt(u32, .big),
            .x = try reader.readInt(i32, .big),
            .y = try reader.readInt(i32, .big),
            .z = try reader.readInt(i32, .big),
            .yaw = try reader.readByte(),
            .pitch = try reader.readByte(),
        };
    }

    pub fn encode(self: EntityTeleport, writer: io.AnyWriter) !void {
        try writer.writeInt(u32, self.entity_id, .big);
        try writer.writeInt(i32, self.x, .big);
        try writer.writeInt(i32, self.y, .big);
        try writer.writeInt(i32, self.z, .big);
        try writer.writeByte(self.yaw);
        try writer.writeByte(self.pitch);
    }
};

pub const PrepareChunk = struct {
    pub const ID = 0x032;

    chunk_x: i32,
    chunk_z: i32,
    action: enum(u8) {
        unload = 0,
        load = 1,
    },

    pub fn encode(self: PrepareChunk, writer: io.AnyWriter) !void {
        try writer.writeInt(i32, self.chunk_x, .big);
        try writer.writeInt(i32, self.chunk_z, .big);
        try writer.writeByte(@intFromEnum(self.action));
    }
};

pub const MapChunk = struct {
    pub const ID = 0x33;

    x: i32,
    y: i16,
    z: i32,
    size_x: u8 = 15,
    size_y: u8 = 127,
    size_z: u8 = 15,
    chunk: *Chunk,

    pub fn ofChunk(chunk: *Chunk) MapChunk {
        return MapChunk{
            .x = chunk.chunk_x * 16,
            .y = 0,
            .z = chunk.chunk_z * 16,
            .chunk = chunk,
        };
    }

    pub fn encode(self: MapChunk, writer: io.AnyWriter) !void {
        try writer.writeInt(i32, self.x, .big);
        try writer.writeInt(i16, self.y, .big);
        try writer.writeInt(i32, self.z, .big);
        try writer.writeByte(self.size_x);
        try writer.writeByte(self.size_y);
        try writer.writeByte(self.size_z);

        const data = try self.chunk.getCompressedData();
        try writer.writeInt(u32, @intCast(data.len), .big);
        try writer.writeAll(data);
    }
};

pub const WindowOpen = struct {
    pub const ID = 0x64;

    window_id: u8,
    window_type: enum(u8) {
        chest = 0,
        crafting_table = 1,
        furnace = 2,
        dispenser = 3,
    },
    title: []const u8,
    slots: u8,

    pub fn encode(self: WindowOpen, writer: io.AnyWriter) !void {
        try writer.writeByte(self.window_id);
        try writer.writeByte(@intFromEnum(self.window_type));
        // Write the string using string8 format
        try writer.writeInt(u16, @intCast(self.title.len), .big);
        try writer.writeAll(self.title);

        try writer.writeByte(self.slots);
    }
};

pub const WindowClose = struct {
    pub const ID = 0x65;

    window_id: u8,

    pub fn decode(reader: *StreamReader) !WindowClose {
        return WindowClose{
            .window_id = try reader.readByte(),
        };
    }

    pub fn encode(self: WindowClose, writer: io.AnyWriter) !void {
        try writer.writeByte(self.window_id);
    }
};

pub const WindowClick = struct {
    pub const ID = 0x66;

    window_id: u8,
    slot: u16,
    button: enum(u8) {
        left = 0,
        right = 1,
    },
    transaction: u16,
    shift: bool,
    item: ?mc.Item,

    pub fn decode(reader: *StreamReader) !WindowClick {
        return WindowClick{
            .window_id = try reader.readByte(),
            .slot = try reader.readInt(u16, .big),
            .button = @enumFromInt(try reader.readByte()),
            .transaction = try reader.readInt(u16, .big),
            .shift = try reader.readBoolean(),
            .item = item: {
                const item_id = try reader.readInt(u16, .big);
                break :item if (item_id != mc.Item.NO_ITEM) .{
                    .id = @enumFromInt(item_id),
                    .amount = try reader.readByte(),
                    .damage = try reader.readInt(u16, .big),
                } else null;
            },
        };
    }

    pub fn encode(self: WindowClick, writer: io.AnyWriter) !void {
        try writer.writeByte(self.window_id);
        try writer.writeInt(u16, self.slot, .big);
        try writer.writeByte(@intFromEnum(self.button));
        try writer.writeInt(u16, self.transaction, .big);
        try writer.writeByte(@intFromBool(self.shift));

        if (self.item) |item| {
            try writer.writeInt(u16, @intFromEnum(item.id), .big);
            try writer.writeByte(item.amount);
            try writer.writeInt(u16, item.damage, .big);
        } else {
            try writer.writeInt(u16, mc.Item.NO_ITEM, .big);
        }
    }
};

pub const WindowUpdate = struct {
    pub const ID = 0x67;

    window_id: u8,
    slot: u16,
    item: ?mc.Item,

    pub fn encode(self: WindowUpdate, writer: io.AnyWriter) !void {
        try writer.writeByte(self.window_id);
        try writer.writeInt(u16, self.slot, .big);

        if (self.item) |item| {
            try writer.writeInt(u16, @intFromEnum(item.id), .big);
            try writer.writeByte(item.amount);
            try writer.writeInt(u16, item.damage, .big);
        } else {
            try writer.writeInt(u16, mc.Item.NO_ITEM, .big);
        }
    }
};

/// Packet to initialize a window with it's initial set of items
pub const WindowInitialize = struct {
    pub const ID = 0x68;

    window_id: u8,
    items: []const ?mc.Item,

    pub fn encode(self: WindowInitialize, writer: io.AnyWriter) !void {
        try writer.writeByte(self.window_id);
        try writer.writeInt(u16, @intCast(self.items.len), .big);

        for (self.items) |opt_item| {
            if (opt_item) |item| {
                try writer.writeInt(u16, @intFromEnum(item.id), .big);
                try writer.writeByte(item.amount);
                try writer.writeInt(u16, item.damage, .big);
            } else {
                try writer.writeInt(u16, mc.Item.NO_ITEM, .big);
            }
        }
    }
};

pub const WindowTransactionResolved = struct {
    pub const ID = 0x6A;

    window_id: u8,
    transaction: u16,
    accepted: bool,

    pub fn encode(self: WindowTransactionResolved, writer: io.AnyWriter) !void {
        try writer.writeByte(self.window_id);
        try writer.writeInt(u16, self.transaction, .big);
        try writer.writeByte(@intFromBool(self.accepted));
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
    entity_interaction = EntityInteraction.ID,
    update_health = UpdateHealth.ID,
    player_respawn = PlayerRespawn.ID,
    player_on_ground = PlayerOnGround.ID,
    player_position = PlayerPosition.ID,
    player_look = PlayerLook.ID,
    player_position_and_look = PlayerPositionAndLook.ID,
    player_digging = PlayerDigging.ID,
    player_place_block = PlayerPlaceBlock.ID,
    holding_change = HoldingChange.ID,
    use_bed = UseBed.ID,
    entity_animation = EntityAnimation.ID,
    entity_action = EntityAction.ID,
    named_entity_spawn = NamedEntitySpawn.ID,
    item_entity_spawn = ItemEntitySpawn.ID,
    item_entity_collect = ItemEntityCollect.ID,
    generic_entity_spawn = GenericEntitySpawn.ID,
    living_entity_spawn = LivingEntitySpawn.ID,
    painting_entity_spawn = PaintingEntitySpawn.ID,
    entity_destroy = EntityDestroy.ID,
    entity_move = EntityMove.ID,
    entity_look = EntityLook.ID,
    entity_move_and_look = EntityMoveAndLook.ID,
    entity_teleport = EntityTeleport.ID,
    prepare_chunk = PrepareChunk.ID,
    map_chunk = MapChunk.ID,
    window_open = WindowOpen.ID,
    window_close = WindowClose.ID,
    window_click = WindowClick.ID,
    window_update = WindowUpdate.ID,
    window_initialize = WindowInitialize.ID,
    window_transaction_resolved = WindowTransactionResolved.ID,
};

pub const Packet = union(PacketId) {
    keep_alive: KeepAlive,
    login: Login,
    handshake: Handshake,
    chat_message: ChatMessage,
    time_update: TimeUpdate,
    entity_equipment: EntityEquipment,
    spawn_position: SpawnPosition,
    entity_interaction: EntityInteraction,
    update_health: UpdateHealth,
    player_respawn: PlayerRespawn,
    player_on_ground: PlayerOnGround,
    player_position: PlayerPosition,
    player_look: PlayerLook,
    player_position_and_look: PlayerPositionAndLook,
    player_digging: PlayerDigging,
    player_place_block: PlayerPlaceBlock,
    holding_change: HoldingChange,
    use_bed: UseBed,
    entity_animation: EntityAnimation,
    entity_action: EntityAction,
    named_entity_spawn: NamedEntitySpawn,
    item_entity_spawn: ItemEntitySpawn,
    item_entity_collect: ItemEntityCollect,
    generic_entity_spawn: GenericEntitySpawn,
    living_entity_spawn: LivingEntitySpawn,
    painting_entity_spawn: PaintingEntitySpawn,
    entity_destroy: EntityDestroy,
    entity_move: EntityMove,
    entity_look: EntityLook,
    entity_move_and_look: EntityMoveAndLook,
    entity_teleport: EntityTeleport,
    prepare_chunk: PrepareChunk,
    map_chunk: MapChunk,
    window_open: WindowOpen,
    window_close: WindowClose,
    window_click: WindowClick,
    window_update: WindowUpdate,
    window_initialize: WindowInitialize,
    window_transaction_resolved: WindowTransactionResolved,
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
        EntityInteraction.ID => .{ .entity_interaction = try EntityInteraction.decode(reader) },
        UpdateHealth.ID => .{ .update_health = try UpdateHealth.decode(reader) },
        PlayerRespawn.ID => .{ .player_respawn = try PlayerRespawn.decode(reader) },
        PlayerOnGround.ID => .{ .player_on_ground = try PlayerOnGround.decode(reader) },
        PlayerPosition.ID => .{ .player_position = try PlayerPosition.decode(reader) },
        PlayerLook.ID => .{ .player_look = try PlayerLook.decode(reader) },
        PlayerPositionAndLook.ID => .{ .player_position_and_look = try PlayerPositionAndLook.decode(reader) },
        PlayerDigging.ID => .{ .player_digging = try PlayerDigging.decode(reader) },
        PlayerPlaceBlock.ID => .{ .player_place_block = try PlayerPlaceBlock.decode(reader) },
        HoldingChange.ID => .{ .holding_change = try HoldingChange.decode(reader) },
        UseBed.ID => .{ .use_bed = try UseBed.decode(reader) },
        EntityAnimation.ID => .{ .entity_animation = try EntityAnimation.decode(reader) },
        EntityAction.ID => .{ .entity_action = try EntityAction.decode(reader) },
        NamedEntitySpawn.ID => .{ .named_entity_spawn = try NamedEntitySpawn.decode(reader, alloc) },
        ItemEntitySpawn.ID => .{ .item_entity_spawn = try ItemEntitySpawn.decode(reader) },
        ItemEntityCollect.ID => .{ .item_entity_collect = try ItemEntityCollect.decode(reader) },
        // GenericEntitySpawn
        // LivingEntitySpawn
        EntityDestroy.ID => .{ .entity_destroy = try EntityDestroy.decode(reader) },
        EntityMove.ID => .{ .entity_move = try EntityMove.decode(reader) },
        EntityLook.ID => .{ .entity_look = try EntityLook.decode(reader) },
        EntityMoveAndLook.ID => .{ .entity_move_and_look = try EntityMoveAndLook.decode(reader) },
        EntityTeleport.ID => .{ .entity_teleport = try EntityTeleport.decode(reader) },
        // PrepareChunk
        // MapChunk
        // WindowOpen
        WindowClose.ID => .{ .window_close = try WindowClose.decode(reader) },
        WindowClick.ID => .{ .window_click = try WindowClick.decode(reader) },
        // WindowUpdate
        // WindowInitialize
        // WindowTransactionResolved
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
        .time_update => try packet.time_update.encode(writer),
        .entity_equipment => try packet.entity_equipment.encode(writer),
        .spawn_position => try packet.spawn_position.encode(writer),
        .entity_interaction => try packet.entity_interaction.encode(writer),
        .update_health => try packet.update_health.encode(writer),
        .player_respawn => try packet.player_respawn.encode(writer),
        .player_position_and_look => try packet.player_position_and_look.encode(writer),
        .player_digging => try packet.player_digging.encode(writer),
        .player_place_block => try packet.player_place_block.encode(writer),
        .use_bed => try packet.use_bed.encode(writer),
        .entity_animation => try packet.entity_animation.encode(writer),
        .named_entity_spawn => try packet.named_entity_spawn.encode(writer),
        .item_entity_spawn => try packet.item_entity_spawn.encode(writer),
        .item_entity_collect => try packet.item_entity_collect.encode(writer),
        .generic_entity_spawn => try packet.generic_entity_spawn.encode(writer),
        .living_entity_spawn => try packet.living_entity_spawn.encode(writer),
        .prepare_chunk => try packet.prepare_chunk.encode(writer),
        .map_chunk => try packet.map_chunk.encode(writer),
        .entity_destroy => try packet.entity_destroy.encode(writer),
        .entity_move => try packet.entity_move.encode(writer),
        .entity_look => try packet.entity_look.encode(writer),
        .entity_move_and_look => try packet.entity_move_and_look.encode(writer),
        .entity_teleport => try packet.entity_teleport.encode(writer),
        .window_open => try packet.window_open.encode(writer),
        .window_close => try packet.window_close.encode(writer),
        .window_click => try packet.window_click.encode(writer),
        .window_update => try packet.window_update.encode(writer),
        .window_initialize => try packet.window_initialize.encode(writer),
        .window_transaction_resolved => try packet.window_transaction_resolved.encode(writer),
        else => {
            std.debug.print("Write packet ID 0x{0X:0>2} ({0d})\n", .{@intFromEnum(packet)});
            return error.InvalidPacket;
        },
    }
}
