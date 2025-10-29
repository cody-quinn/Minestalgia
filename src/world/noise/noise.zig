pub const OctaveNoise = @import("octave_noise.zig").OctaveNoise;

pub const OctaveNoisePerlin = @import("octave_noise.zig").OctaveNoisePerlin;
pub const OctaveNoiseSimplex = @import("octave_noise.zig").OctaveNoiseSimplex;

pub const PerlinNoise = @import("PerlinNoise.zig");
pub const SimplexNoise = @import("SimplexNoise.zig");

const std = @import("std");
const expectEqual = std.testing.expectEqual;

const Random = @import("../../jvm/Random.zig");

fn parseBinFile(comptime path: []const u8) [@embedFile(path).len / 8]f64 {
    const bin = @embedFile(path);
    var expected: [bin.len / 8]f64 = undefined;

    for (0..expected.len) |i| {
        const slice: *const [8]u8 = @ptrCast(bin[i * 8 .. i * 8 + 8]);
        const expected_value: f64 = @bitCast(std.mem.readInt(u64, slice, .big));
        expected[i] = expected_value;
    }

    return expected;
}

fn testNoise2D(comptime Noise: type, comptime path: []const u8, octaves: comptime_int, scale: f64) !void {
    var random = Random.init(0);
    const gen =
        if (octaves == 0)
            Noise.init(&random)
        else
            OctaveNoise(Noise, octaves).init(&random, 0.5);
    const expected = parseBinFile(path);

    for (0..256 * 256) |i| {
        const x: f64 = @floatFromInt(@as(i64, @intCast(i / 256)) - 128);
        const z: f64 = @floatFromInt(@as(i64, @intCast(i % 256)) - 128);
        const actual = gen.noise2D(x, z, scale, scale);
        try expectEqual(expected[i], actual);
    }
}

fn testNoise3D(comptime Noise: type, comptime path: []const u8, octaves: comptime_int, scale: f64) !void {
    var random = Random.init(0);
    const gen =
        if (octaves == 0)
            Noise.init(&random)
        else
            OctaveNoise(Noise, octaves).init(&random, 0.5);
    const expected = parseBinFile(path);

    for (0..64 * 64 * 64) |i| {
        const x: f64 = @floatFromInt(@as(i64, @intCast(i / (64 * 64))) - 32);
        const z: f64 = @floatFromInt(@as(i64, @intCast(i / 64 % 64)) - 32);
        const y: f64 = @floatFromInt(@as(i64, @intCast(i % 64)) - 32);
        const actual = gen.noise3D(x, y, z, scale, scale, scale);
        try expectEqual(expected[i], actual);
    }
}

test "Simplex Noise No Octaves" {
    try testNoise2D(SimplexNoise, "test/simplex_s0_o0.bin", 0, 100.0);
}

test "Simplex Noise 2 Octaves" {
    try testNoise2D(SimplexNoise, "test/simplex_s0_o2.bin", 2, 100.0 / 1.5);
}

test "Simplex Noise 4 Octaves" {
    try testNoise2D(SimplexNoise, "test/simplex_s0_o4.bin", 4, 100.0 / 1.5);
}

test "Simplex Noise 8 Octaves" {
    try testNoise2D(SimplexNoise, "test/simplex_s0_o8.bin", 8, 100.0 / 1.5);
}

test "Perlin Noise 2D No Octaves" {
    try testNoise2D(PerlinNoise, "test/perlin_2d_s0_o0.bin", 0, 100.0);
}

test "Perlin Noise 2D 2 Octaves" {
    try testNoise2D(PerlinNoise, "test/perlin_2d_s0_o2.bin", 2, 100.0);
}

test "Perlin Noise 2D 4 Octaves" {
    try testNoise2D(PerlinNoise, "test/perlin_2d_s0_o4.bin", 4, 100.0);
}

test "Perlin Noise 2D 16 Octaves" {
    try testNoise2D(PerlinNoise, "test/perlin_2d_s0_o16.bin", 16, 100.0);
}

test "Perlin Noise 3D No Octaves" {
    try testNoise3D(PerlinNoise, "test/perlin_3d_s0_o0.bin", 0, 100.0);
}

test "Perlin Noise 3D 2 Octaves" {
    try testNoise3D(PerlinNoise, "test/perlin_3d_s0_o2.bin", 2, 100.0);
}

test "Perlin Noise 3D 4 Octaves" {
    try testNoise3D(PerlinNoise, "test/perlin_3d_s0_o4.bin", 4, 100.0);
}

test "Perlin Noise 3D 7 Octaves" {
    try testNoise3D(PerlinNoise, "test/perlin_3d_s0_o7.bin", 7, 100.0);
}

test "Perlin Noise 3D 8 Octaves" {
    try testNoise3D(PerlinNoise, "test/perlin_3d_s0_o8.bin", 8, 100.0);
}

test "Perlin Noise 3D 16 Octaves" {
    try testNoise3D(PerlinNoise, "test/perlin_3d_s0_o16.bin", 16, 100.0);
}
