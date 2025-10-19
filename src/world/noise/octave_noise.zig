const std = @import("std");
const assert = std.debug.assert;

const PerlinNoise = @import("noise.zig").PerlinNoise;
const Random = @import("../../jvm/Random.zig");

pub fn OctaveNoise(sample_count: comptime_int) type {
    return struct {
        const Self = @This();

        samples: [sample_count]PerlinNoise,

        pub fn init(random: *Random) Self {
            var samples: [sample_count]PerlinNoise = undefined;
            for (0..sample_count) |i| {
                samples[i] = PerlinNoise.init(random);
            }
            return Self{ .samples = samples };
        }

        pub fn noise2D(self: *const Self, ix: f64, iz: f64, scale_x: f64, scale_z: f64) f64 {
            var value: f64 = 0.0;
            var exp: f64 = 1.0;
            for (self.samples) |sample| {
                const result = sample.noise2D(ix, iz, scale_x * exp, scale_z * exp);
                value += result * (1.0 / exp);
                exp /= 2.0;
            }
            return value;
        }

        pub fn fill2D(self: *const Self, buffer: []f64, ix: f64, iz: f64, size_x: usize, size_z: usize, scale_x: f64, scale_z: f64) void {
            assert(size_x * size_z <= buffer.len);
            for (0..size_x) |ox| {
                for (0..size_z) |oz| {
                    const idx = ox * size_z + oz;
                    const x: f64 = ix + @as(f64, @floatFromInt(ox));
                    const z: f64 = iz + @as(f64, @floatFromInt(oz));
                    buffer[idx] = self.noise2D(x, z, scale_x, scale_z);
                }
            }
        }

        pub fn noise3D(self: *const Self, ix: f64, iy: f64, iz: f64, scale_x: f64, scale_y: f64, scale_z: f64) f64 {
            var value: f64 = 0.0;
            var exp: f64 = 1.0;
            for (self.samples) |sample| {
                const result = sample.noise3D(ix, iy, iz, scale_x * exp, scale_y * exp, scale_z * exp);
                value += result * (1.0 / exp);
                exp /= 2.0;
            }
            return value;
        }

        pub fn fill3D(self: *const Self, buffer: []f64, ix: f64, iy: f64, iz: f64, size_x: usize, size_y: usize, size_z: usize, scale_x: f64, scale_y: f64, scale_z: f64) void {
            assert(size_x * size_y * size_z <= buffer.len);
            for (0..size_x) |ox| {
                for (0..size_y) |oy| {
                    for (0..size_z) |oz| {
                        const idx = ox * size_z * size_y + oy * size_y + oz;
                        const x: f64 = ix + @as(f64, @floatFromInt(ox));
                        const y: f64 = iy + @as(f64, @floatFromInt(oy));
                        const z: f64 = iz + @as(f64, @floatFromInt(oz));
                        buffer[idx] = self.noise3D(x, y, z, scale_x, scale_y, scale_z);
                    }
                }
            }
        }
    };
}
