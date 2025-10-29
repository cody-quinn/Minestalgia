pub const OctaveNoise = @import("octave_noise.zig").OctaveNoise;

pub const PerlinNoise = @import("PerlinNoise.zig");
pub const SimplexNoise = @import("SimplexNoise.zig");

const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

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
    const gen = OctaveNoise(Noise, octaves).init(&random, 0.5);
    const expected = parseBinFile(path);
    var actual: [256 * 256]f64 = undefined;
    gen.fill2D(&actual, .splat(-128), .splat(256), .splat(scale));
    try expectEqualSlices(f64, &expected, &actual);
}

fn testNoise3D(comptime Noise: type, comptime path: []const u8, octaves: comptime_int, scale: f64) !void {
    var random = Random.init(0);
    const gen = OctaveNoise(Noise, octaves).init(&random, 0.5);
    const expected = parseBinFile(path);
    var actual: [64 * 64 * 64]f64 = undefined;
    gen.fill3D(&actual, .splat(-32), .splat(64), .splat(scale));
    try expectEqualSlices(f64, &expected, &actual);
}

test "Simplex Noise No Octaves" {
    var random = Random.init(0);
    const gen = SimplexNoise.init(&random);
    const expected = parseBinFile("test/simplex_s0_o0.bin");
    var actual: [256 * 256]f64 = undefined;
    for (0 .. 256 * 256) |i| {
        const x: f64 = @floatFromInt(@as(i64, @intCast(i / 256)) - 128);
        const z: f64 = @floatFromInt(@as(i64, @intCast(i % 256)) - 128);
        actual[i] = gen.noise2D(.init(x, z), .splat(100.0));
    }
    try expectEqualSlices(f64, &expected, &actual);
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

test "Perlin Noise 2D 1/No Octaves" {
    try testNoise2D(PerlinNoise, "test/perlin_2d_s0_o0.bin", 1, 100.0);
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

test "Perlin Noise 3D 1/No Octaves" {
    try testNoise3D(PerlinNoise, "test/perlin_3d_s0_o0.bin", 1, 100.0);
}

test "Perlin Noise 3D 2 Octaves" {
    try testNoise3D(PerlinNoise, "test/perlin_3d_s0_o2.bin", 2, 100.0);
}

test "Perlin Noise 3D 4 Octaves" {
    try testNoise3D(PerlinNoise, "test/perlin_3d_s0_o4.bin", 4, 100.0);
}

test "Perlin Noise 3D 8 Octaves" {
    try testNoise3D(PerlinNoise, "test/perlin_3d_s0_o8.bin", 8, 100.0);
}

test "Perlin Noise 3D 16 Octaves" {
    try testNoise3D(PerlinNoise, "test/perlin_3d_s0_o16.bin", 16, 100.0);
}
