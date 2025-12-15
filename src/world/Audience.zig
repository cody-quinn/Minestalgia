//! Special type of list containing players that automatically handles the removal of disconnected
//! players.

const std = @import("std");
const mem = std.mem;

const Player = @import("../Player.zig");
const protocol = @import("../protocol.zig");

const Self = @This();

players: std.ArrayList(*const Player),

pub fn init(allocator: mem.Allocator) Self {
    const players = std.ArrayList(*const Player).init(allocator);
    return Self{ .players = players };
}

pub fn deinit(self: Self) void {
    self.players.deinit();
}

pub fn insert(self: *Self, player: *const Player) !void {
    try self.players.append(player);
}

pub fn remove(self: *Self, player: *const Player) void {
    const idx = for (self.players.items, 0..) |target, i| {
        if (target == player) {
            break i;
        }
    } else {
        return;
    };

    self.players.swapRemove(idx);
}

pub fn broadcastMessage(self: *Self, packet: protocol.Packet) !void {
    // TODO: Improve with less naive approach to broadcasting
    for (self.players.items) |player| {
        try player.connection.writeMessage(packet);
    }
}
