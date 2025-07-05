const std = @import("std");

const net = std.net;
const posix = std.posix;

const Thread = std.Thread;
const Allocator = std.mem.Allocator;

const proto = @import("protocol.zig");

const BUFFER_SIZE = 16_384;

const PacketBuffer = struct {
    data: [BUFFER_SIZE]u8 = undefined,
    items: []u8 = &[_]u8{},
    pos: usize = 0,

    const Writer = std.io.Writer(*PacketBuffer, anyerror, write);
    const Reader = std.io.Reader(*PacketBuffer, anyerror, read);

    fn write(self: *PacketBuffer, data: []const u8) !usize {
        if (self.items.len + data.len > self.data.len) {
            return error.EndOfBuffer;
        }

        @memcpy(self.data[self.items.len..][0..data.len], data);
        self.items = self.data[0 .. self.items.len + data.len];
        return data.len;
    }

    fn writer(self: *PacketBuffer) Writer {
        return .{ .context = self };
    }

    fn read(self: *PacketBuffer, buffer: []u8) !usize {
        const remainingBytes = self.items.len - self.pos;
        const len = @min(remainingBytes, buffer.len);

        if (len < 0) {
            return error.EndOfBuffer;
        }

        @memcpy(buffer[0..len], self.items[self.pos .. self.pos + len]);
        self.pos += len;
        return len;
    }

    fn reader(self: *PacketBuffer) Reader {
        return .{ .context = self };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Making an arena allocator for packets
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const alloc = arena.allocator();
    _ = alloc;

    // var buf = PacketBuffer{};

    // var foo = [_]u16{ 'C', 'a', 't' };
    // const packet = proto.ClientboundLogin{
    //     .entity_id = 14,
    //     .username = .{
    //         .length = 3,
    //         .value = &foo,
    //     },
    //     .map_seed = 0,
    //     .dimension = 0,
    // };

    // try proto.writePacket(buf.writer().any(), .{ .login = packet });

    // printBytes(buf.items);

    // const p = try proto.readPacket(buf.reader().any(), alloc);

    // std.debug.print("{}", .{p});

    const address = try net.Address.parseIp("127.0.0.1", 25565);

    var server = try Server.init(gpa.allocator(), 1023);
    defer server.deinit();
    try server.run(address);
}

const Server = struct {
    allocator: Allocator,

    polls: []posix.pollfd,

    connected: usize,
    clients: []Client,
    client_polls: []posix.pollfd,

    fn init(allocator: Allocator, max_clients: usize) !Server {
        const polls = try allocator.alloc(posix.pollfd, max_clients + 1);
        errdefer allocator.free(polls);

        const clients = try allocator.alloc(Client, max_clients);
        errdefer allocator.free(clients);

        return Server{
            .allocator = allocator,
            .polls = polls,
            .connected = 0,
            .clients = clients,
            .client_polls = polls[1..],
        };
    }

    fn run(self: *Server, address: net.Address) !void {
        const tpe: u32 = posix.SOCK.STREAM | posix.SOCK.NONBLOCK;
        const protocol = posix.IPPROTO.TCP;
        const listener = try posix.socket(address.any.family, tpe, protocol);
        defer posix.close(listener);

        try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try posix.bind(listener, &address.any, address.getOsSockLen());
        try posix.listen(listener, 128);

        self.polls[0] = posix.pollfd{
            .fd = listener,
            .revents = 0,
            .events = posix.POLL.IN,
        };

        while (true) {
            std.debug.print("Looped\n", .{});

            _ = try posix.poll(self.polls[0 .. self.connected + 1], -1);

            // Accept new clients
            if (self.polls[0].revents != 0) {
                self.acceptClients(listener) catch |err| {
                    std.debug.print("Error accepting client:\n{}\n", .{err});
                };
            }

            // Handle new messages from clients
            var i: usize = 0;
            while (i < self.connected) {
                const revents = self.client_polls[i].revents;
                if (revents == 0) {
                    i += 1;
                    continue;
                }

                const client = &self.clients[i];
                if (revents & posix.POLL.IN == posix.POLL.IN) {
                    // Read message
                    var buffer: [1024]u8 = undefined;
                    while (true) {
                        const length = posix.read(client.socket, &buffer) catch |err| {
                            if (err == error.WouldBlock) {
                                i += 1;
                                break;
                            }

                            std.debug.print("Error reading from client:\n{}\n", .{err});
                            break;
                        };

                        if (length == 0) {
                            self.removeClient(i);
                            break;
                        }

                        printBytes(buffer[0..length]);
                    }
                }
            }

            // Handle broadcasting messages to clients
        }
    }

    fn acceptClients(self: *Server, listener: posix.socket_t) !void {
        while (true) {
            self.acceptClient(listener) catch |err| switch (err) {
                error.WouldBlock => return,
                else => return err,
            };
        }
    }

    fn acceptClient(self: *Server, listener: posix.socket_t) !void {
        var address: net.Address = undefined;
        var address_len: posix.socklen_t = @sizeOf(net.Address);

        const socket = try posix.accept(listener, &address.any, &address_len, posix.SOCK.NONBLOCK);
        const client = try Client.init(self.allocator, socket, address);

        self.clients[self.connected] = client;
        self.client_polls[self.connected] = posix.pollfd{
            .fd = socket,
            .revents = 0,
            .events = posix.POLL.IN,
        };

        self.connected += 1;

        std.debug.print("Client {} connected\n", .{address});
    }

    fn removeClient(self: *Server, index: usize) void {
        var client = self.clients[index];
        posix.close(client.socket);
        client.deinit();

        const last_index = self.connected - 1;
        self.clients[index] = self.clients[last_index];
        self.client_polls[index] = self.client_polls[last_index];

        self.connected = last_index;
    }

    fn deinit(self: *Server) void {
        self.allocator.free(self.polls);
        self.allocator.free(self.clients);
    }
};

const Client = struct {
    allocator: Allocator,

    socket: posix.socket_t,
    address: net.Address,

    read_buffer: []u8,

    fn init(allocator: Allocator, socket: posix.socket_t, address: net.Address) !Client {
        const read_buffer = try allocator.alloc(u8, BUFFER_SIZE);
        errdefer allocator.free(read_buffer);

        return Client{
            .allocator = allocator,
            .socket = socket,
            .address = address,
            .read_buffer = read_buffer,
        };
    }

    fn readMessage(self: *Client) !proto.ClientboundPacket {
        _ = self;
    }

    fn writeMessage(self: *Client, packet: proto.ServerboundPacket) !void {
        _ = self;
        _ = packet;
    }

    fn deinit(self: *Client) void {
        self.allocator.free(self.read_buffer);
    }
};

// pub const Reader = struct {
//     buf: []u8,

//     pos: usize = 0,
//     start: usize = 0,

//     socket: posix.socket_t,

//     pub fn readByte() !void {
//         //
//     }
// };

fn readMessage(socket: posix.socket_t, buf: []u8) ![]u8 {
    var pos: usize = 0;
    while (true) {
        const n = try posix.read(socket, buf[pos..]);
        if (n == 0) {
            return error.Closed;
        }
        const end = pos + n;
        const index = std.mem.indexOfScalar(u8, buf[pos..end], 0) orelse {
            pos = end;
            continue;
        };
        return buf[0 .. pos + index];
    }
}

fn writeMessage(allocator: Allocator, socket: posix.socket_t, messages: []const []const u8) !void {
    var vec = try allocator.alloc(posix.iovec_const, messages.len + 1);
    for (messages, 0..) |msg, i| {
        vec[i] = .{ .len = msg.len, .base = msg.ptr };
    }
    vec[messages.len] = .{ .len = 1, .base = &[1]u8{0} };

    try writeAllVectorized(socket, vec);
}

fn writeAllVectorized(socket: posix.socket_t, vec: []posix.iovec_const) !void {
    var i: usize = 0;
    while (true) {
        var n = try posix.writev(socket, vec[i..]);
        while (n >= vec[i].len) {
            n -= vec[i].len;
            i += 1;
            if (i >= vec.len) return;
        }
        vec[i].base += n;
        vec[i].len -= n;
    }
}

fn printBytes(bytes: []const u8) void {
    std.debug.print("Length: {}", .{bytes.len});
    for (bytes, 0..) |b, i| {
        if (i % 16 == 0) {
            std.debug.print("\n{x:0>4}: ", .{i});
        }
        std.debug.print("{x:0>2} ", .{b});
    }
    std.debug.print("(EOF) \n", .{});
}
