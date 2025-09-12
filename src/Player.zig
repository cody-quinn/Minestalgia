const Self = @This();

const std = @import("std");
const proto = @import("protocol.zig");

const mem = std.mem;

const Server = @import("Server.zig");
const ServerConnection = @import("ServerConnection.zig");

connection: *ServerConnection,

username_str: [16]u8 = [_]u8{0} ** 16,
username_len: usize = 0,

eid: u32,
x: f64 = 0.0,
y: f64 = 0.0,
z: f64 = 0.0,

pub fn init(connection: *ServerConnection, eid: u32) Self {
    return Self{
        .connection = connection,
        .eid = eid,
    };
}

pub fn username(self: *Self) []const u8 {
    return self.username_str[0..self.username_len];
}
