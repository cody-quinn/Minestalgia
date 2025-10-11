const Self = @This();

const std = @import("std");
const math = std.math;

const Random = @import("../../jvm/Random.zig");
const PerlinNoise = @import("PerlinNoise.zig");

samples: []PerlinNoise,

pub fn init(allocator: std.mem.Allocator, sample_count: usize, random: *Random) !Self {
    var samples = try allocator.alloc(PerlinNoise, sample_count);
    for (0..sample_count) |i| {
        samples[i] = PerlinNoise.init(random);
    }
    return Self{ .samples = samples };
}

pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
    allocator.free(self.samples);
}

pub fn noise2D(self: *const Self, ix: f64, iz: f64, scale_x: f64, scale_z: f64, iexp: f64) f64 {
    var value: f64 = 0.0;
    var exp: f64 = iexp;
    for (self.samples) |sample| {
        const result = sample.noise2D(ix, iz, scale_x * exp, scale_z * exp);
        value += result * (1.0 / exp);
        exp /= 2.0;
    }
    return value;
}

pub fn noise3D(self: *const Self, ix: f64, iy: f64, iz: f64, scale_x: f64, scale_y: f64, scale_z: f64, iexp: f64) f64 {
    var value: f64 = 0.0;
    var exp: f64 = iexp;
    for (self.samples) |sample| {
        const result = sample.noise3D(ix, iy, iz, scale_x * exp, scale_y * exp, scale_z * exp);
        value += result * (1.0 / exp);
        exp /= 2.0;
    }
    return value;
}
