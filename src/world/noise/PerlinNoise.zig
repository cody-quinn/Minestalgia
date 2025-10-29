const Self = @This();

// Minecraft Beta 1.7.3 uses the "Improved Noise" by Ken Perlin with a single modification. The
// modification is that an additional randomly generated modifier based on world seed is added to
// the x, y, and z values.
//
// Implementation based on:
// - https://mrl.cs.nyu.edu/~perlin/noise/
// - Minecraft Beta 1.7.3 Source Code (decompiled using Ornithe)

const std = @import("std");
const math = std.math;

const Random = @import("../../jvm/Random.zig");

pub const OCTAVE_MOD_NUMERATOR: f64 = 1.0;

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

pub fn fill3D(self: *const Self, buf: []f64, ix: f64, iy: f64, iz: f64, size_x: usize, size_y: usize, size_z: usize, scale_x: f64, scale_y: f64, scale_z: f64, mul: f64) void {
    const exp: f64 = 1.0 / mul;

    var prevY: usize = 0;
    var A: usize = 0;
    var AA: usize = 0;
    var AB: usize = 0;
    var B: usize = 0;
    var BA: usize = 0;
    var BB: usize = 0;

    var r1: f64 = 0.0;
    var r2: f64 = 0.0;
    var r3: f64 = 0.0;
    var r4: f64 = 0.0;

    for (0..size_x) |ox| {
        var x = (ix + @as(f64, @floatFromInt(ox))) * scale_x + self.rx;

        const X: usize = @intCast(@as(i32, @intFromFloat(@floor(x))) & 255);
        x -= @floor(x);
        const u = fade(x);

        for (0..size_z) |oz| {
            var z = (iz + @as(f64, @floatFromInt(oz))) * scale_z + self.rz;

            const Z: usize = @intCast(@as(i32, @intFromFloat(@floor(z))) & 255);
            z -= @floor(z);
            const w = fade(z);

            for (0..size_y) |oy| {
                const idx = oy + oz * size_y + ox * size_y * size_z;
                var y = (iy + @as(f64, @floatFromInt(oy))) * scale_y + self.ry;

                const Y: usize = @intCast(@as(i32, @intFromFloat(@floor(y))) & 255);
                y -= @floor(y);
                const v = fade(y);

                if (oy == 0 or Y != prevY) {
                    prevY = Y;

                    A = self.permutations[X] + Y;
                    AA = self.permutations[A] + Z;
                    AB = self.permutations[A + 1] + Z;
                    B = self.permutations[X + 1] + Y;
                    BA = self.permutations[B] + Z;
                    BB = self.permutations[B + 1] + Z;

                    r1 = lerp(u, grad(self.permutations[AA], x, y, z), grad(self.permutations[BA], x - 1, y, z));
                    r2 = lerp(u, grad(self.permutations[AB], x, y - 1, z), grad(self.permutations[BB], x - 1, y - 1, z));
                    r3 = lerp(u, grad(self.permutations[AA + 1], x, y, z - 1), grad(self.permutations[BA + 1], x - 1, y, z - 1));
                    r4 = lerp(u, grad(self.permutations[AB + 1], x, y - 1, z - 1), grad(self.permutations[BB + 1], x - 1, y - 1, z - 1));
                }

                const res =
                    lerp(w, lerp(v, r1, r2), lerp(v, r3, r4));

                buf[idx] += res * exp;
            }
        }
    }
}

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
