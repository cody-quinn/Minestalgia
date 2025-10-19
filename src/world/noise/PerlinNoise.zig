const Self = @This();

// Minecraft Beta 1.7.3 uses the "Improved Noise" by Ken Perlin with a single modification. The modification is that an
// additional randomly generated modifier based on world seed is added to the x, y, and z values.
//
// Implementation based on:
// - https://mrl.cs.nyu.edu/~perlin/noise/
// - Minecraft Beta 1.7.3 Source Code (decompiled using Ornithe)

const std = @import("std");
const math = std.math;

const Random = @import("../../jvm/Random.zig");

permutations: [512]u8,
rx: f64,
ry: f64,
rz: f64,

pub fn init(random: *Random) Self {
    // Generate some random numbers based on the seed that will always offset the position
    const rx = random.float(f64) * 256.0;
    const ry = random.float(f64) * 256.0;
    const rz = random.float(f64) * 256.0;

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
        .ry = ry,
        .rz = rz,
    };
}

pub fn noise2D(self: *const Self, ix: f64, iz: f64, scale_x: f64, scale_z: f64) f64 {
    var x = ix * scale_x + self.rx;
    var z = iz * scale_z + self.rz;

    const X: usize = @intCast(@as(i32, @intFromFloat(@floor(x))) & 255);
    const Z: usize = @intCast(@as(i32, @intFromFloat(@floor(z))) & 255);

    x -= @floor(x);
    z -= @floor(z);

    const u = fade(x);
    const w = fade(z);

    const A = self.permutations[X];
    const AA = self.permutations[A] + Z;
    const B = self.permutations[X + 1];
    const BA = self.permutations[B] + Z;

    // zig fmt: off
    return
        lerp(w, lerp(u, grad(self.permutations[AA]  , x  , 0, z),
                        grad(self.permutations[BA]  , x-1, 0, z)),
                lerp(u, grad(self.permutations[AA+1], x  , 0, z-1),
                        grad(self.permutations[BA+1], x-1, 0, z-1)));
}
// zig fmt: on

pub fn noise3D(self: *const Self, ix: f64, iy: f64, iz: f64, scale_x: f64, scale_y: f64, scale_z: f64) f64 {
    var x = ix * scale_x + self.rx;
    var y = iy * scale_y + self.ry;
    var z = iz * scale_z + self.rz;

    const X: usize = @intCast(@as(i32, @intFromFloat(@floor(x))) & 255);
    const Y: usize = @intCast(@as(i32, @intFromFloat(@floor(y))) & 255);
    const Z: usize = @intCast(@as(i32, @intFromFloat(@floor(z))) & 255);

    // Set x, y, z to the position inside the cube instead of world
    x -= @floor(x);
    y -= @floor(y);
    z -= @floor(z);

    const u = fade(x);
    const v = fade(y);
    const w = fade(z);

    const A = self.permutations[X] + Y;
    const AA = self.permutations[A] + Z;
    const AB = self.permutations[A + 1] + Z;
    const B = self.permutations[X + 1] + Y;
    const BA = self.permutations[B] + Z;
    const BB = self.permutations[B + 1] + Z;

    // zig fmt: off
    return
        lerp(w, lerp(v, lerp(u, grad(self.permutations[AA], x  , y  , z),
                                grad(self.permutations[BA], x-1, y  , z)),
                        lerp(u, grad(self.permutations[AB], x  , y-1, z),
                                grad(self.permutations[BB], x-1, y-1, z))),
                lerp(v, lerp(u, grad(self.permutations[AA+1], x  , y  , z-1),
                                grad(self.permutations[BA+1], x-1, y  , z-1)),
                        lerp(u, grad(self.permutations[AB+1], x  , y-1, z-1),
                                grad(self.permutations[BB+1], x-1, y-1, z-1))));
}
// zig fmt: on

fn fade(t: f64) f64 {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

fn lerp(t: f64, a: f64, b: f64) f64 {
    return a + t * (b - a);
}

/// Set y to 0 for 2D
fn grad(hash: i32, x: f64, y: f64, z: f64) f64 {
    const lo = hash & 15;
    const u = if (lo < 8) x else y;
    const v = if (lo < 4) y else if (lo == 12 or lo == 14) x else z;
    const uP = if ((lo & 1) == 0) u else -u;
    const vP = if ((lo & 2) == 0) v else -v;
    return uP + vP;
}
