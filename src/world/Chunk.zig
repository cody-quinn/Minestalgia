const Self = @This();

const std = @import("std");

const Allocator = std.mem.Allocator;

const Player = @import("../Player.zig");

const mc = @import("../mc.zig");

const blocks_per_chunk = 16 * 16 * 128;

viewers: std.ArrayList(*Player),

chunk_x: i32,
chunk_y: i32,

blocks: [blocks_per_chunk]mc.BlockId,
block_metadata: [blocks_per_chunk / 2]u8,
block_lighting: [blocks_per_chunk / 2]u8,
sky_lighting: [blocks_per_chunk / 2]u8,

pub fn init(allocator: Allocator, chunk_x: i32, chunk_y: i32) !Self {
    const viewers = try std.ArrayList(*Player).initCapacity(allocator, 64);
    errdefer viewers.deinit();

    return Self{
        .viewers = viewers,
        .chunk_x = chunk_x,
        .chunk_y = chunk_y,
        .blocks = .{ .air } ** blocks_per_chunk,
        .block_metadata = .{ 0 } ** (blocks_per_chunk / 2),
        .block_lighting = .{ 0 } ** (blocks_per_chunk / 2),
        .sky_lighting = .{ 0 } ** (blocks_per_chunk / 2),
    };
}

pub fn setBlock(self: *Self, x: anytype, y: anytype, z: anytype, block: mc.BlockId, opt_metadata: ?mc.BlockMetadata) void {
    const idx = coordsToIndex(x, y, z);
    const odd = idx & 1;
    const metadata: u8 = if (opt_metadata) |metadata| @bitCast(metadata) else 0;
    self.blocks[idx] = block;

    {
        // Set the metadata
        const base = self.block_metadata[idx / 2];
        const lhs = base & (@as(u8, 0xF) <<| (odd * 4));
        const rhs = metadata <<| ((odd ^ 1) * 4);
        self.block_metadata[idx / 2] = lhs | rhs;
    }

    for (self.viewers.items) |viewer| {
        _ = viewer;
    }
}

fn coordsToIndex(x: anytype, y: anytype, z: anytype) usize {
    const rx: usize = @intCast(x);
    const ry: usize = @intCast(y);
    const rz: usize = @intCast(z);
    return ry + rz * 128 + rx * 128 * 16;
}
