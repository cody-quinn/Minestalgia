const std = @import("std");

const mc = @import("../mc.zig");

const Random = @import("../jvm/Random.zig");
const PerlinNoise = @import("noise/PerlinNoise.zig");
const OctaveNoise = @import("noise/OctaveNoise.zig");
const Chunk = @import("Chunk.zig");

pub fn populateChunk(chunk: *Chunk, world_seed: u64) void {
    var random = Random.init(world_seed);
    const noise = OctaveNoise.init(std.heap.page_allocator, 6, &random) catch {
        std.debug.print("Failed to create octave noise generator", .{});
        return;
    };
    defer noise.deinit(std.heap.page_allocator);

    for (0..16) |x| {
        for (0..16) |z| {
            const scale = 684.412 / 10_000.0;
            const rx: f64 = @floatFromInt(@as(i32, @intCast(x)) + chunk.chunk_x * 16);
            const rz: f64 = @floatFromInt(@as(i32, @intCast(z)) + chunk.chunk_z * 16);
            const raw_height = noise.noise2D(rx, rz, scale, scale, 2.0);

            const height: i32 = @intFromFloat(@max(@min((raw_height + 15) * 2, 48.0), 2.0));
            var y: i32 = height;
            while (y > 0) : (y -= 1) {
                var block: mc.BlockId = .stone;
                if (y == height) {
                    block = .grass;
                } else if (y > height - 3) {
                    block = .dirt;
                }
                chunk.setBlock(x, y, z, block, null);
            }

            for (1..62) |i| {
                if (noise.noise3D(rx + 8375, @floatFromInt(i), rz + 9582, scale, scale, scale, 1.0) > 3) {
                    chunk.setBlock(x, i, z, .air, null);
                }
            }

            chunk.setBlock(x, 0, z, .glass, null);
        }
    }

    chunk.recompressChunk() catch {
        std.debug.print("Failed to compress chunk {}, {}.\n", .{
            chunk.chunk_x,
            chunk.chunk_z,
        });
    };
}
