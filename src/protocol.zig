pub const Direction = enum {
    Universal,
    Serverbound,
    Clientbound,

    fn is_serverbound(self: Direction) bool {
        return self != .Clientbound;
    }

    fn is_clientbound(self: Direction) bool {
        return self != .Serverbound;
    }
};

fn PacketMeta(comptime Packet: type, packet_id: u8, packet_direction: Direction) type {
    _ = Packet;
    return struct {
        pub fn id() u8 {
            return packet_id;
        }

        pub fn direction() Direction {
            return packet_direction;
        }
    };
}

pub const String16 = struct {
    length: u16,
};

// Packets
pub const KeepAlive = struct {
    pub usingnamespace PacketMeta(@This(), 0x00, .Universal);
};

pub const ServerboundLogin = struct {
    protocol_version: u32,
    username: [16]u8,
    pub usingnamespace PacketMeta(@This(), 0x01, .Serverbound);
};

pub const ClientboundLogin = struct {
    entity_id: u32,
    username: [16]u8,
    pub usingnamespace PacketMeta(@This(), 0x01, .Clientbound);
};

pub const ServerboundHandshake = struct {
    username: String16,
    pub usingnamespace PacketMeta(@This(), 0x02, .Serverbound);
};

pub const ClientboundHandshake = struct {
    connection_hash: String16,
    pub usingnamespace PacketMeta(@This(), 0x02, .Clientbound);
};

pub const ClientboundPlayerPositionAndLook = struct {
    x: f64,
    y: f64,
    stance: f64,
    z: f64,
    yaw: f32,
    pitch: f32,
    on_ground: bool,

    pub usingnamespace PacketMeta(@This(), 0x0D, .Clientbound);
};

pub const ServerboundPacket = union(enum) {
    keep_alive: KeepAlive,
    login: ServerboundLogin,
    handshake: ServerboundHandshake,
};

pub const ClientboundPacket = union(enum) {
    keep_alive: KeepAlive,
    login: ClientboundLogin,
    handshake: ClientboundHandshake,
    player_position_and_look: ClientboundPlayerPositionAndLook,
};
