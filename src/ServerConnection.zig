const Self = @This();

const std = @import("std");
const proto = @import("protocol.zig");

const mem = std.mem;
const net = std.net;
const posix = std.posix;

const Allocator = mem.Allocator;

const PacketBuffer = @import("main.zig").PacketBuffer;
const StreamReader = @import("StreamReader.zig");

const BUFFER_SIZE = 16_384;

allocator: Allocator,

socket: posix.socket_t,
address: net.Address,

serverbound_buffer: []u8,
serverbound_buffer_read_head: usize,
serverbound_buffer_write_head: usize,

clientbound_buffer: PacketBuffer,

pub fn init(allocator: Allocator, socket: posix.socket_t, address: net.Address) !Self {
    const serverbound_buffer = try allocator.alloc(u8, BUFFER_SIZE);
    errdefer allocator.free(serverbound_buffer);

    // const write_buffer_data = try allocator.alloc(u8, BUFFER_SIZE);
    // errdefer allocator.free(write_buffer_data);
    const clientbound_buffer = PacketBuffer{};

    return Self{
        .allocator = allocator,
        .socket = socket,
        .address = address,
        .serverbound_buffer = serverbound_buffer,
        .serverbound_buffer_read_head = 0,
        .serverbound_buffer_write_head = 0,
        .clientbound_buffer = clientbound_buffer,
    };
}

pub fn readMessage(self: *Self) !proto.ServerboundPacket {
    while (true) {
        const length = posix.read(self.socket, self.serverbound_buffer[self.serverbound_buffer_write_head..]) catch |err| {
            if (err == error.WouldBlock) {
                break;
            }
            // TODO: Handle error.WouldBlock case
            std.debug.print("Error reading from client:\n{}\n", .{err});
            break;
        };

        self.serverbound_buffer_write_head += length;

        if (length == 0) {
            return error.ClientDisconnected;
        }
    }

    var reader = StreamReader.init(self.serverbound_buffer);
    reader.head = self.serverbound_buffer_read_head;

    const packet = proto.readPacket(&reader, self.allocator) catch |err| {
        if (err == error.InvalidPacket) {
            std.debug.print("Got unknown packet\n", .{});
            _ = try posix.write(self.socket, &.{0x00});
        }
        return error.EndOfStream;
    };

    self.serverbound_buffer_read_head = reader.head;

    return packet;
}

pub fn writeMessage(self: *Self, packet: proto.ClientboundPacket) !void {
    try proto.writePacket(self.clientbound_buffer.writer().any(), packet);
    const n = try posix.write(self.socket, self.clientbound_buffer.items);
    std.debug.print("Wrote {} bytes\n", .{n});
    self.clientbound_buffer.reset();
    // self.write_buffer.items
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.serverbound_buffer);
}
