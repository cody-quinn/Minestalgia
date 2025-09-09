const Self = @This();

const std = @import("std");
const proto = @import("protocol.zig");

const mem = std.mem;
const net = std.net;
const posix = std.posix;

const Allocator = mem.Allocator;

const PacketBuffer = @import("main.zig").PacketBuffer;
const StreamReader = @import("StreamReader.zig");
const NetworkBuffer = @import("NetworkBuffer.zig");

const BUFFER_SIZE = 16_384;

allocator: Allocator,

socket: posix.socket_t,
address: net.Address,

serverbound_buffer: NetworkBuffer,
clientbound_buffer: PacketBuffer,

pub fn init(allocator: Allocator, socket: posix.socket_t, address: net.Address) !Self {
    const serverbound_buffer = try NetworkBuffer.init(allocator, BUFFER_SIZE);
    errdefer serverbound_buffer.deinit();

    // const write_buffer_data = try allocator.alloc(u8, BUFFER_SIZE);
    // errdefer allocator.free(write_buffer_data);
    const clientbound_buffer = PacketBuffer{};

    return Self{
        .allocator = allocator,
        .socket = socket,
        .address = address,
        .serverbound_buffer = serverbound_buffer,
        .clientbound_buffer = clientbound_buffer,
    };
}

pub fn deinit(self: *Self) void {
    self.serverbound_buffer.deinit();
}

pub fn readMessage(self: *Self) !proto.ServerboundPacket {
    try self.serverbound_buffer.fillBuffer(self.socket);

    const buffer_slice = self.serverbound_buffer.buffer[self.serverbound_buffer.read_head..self.serverbound_buffer.write_head];
    var reader = StreamReader.init(buffer_slice);

    const packet = try proto.readPacket(&reader, self.allocator);

    self.serverbound_buffer.read_head += reader.head;

    return packet;
}

pub fn writeMessage(self: *Self, packet: proto.ClientboundPacket) !void {
    try proto.writePacket(self.clientbound_buffer.writer().any(), packet);
    const n = try posix.write(self.socket, self.clientbound_buffer.items);
    std.debug.print("Wrote {} bytes\n", .{n});
    self.clientbound_buffer.reset();
    // self.write_buffer.items
}
