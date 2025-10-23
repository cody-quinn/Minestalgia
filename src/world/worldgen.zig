// Lots of this was figured out thanks to Pixel Brush's beta wiki, though I did a bit before that
// resource existed!
// - https://pixelbrush.dev/beta-wiki/worlds/generation.html

const std = @import("std");
const assert = std.debug.assert;

const mc = @import("../mc.zig");
const noise = @import("noise/noise.zig");

const Random = @import("../jvm/Random.zig");
const Chunk = @import("Chunk.zig");

var initialized: bool = false;

var min_limit_noise: noise.OctaveNoise(noise.PerlinNoise, 16) = undefined;
var max_limit_noise: noise.OctaveNoise(noise.PerlinNoise, 16) = undefined;
var main_noise: noise.OctaveNoise(noise.PerlinNoise, 8) = undefined;

/// Unknown purpose. Initialized to move random along
var f_6739260: noise.OctaveNoise(noise.PerlinNoise, 4) = undefined;

var surface_noise: noise.OctaveNoise(noise.PerlinNoise, 4) = undefined;
var scale_noise: noise.OctaveNoise(noise.PerlinNoise, 10) = undefined;
var depth_noise: noise.OctaveNoise(noise.PerlinNoise, 16) = undefined;

var forest_noise: noise.OctaveNoise(noise.PerlinNoise, 8) = undefined;

pub fn populateChunk(chunk: *Chunk, world_seed: u64) void {
    if (!initialized) initializeNoise(world_seed);

    // Get a heightmap.
    // Size of heightmap is width * height * depth. Depth is always 5.
    var heightmap: [5 * 17 * 5]f64 = undefined;
    populateHeightmap(&heightmap, chunk.chunk_x, chunk.chunk_z);

    for (0..16) |x| {
        for (0..16) |z| {
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

fn populateHeightmap(heightmap: []f64, chunk_x: i32, chunk_z: i32) void {
    const width = 5;
    const height = 17;
    const depth = 5;

    var depth_noise_buf: [width * depth]f64 = undefined;
    var main_noise_buf: [width * height * depth]f64 = undefined;
    var min_limit_noise_buf: [width * height * depth]f64 = undefined;
    var max_limit_noise_buf: [width * height * depth]f64 = undefined;

    {
        // Fill the buffers
        const scale_xz: f64 = 684.412;
        const scale_y: f64 = 684.412;
        const x: f64 = @floatFromInt(chunk_x * 4);
        const z: f64 = @floatFromInt(chunk_z * 4);

        depth_noise.fill2D(&depth_noise_buf, x, z, width, depth, 200.0, 200.0);
        main_noise.fill3D(&main_noise_buf, x, 0.0, z, width, height, depth, scale_xz / 80.0, scale_y / 160.0, scale_xz / 80.0);
        min_limit_noise.fill3D(&min_limit_noise_buf, x, 0.0, z, width, height, depth, scale_xz, scale_y, scale_xz);
        max_limit_noise.fill3D(&max_limit_noise_buf, x, 0.0, z, width, height, depth, scale_xz, scale_y, scale_xz);
    }

    const k14 = 16 / width;

    for (0..width) |x| {
        const m16 = x * k14 + k14 / 2;

        for (0..depth) |z| {
            const o18 = z * k14 + k14 / 2;

            for (0..height) |y| {
                // const ix: i32 = (chunk_x * 4) + @as(i32, @intCast(x));
                // const iz: i32 = (chunk_z * 4) + @as(i32, @intCast(z));

                _ = y;
                _ = m16;
                _ = o18;
            }
        }
    }

    _ = heightmap;
}

fn initializeNoise(world_seed: u64) void {
    var random = Random.init(world_seed);

    min_limit_noise = .init(&random, 1.0);
    max_limit_noise = .init(&random, 1.0);
    main_noise = .init(&random, 1.0);
    f_6739260 = .init(&random, 1.0);
    surface_noise = .init(&random, 1.0);
    scale_noise = .init(&random, 1.0);
    depth_noise = .init(&random, 1.0);
    forest_noise = .init(&random, 1.0);

    initialized = true;
}
