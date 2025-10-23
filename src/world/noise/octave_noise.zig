const std = @import("std");
const assert = std.debug.assert;

const Random = @import("../../jvm/Random.zig");

pub fn OctaveNoise(Noise: type, sample_count: comptime_int) type {
    const supports_2D = @hasDecl(Noise, "noise2D");
    const supports_3D = @hasDecl(Noise, "noise3D");

    if (!supports_2D and !supports_3D) {
        @compileError("Noise type must support either 2D or 3D noise");
    }

    return struct {
        const Self = @This();

        samples: [sample_count]Noise,
        initial_scale_modifier: f64,

        pub fn init(random: *Random, initial_scale_modifier: f64) Self {
            var samples: [sample_count]Noise = undefined;
            for (0..sample_count) |i| {
                samples[i] = Noise.init(random);
            }

            return Self{
                .samples = samples,
                .initial_scale_modifier = initial_scale_modifier,
            };
        }

        pub fn noise2D(self: *const Self, ix: f64, iz: f64, scale_x: f64, scale_z: f64) f64 {
            if (!supports_2D) @compileError("Noise type doesn't support 2D noise");

            var scale_modifier: f64 = self.initial_scale_modifier;
            var denominator: f64 = 1.0;
            var value: f64 = 0.0;

            for (self.samples) |sample| {
                const result = sample.noise2D(ix, iz, scale_x * scale_modifier, scale_z * scale_modifier);
                value += result * (Noise.OCTAVE_MOD_NUMERATOR / denominator);
                scale_modifier /= 2.0;
                denominator /= 2.0;
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
            if (!supports_3D) @compileError("Noise type doesn't support 3D noise");

            var scale_modifier: f64 = self.initial_scale_modifier;
            var denominator: f64 = 1.0;
            var value: f64 = 0.0;

            for (self.samples) |sample| {
                const result = sample.noise3D(ix, iy, iz, scale_x * scale_modifier, scale_y * scale_modifier, scale_z * scale_modifier);
                value += result * (Noise.OCTAVE_MOD_NUMERATOR / denominator);
                scale_modifier /= 2.0;
                denominator /= 2.0;
            }

            return value;
        }

        pub fn fill3D(self: *const Self, buffer: []f64, ix: f64, iy: f64, iz: f64, size_x: usize, size_y: usize, size_z: usize, scale_x: f64, scale_y: f64, scale_z: f64) void {
            assert(size_x * size_y * size_z <= buffer.len);
            for (0..size_x) |ox| {
                for (0..size_y) |oy| {
                    for (0..size_z) |oz| {
                        const idx = ox * size_z * size_y + oy * size_z + oz;
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
