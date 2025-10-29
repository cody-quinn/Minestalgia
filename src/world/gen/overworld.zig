// Resources used in the development of overworld generation:
// - https://pixelbrush.dev/beta-wiki/worlds/generation.html
// - Minecraft Beta 1.7.3 Source Code (decompiled using Ornithe)

const std = @import("std");
const math = std.math;
const clamp = math.clamp;
const assert = std.debug.assert;

const mc = @import("../../mc.zig");
const noise = @import("../noise/noise.zig");

const Random = @import("../../jvm/Random.zig");
const Chunk = @import("../Chunk.zig");

const Vec2 = @import("../../vec.zig").Vec2;
const Vec3 = @import("../../vec.zig").Vec3;

const dm_width = 5;
const dm_height = 17;
const dm_depth = 5;

// Terrain Noise
var lo_noise: noise.OctaveNoise(noise.PerlinNoise, 16) = undefined;
var hi_noise: noise.OctaveNoise(noise.PerlinNoise, 16) = undefined;
var main_noise: noise.OctaveNoise(noise.PerlinNoise, 8) = undefined;

var sand_noise: noise.OctaveNoise(noise.PerlinNoise, 4) = undefined;
var stone_noise: noise.OctaveNoise(noise.PerlinNoise, 4) = undefined;

var scale_noise: noise.OctaveNoise(noise.PerlinNoise, 10) = undefined;
var depth_noise: noise.OctaveNoise(noise.PerlinNoise, 16) = undefined;

// Features Noise
var forest_noise: noise.OctaveNoise(noise.PerlinNoise, 8) = undefined;

// Biome Noise
var temp_noise: noise.OctaveNoise(noise.SimplexNoise, 4) = undefined;
var humidity_noise: noise.OctaveNoise(noise.SimplexNoise, 4) = undefined;
var variation_noise: noise.OctaveNoise(noise.SimplexNoise, 2) = undefined;

pub fn initializeGenerator(world_seed: u64) void {
    var random = Random.init(world_seed);

    lo_noise = .init(&random, 0.5);
    hi_noise = .init(&random, 0.5);
    main_noise = .init(&random, 0.5);
    sand_noise = .init(&random, 0.5);
    stone_noise = .init(&random, 0.5);
    scale_noise = .init(&random, 0.5);
    depth_noise = .init(&random, 0.5);
    forest_noise = .init(&random, 0.5);

    random = Random.init(world_seed * 9871);
    temp_noise = .init(&random, 0.25);

    random = Random.init(world_seed * 39811);
    humidity_noise = .init(&random, 1.0 / 3.0);

    random = Random.init(world_seed * 543321);
    variation_noise = .init(&random, 0.5882352941176471);
}

pub fn generateChunk(chunk: *Chunk) void {
    generateChunkTerrain(chunk);
    generateChunkBiomes(chunk);

    chunk.recompressChunk() catch {
        std.debug.print("Failed to compress chunk {}, {}.\n", .{
            chunk.chunk_x,
            chunk.chunk_z,
        });
    };
}

fn generateChunkTerrain(chunk: *Chunk) void {
    // Get a heightmap.
    var density_map: [dm_width * dm_height * dm_depth]f64 = undefined;
    populateDensityMap(&density_map, chunk.chunk_x, chunk.chunk_z);

    for (0..4) |x| {
        for (0..4) |z| {
            for (0..16) |y| {
                var c000 = density_map[(x * dm_depth + z) * dm_height + y];
                var c010 = density_map[(x * dm_depth + z + 1) * dm_height + y];
                var c100 = density_map[((x + 1) * dm_depth + z) * dm_height + y];
                var c110 = density_map[((x + 1) * dm_depth + z + 1) * dm_height + y];

                const c001 = (density_map[(x * dm_depth + z) * dm_height + y + 1] - c000) * 0.125;
                const c011 = (density_map[(x * dm_depth + z + 1) * dm_height + y + 1] - c010) * 0.125;
                const c101 = (density_map[((x + 1) * dm_depth + z) * dm_height + y + 1] - c100) * 0.125;
                const c111 = (density_map[((x + 1) * dm_depth + z + 1) * dm_height + y + 1] - c110) * 0.125;

                for (0..8) |interp_y| {
                    var c00 = c000;
                    var c10 = c010;

                    const c00_step = (c100 - c000) * 0.25;
                    const c10_step = (c110 - c010) * 0.25;

                    for (0..4) |interp_x| {
                        var c0 = c00;

                        const c0_step = (c10 - c00) * 0.25;

                        for (0..4) |interp_z| {
                            const local_x = interp_x + x * 4;
                            const local_y = interp_y + y * 8;
                            const local_z = interp_z + z * 4;

                            var block: mc.BlockId = .air;

                            if (local_y < 64) {
                                block = .water_still;
                            }

                            if (c0 > 0.0) {
                                block = .stone;
                            }

                            chunk.data[local_x <<| 11 | local_z <<| 7 | local_y] = @intFromEnum(block);

                            c0 += c0_step;
                        }

                        c00 += c00_step;
                        c10 += c10_step;
                    }

                    c000 += c001;
                    c010 += c011;
                    c100 += c101;
                    c110 += c111;
                }
            }
        }
    }
}

