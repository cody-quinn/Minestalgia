const Self = @This();

const std = @import("std");

const Allocator = std.mem.Allocator;

const Player = @import("../Player.zig");

const mc = @import("../mc.zig");

const blocks_per_chunk = 16 * 16 * 128;

viewers: std.ArrayList(*Player),

chunk_x: i32,
chunk_z: i32,

data: [81_920]u8 = [_]u8{0} ** 81_920,

// Cache compressed version of chunk
compressed_data: std.ArrayList(u8),
compressed_valid: bool,

pub fn init(allocator: Allocator, chunk_x: i32, chunk_z: i32) !Self {
    const viewers = try std.ArrayList(*Player).initCapacity(allocator, 64);
    errdefer viewers.deinit();

    const compressed_data = try std.ArrayList(u8).initCapacity(allocator, 2048);
    errdefer compressed_data.deinit();

    var self = Self{
        .viewers = viewers,
        .chunk_x = chunk_x,
        .chunk_z = chunk_z,
        .compressed_data = compressed_data,
        .compressed_valid = false,
    };

    @memset(&self.data, 0);
    @memset(self.blockLighting(), 0xFF);
    @memset(self.skyLighting(), 0xFF);

    return self;
}

pub fn deinit(self: *const Self) void {
    self.viewers.deinit();
    self.compressed_data.deinit();
}

pub fn setBlock(self: *Self, x: anytype, y: anytype, z: anytype, block: mc.BlockId, opt_metadata: ?mc.BlockMetadata) void {
    const idx = coordsToIndex(x, y, z);
    const odd = idx & 1;
    const metadata: u8 = if (opt_metadata) |metadata| @bitCast(metadata) else 0;
    self.blocks()[idx] = (block);

    {
        // Set the metadata
        const base = self.blockMetadata()[idx / 2];
        const lhs = base & (@as(u8, 0xF) <<| (odd * 4));
        const rhs = metadata <<| ((odd ^ 1) * 4);
        self.blockMetadata()[idx / 2] = lhs | rhs;
    }

    self.compressed_valid = false;

    for (self.viewers.items) |viewer| {
        _ = viewer;
    }
}

pub fn getBlock(self: *Self, x: anytype, y: anytype, z: anytype) mc.BlockId {
    const idx = coordsToIndex(x, y, z);
    return self.blocks[idx];
}

pub fn getBlockMetadata(self: *Self, x: anytype, y: anytype, z: anytype) mc.BlockMetadata {
    const idx = coordsToIndex(x, y, z);
    const odd = idx & 1;
    const metadata: u8 = (self.block_metadata[idx / 2] >> (4 * odd)) & 0xF;
    return @bitCast(metadata);
}

pub fn recompressChunk(self: *Self) !void {
    self.compressed_data.clearRetainingCapacity();
    var ingress = std.io.fixedBufferStream(&self.data);
    try std.compress.zlib.compress(ingress.reader(), self.compressed_data.writer(), .{});
    self.compressed_valid = true;
}

pub fn getCompressedData(self: *Self) ![]u8 {
    if (!self.compressed_valid) {
        try self.recompressChunk();
    }

    return self.compressed_data.items;
}

inline fn coordsToIndex(x: anytype, y: anytype, z: anytype) usize {
    const rx: usize = @intCast(x);
    const ry: usize = @intCast(y);
    const rz: usize = @intCast(z);
    return ry + rz * 128 + rx * 128 * 16;
}

inline fn blocks(self: *Self) []mc.BlockId {
    return @ptrCast(self.data[0..32_768]);
}

inline fn blockMetadata(self: *Self) []u8 {
    return self.data[32_768..49_152];
}

inline fn blockLighting(self: *Self) []u8 {
    return self.data[49_152..65_536];
}

inline fn skyLighting(self: *Self) []u8 {
    return self.data[65_536..81_920];
}
