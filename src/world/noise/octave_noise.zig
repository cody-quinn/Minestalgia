const std = @import("std");
const assert = std.debug.assert;

const noise = @import("noise.zig");

const Vec2 = @import("../../vec.zig").Vec2;
const Vec3 = @import("../../vec.zig").Vec3;

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
        scale_multiplier: f64,

        pub fn init(random: *Random, scale_multiplier: f64) Self {
            var samples: [sample_count]Noise = undefined;
            for (0..sample_count) |i| {
                samples[i] = Noise.init(random);
            }

            return Self{
                .samples = samples,
                .scale_multiplier = scale_multiplier,
            };
        }

        pub fn noise2D(self: *const Self, pos: Vec2(f64), scale: Vec2(f64)) f64 {
            if (!supports_2D) @compileError("Noise type doesn't support 2D noise");

            var scale_modifier: f64 = 1.0;
            var denominator: f64 = 1.0;
            var value: f64 = 0.0;

            for (self.samples) |sample| {
                const result = sample.noise2D(pos, scale.scale(scale_modifier));
                value += result * (Noise.OCTAVE_MOD_NUMERATOR / denominator);

                scale_modifier *= self.scale_multiplier;
                denominator *= 0.5;
            }

            return value;
        }

        pub fn fill2D(self: *const Self, buffer: []f64, pos: Vec2(f64), size: Vec2(usize), scale: Vec2(f64)) void {
            assert(size.x * size.z <= buffer.len);
            for (0..size.x) |ox| {
                for (0..size.z) |oz| {
                    const idx = oz + ox * size.z;
                    const x: f64 = pos.x + @as(f64, @floatFromInt(ox));
                    const z: f64 = pos.z + @as(f64, @floatFromInt(oz));
                    buffer[idx] = self.noise2D(.init(x, z), scale);
                }
            }
        }

        pub fn noise3D(self: *const Self, pos: Vec3(f64), scale: Vec3(f64)) f64 {
            if (!supports_3D) @compileError("Noise type doesn't support 3D noise");

            var scale_modifier: f64 = 1.0;
            var denominator: f64 = 1.0;
            var value: f64 = 0.0;

            for (self.samples) |sample| {
                const result = sample.noise3D(pos, scale.scale(scale_modifier));
                value += result * (Noise.OCTAVE_MOD_NUMERATOR / denominator);

                scale_modifier *= self.scale_multiplier;
                denominator *= 0.5;
            }

            return value;
        }

        pub fn fill3D(self: *const Self, buffer: []f64, pos: Vec3(f64), size: Vec3(usize), scale: Vec3(f64)) void {
            assert(size.x * size.y * size.z <= buffer.len);
            if (@hasDecl(Noise, "fill3D")) {
                var scale_modifier: f64 = 1.0;
                for (self.samples) |sample| {
                    sample.fill3D(buffer, pos, size, scale.scale(scale_modifier), scale_modifier);
                    scale_modifier *= self.scale_multiplier;
                }
            } else {
                for (0..size.x) |ox| {
                    for (0..size.z) |oz| {
                        for (0..size.y) |oy| {
                            const idx = oy + oz * size.y + ox * size.y * size.z;
                            const x: f64 = pos.x + @as(f64, @floatFromInt(ox));
                            const y: f64 = pos.y + @as(f64, @floatFromInt(oy));
                            const z: f64 = pos.z + @as(f64, @floatFromInt(oz));
                            buffer[idx] = self.noise3D(.init(x, y, z), scale);
                        }
                    }
                }
            }
        }
    };
}