fn generateChunkBiomes(chunk: *Chunk) void {
    _ = chunk;
}

fn populateDensityMap(densities: []f64, chunk_x: i32, chunk_z: i32) void {
    const xz_mul = 16 / dm_width;

    var scale_noise_buf: [dm_width * dm_depth]f64 = undefined;
    var depth_noise_buf: [dm_width * dm_depth]f64 = undefined;
    var main_noise_buf: [dm_width * dm_height * dm_depth]f64 = undefined;
    var lo_noise_buf: [dm_width * dm_height * dm_depth]f64 = undefined;
    var hi_noise_buf: [dm_width * dm_height * dm_depth]f64 = undefined;

    {
        // Fill the buffers
        const scale: f64 = 684.412;
        const pos = Vec3(f64).init(@floatFromInt(chunk_x * 4), 0.0, @floatFromInt(chunk_z * 4));
        const size = Vec3(usize).init(dm_width, dm_height, dm_depth);

        scale_noise.fill2D(&scale_noise_buf, pos.toVec2(), size.toVec2(), .splat(1.121));
        depth_noise.fill2D(&depth_noise_buf, pos.toVec2(), size.toVec2(), .splat(200.0));
        main_noise.fill3D(&main_noise_buf, pos, size, .init(scale / 80.0, scale / 160.0, scale / 80.0));
        lo_noise.fill3D(&lo_noise_buf, pos, size, .splat(scale));
        hi_noise.fill3D(&hi_noise_buf, pos, size, .splat(scale));
    }

    for (0..dm_width) |x| {
        const local_x: i32 = @intCast(x * xz_mul + xz_mul / 2);
        const world_x = chunk_x * 16 + local_x;

        for (0..dm_depth) |z| {
            const z_index = x * dm_depth + z;

            const local_z: i32 = @intCast(z * xz_mul + xz_mul / 2);
            const world_z = chunk_z * 16 + local_z;

            const temp, var humidity = getTempHumidity(world_x, world_z);
            humidity *= temp;
            humidity = 1.0 - humidity;
            humidity = (humidity * humidity) * (humidity * humidity);
            humidity = 1.0 - humidity;

            // Calculate scale
            var scale = (scale_noise_buf[z_index] + 256.0) / 512.0;
            scale *= humidity;
            scale = clamp(scale, 0.0, 1.0);

            // Calculate depth
            var depth = depth_noise_buf[z_index] / 8000.0;
            if (depth < 0.0) {
                depth = -depth * 0.3;
            }

            depth = depth * 3.0 - 2.0;
            if (depth < 0.0) {
                depth /= 2.0;
                if (depth < -1.0) {
                    depth = -1.0;
                }

                depth /= 1.4;
                depth /= 2.0;
                scale = 0.0;
            } else {
                if (depth > 1.0) {
                    depth = 1.0;
                }

                depth /= 8.0;
            }

            scale += 0.5;

            depth = depth * @as(f64, dm_height) / 16.0;
            depth = @as(f64, dm_height) / 2.0 + depth * 4.0;

            for (0..dm_height) |y| {
                const y_index = x * dm_height * dm_depth + z * dm_height + y;

                const lo = lo_noise_buf[y_index] / 512.0;
                const hi = hi_noise_buf[y_index] / 512.0;
                const main = (main_noise_buf[y_index] / 10.0 + 1.0) / 2.0;

                var value: f64 =
                    if (main < 0.0) lo else if (main > 1.0) hi else lo + (hi - lo) * main;

                var mod: f64 = (@as(f64, @floatFromInt(y)) - depth) * 12.0 / scale;
                if (mod < 0.0) {
                    mod *= 4.0;
                }

                value -= mod;

                if (y > dm_height - 4) {
                    const q = @as(f64, @floatFromInt(y - (dm_height - 4))) / 3.0;
                    value = value * (1.0 - q) + -10.0 * q;
                }

                densities[y_index] = value;
            }
        }
    }
}

fn getTempHumidity(ix: i32, iz: i32) struct { f64, f64 } {
    const x: f64 = @floatFromInt(ix);
    const z: f64 = @floatFromInt(iz);

    const variation_scale = 0.25 / 1.5;
    const variation = variation_noise.noise2D(.init(x, z), .splat(variation_scale)) * 1.1 + 0.5;

    const temp_scale = 0.025 / 1.5;
    var temp = temp_noise.noise2D(.init(x, z), .splat(temp_scale)) * 0.15 + 0.7;
    temp *= 1.0 - 0.01;
    temp += variation * 0.01;
    temp = clamp(1.0 - (1.0 - temp) * (1.0 - temp), 0.0, 1.0);

    const humidity_scale = 0.05 / 1.5;
    var humidity = humidity_noise.noise2D(.init(x, z), .splat(humidity_scale)) * 0.15 + 0.5;
    humidity *= 1.0 - 0.002;
    humidity += variation * 0.002;
    humidity = clamp(humidity, 0.0, 1.0);

    return .{ temp, humidity };
}
