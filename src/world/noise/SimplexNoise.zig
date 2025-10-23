const Self = @This();

// Minecraft Beta 1.7.3 uses "Simplex Noise" by Ken Perlin for some things, like generating
// temperature and humidity, which then goes on to influence the biome and terrain generation.
// Similarly to the Perlin Noise generation it has the modification of storing an x and z offset
// that will be used. It also uses a table for the gradient for some reason? This I'm still confused
// about :P
//
// Implementation based on:
// - https://github.com/SRombauts/SimplexNoise
// - Minecraft Beta 1.7.3 Source Code (decompiled using Ornithe)

const std = @import("std");
const math = std.math;

const Random = @import("../../jvm/Random.zig");

pub const OCTAVE_MOD_NUMERATOR: f64 = 0.55;

const gradient_table = [12][3]f64{
    .{ 1, 1, 0 },   .{ -1, 1, 0 },  .{ 1, -1, 0 },
    .{ -1, -1, 0 }, .{ 1, 0, 1 },   .{ -1, 0, 1 },
    .{ 1, 0, -1 },  .{ -1, 0, -1 }, .{ 0, 1, 1 },
    .{ 0, -1, 1 },  .{ 0, 1, -1 },  .{ 0, -1, -1 },
};

const f2: f64 = 0.5 * (@sqrt(3.0) - 1.0);
const g2: f64 = (3.0 - @sqrt(3.0)) / 6.0;

permutations: [512]u8,
rx: f64,
rz: f64,

pub fn init(random: *Random) Self {
    const rx = random.float(f64) * 256.0;
    const rz = random.float(f64) * 256.0;
    _ = random.float(f64);

    var permutations: [512]u8 = undefined;

    for (0..256) |i| {
        permutations[i] = @truncate(i);
    }

    // Shuffle the permutation table around in the same way MC does
    for (0..256) |i| {
        const idx = @as(usize, @intCast(random.intBounded(i32, @intCast(256 - i)))) + i;
        const value = permutations[i];
        permutations[i] = permutations[idx];
        permutations[idx] = value;
        permutations[i + 256] = permutations[i];
    }

    return Self{
        .permutations = permutations,
        .rx = rx,
        .rz = rz,
    };
}

pub fn noise2D(self: *const Self, ix: f64, iz: f64, scale_x: f64, scale_z: f64) f64 {
    const x = ix * scale_x + self.rx;
    const z = iz * scale_z + self.rz;

    const s = (x + z) * f2;
    const xs = floor(x + s);
    const zs = floor(z + s);

    const t = @as(f64, @floatFromInt(xs + zs)) * g2;
    const x0 = x - (@as(f64, @floatFromInt(xs)) - t);
    const z0 = z - (@as(f64, @floatFromInt(zs)) - t);

    const i: usize = if (x0 > z0) 1 else 0;
    const j: usize = if (x0 > z0) 0 else 1;

    const x1 = x0 - @as(f64, @floatFromInt(i)) + g2;
    const z1 = z0 - @as(f64, @floatFromInt(j)) + g2;
    const x2 = x0 - 1.0 + 2.0 * g2;
    const z2 = z0 - 1.0 + 2.0 * g2;

    const x_hash: usize = @intCast(xs & 0xFF);
    const z_hash: usize = @intCast(zs & 0xFF);

    const gi0: u8 = self.permutations[x_hash + self.permutations[z_hash]] % 12;
    const gi1: u8 = self.permutations[x_hash + i + self.permutations[z_hash + j]] % 12;
    const gi2: u8 = self.permutations[x_hash + 1 + self.permutations[z_hash + 1]] % 12;

    const n0 = extract(x0, z0, gi0);
    const n1 = extract(x1, z1, gi1);
    const n2 = extract(x2, z2, gi2);

    return 70.0 * (n0 + n1 + n2);
}

fn extract(x: f64, z: f64, gradient_indice: usize) f64 {
    var t: f64 = 0.5 - x * x - z * z;
    const n: f64 = if (t < 0.0) 0.0 else b: {
        t *= t;
        break :b t * t * grad(gradient_table[gradient_indice], x, z);
    };
    return n;
}

fn grad(indice: [3]f64, x: f64, z: f64) f64 {
    return indice[0] * x + indice[1] * z;
}

fn floor(t: f64) i32 {
    const v: i32 = @intFromFloat(t);
    return if (t > 0.0) v else v - 1;
}
