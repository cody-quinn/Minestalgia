const Random = @import("../jvm/Random.zig");
const PerlinNoise = @import("noise/PerlinNoise.zig");
const Chunk = @import("Chunk.zig");

pub fn populateChunk(chunk: *Chunk, world_seed: u64) void {
    var random = Random.init(world_seed);
    const noise = PerlinNoise.init(&random);

    for (0..16) |x| {
        for (0..16) |z| {
            chunk.setBlock(x, 0, z, .glass, null);
            for (1..128) |y| {
                const rx = @as(i32, @intCast(x)) + chunk.chunk_x * 16;
                const rz = @as(i32, @intCast(z)) + chunk.chunk_z * 16;

                const value = noise.noise3D(
                    @as(f64, @floatFromInt(rx)),
                    @as(f64, @floatFromInt(y)),
                    @as(f64, @floatFromInt(rz)),
                    .{
                        // Scale
                        .x = 684.412 / 10_000.0,
                        .y = 684.412 / 10_000.0,
                        .z = 684.412 / 10_000.0,
                    },
                );

                if (value > 0.4) {
                    chunk.setBlock(x, y, z, .stone, null);
                }
            }
        }
    }
}
