const Self = @This();

const std = @import("std");
const proto = @import("protocol.zig");

const mem = std.mem;
const net = std.net;
const posix = std.posix;

const Allocator = mem.Allocator;

const StreamReader = @import("StreamReader.zig");
const NetworkBuffer = @import("NetworkBuffer.zig");

const BUFFER_SIZE = 8_192;

allocator: Allocator,

socket: posix.socket_t,
address: net.Address,
is_connected: bool,

serverbound_buffer: NetworkBuffer,
clientbound_buffer: NetworkBuffer,

pub fn init(allocator: Allocator, socket: posix.socket_t, address: net.Address) !Self {
    const serverbound_buffer = try NetworkBuffer.init(allocator, BUFFER_SIZE);
    errdefer serverbound_buffer.deinit();

    const clientbound_buffer = try NetworkBuffer.init(allocator, BUFFER_SIZE);
    errdefer clientbound_buffer.deinit();

    return Self{
        .allocator = allocator,
        .socket = socket,
        .address = address,
        .is_connected = true,
        .serverbound_buffer = serverbound_buffer,
        .clientbound_buffer = clientbound_buffer,
    };
}

pub fn deinit(self: *Self) void {
    self.serverbound_buffer.deinit();
    if (self.is_connected) {
        self.clientbound_buffer.flushBuffer(self.socket) catch |err| {
            std.debug.print("Failed to flush connection when deinitializing: {}\n", .{err});
        };
    }
    self.clientbound_buffer.deinit();
}

pub fn readMessage(self: *Self) !proto.ServerboundPacket {
    try self.serverbound_buffer.fillBuffer(self.socket);

    const buffer_slice = self.serverbound_buffer.buffer[self.serverbound_buffer.read_head..self.serverbound_buffer.write_head];
    var reader = StreamReader.fromBuffer(buffer_slice);

    const packet = try proto.readPacket(&reader, self.allocator);

    self.serverbound_buffer.read_head += reader.head;

    return packet;
}

pub fn writeMessage(self: *Self, packet: proto.ClientboundPacket) !void {
    try proto.writePacket(self.clientbound_buffer.writer().any(), packet);
    try self.clientbound_buffer.flushBuffer(self.socket);
    // const n = try posix.write(self.socket, self.clientbound_buffer);
    // std.debug.print("Wrote {} bytes\n", .{n});
    // self.write_buffer.items
}
