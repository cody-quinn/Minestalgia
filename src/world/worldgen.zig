const Random = @import("../jvm/Random.zig");
const Chunk = @import("Chunk.zig");

pub fn populateChunk(chunk: *Chunk, world_seed: u64) void {
    const seed = world_seed ^ (@as(u64, @as(u32, @bitCast(chunk.chunk_x))) <<| 32) ^ @as(u32, @bitCast(chunk.chunk_z));
    var random = Random.init(seed);

    for (0..16) |x| {
        for (0..16) |z| {
            for (0..5 + random.int(u32) % 5) |y| {
                chunk.setBlock(x, y, z, .wool, .{ .color = @enumFromInt(random.int(u32) % 16) });
            }
        }
    }
}
