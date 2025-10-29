const Self = @This();

const std = @import("std");

const multiplier = 0x5DEECE66D;
const increment = 0xB;
const mask = (1 << 48) - 1;

seed: u64,

pub fn init(seed: u64) Self {
    return Self{
        .seed = (seed ^ multiplier) & mask,
    };
}

pub fn next(self: *Self, bits: comptime_int) i32 {
    comptime std.debug.assert(bits <= 48);
    self.seed = (self.seed *% multiplier +% increment) & mask;
    const result: u32 = @truncate(self.seed >> (48 - bits));
    return @bitCast(result);
}

pub fn int(self: *Self, T: type) T {
    const bits = @bitSizeOf(T);
    const SignedT = std.meta.Int(.signed, bits);

    if (bits > 64) {
        @compileError("Bit sizes greater than 64 unsupported");
    } else if (bits > 32) {
        const lhs: i64 = self.next(bits - 32);
        const rhs: i32 = self.next(32);
        const result: SignedT = @truncate((lhs <<| 32) +% rhs);
        return @bitCast(result);
    } else {
        const result: SignedT = @truncate(self.next(bits));
        return @bitCast(result);
    }
}

pub fn intBounded(self: *Self, T: type, bound: i32) T {
    const bits = @bitSizeOf(T);
    const SignedT = std.meta.Int(.signed, bits);

    const value = self.next(bits - 1);
    const m = bound - 1;
    if ((bound & m) == 0) {
        const result: SignedT = @truncate((@as(i64, bound) * @as(i64, value)) >> 31);
        return @bitCast(result);
    } else {
        var u = value;
        var r: i32 = undefined;
        while (u - b: {
            r = @mod(u, bound);
            break :b r;
        } + m < 0) {
            u = self.next(bits - 1);
        }
        return r;
    }
}

pub fn float(self: *Self, T: type) T {
    return switch (T) {
        f32 => @as(T, @floatFromInt(self.next(24))) / @as(T, 1 << 24),
        f64 => @as(T, @floatFromInt((@as(i64, @intCast(self.next(26))) << 27) + self.next(27))) / @as(T, @floatFromInt(1 << 53)),
        else => @compileError("Unsupported float type"),
    };
}

const expectEqual = std.testing.expectEqual;

test "Random i32 matches Random#nextInt" {
    const expected = [_]i32{
        -1155484576, -723955400,  1033096058,  -1690734402,
        -1557280266, 1327362106,  -1930858313, 502539523,
        -1728529858, -938301587,  1431162155,  1085665355,
        1654374947,  -1661998771, -65105105,   -73789608,
        -518907128,  99135751,    -252332814,  755814641,
    };

    var rand = Self.init(0);
    for (expected) |i| {
        try expectEqual(i, rand.int(i32));
    }
}

test "Random i32 bounded matches Random#nextInt" {
    const expected = [_]i32{
        1360, 5948, 8029, 6447,
        3515, 1053, 4491, 9761,
        8719, 2854, 1077, 2677,
        7473, 4262, 1095, 8844,
        84,   7875, 7241, 7320,
    };

    var rand = Self.init(0);
    for (expected) |i| {
        try expectEqual(i, rand.intBounded(i32, 10_000));
    }
}

test "Random i64 matches Random#nextLong" {
    const expected = [_]i64{
        -4962768465676381896, 4437113781045784766,
        -6688467811848818630, -8292973307042192125,
        -7423979211207825555, 6146794652083548235,
        7105486291024734541,  -279624296851435688,
        -2228689144322150137, -1083761183081836303,
        5072005423257391728,  2377732757510138102,
        2704323167362897208,  428667830982598836,
        -8361175665883705505, -655101936082782086,
        1927512926176735975,  -6914829020992303508,
        7577852396602278602,  -4126310024944755050,
    };

    var rand = Self.init(0);
    for (expected) |i| {
        try expectEqual(i, rand.int(i64));
    }
}

test "Random f32 matches Random#nextFloat" {
    const expected = [_]f32{
        0.73096776, 0.831441,   0.24053639, 0.6063452,
        0.6374174,  0.30905056, 0.550437,   0.1170066,
        0.59754527, 0.7815346,  0.3332184,  0.25277615,
        0.38518918, 0.61303574, 0.9848415,  0.9828195,
        0.8791825,  0.02308184, 0.94124913, 0.17597675,
    };

    var rand = Self.init(0);
    for (expected) |i| {
        try expectEqual(i, rand.float(f32));
    }
}

test "Random f64 matches Random#nextDouble" {
    const expected = [_]f64{
        0.730967787376657,   0.24053641567148587,
        0.6374174253501083,  0.5504370051176339,
        0.5975452777972018,  0.3332183994766498,
        0.3851891847407185,  0.984841540199809,
        0.8791825178724801,  0.9412491794821144,
        0.27495396603548483, 0.12889715087377673,
        0.14660165764651822, 0.023238122483889456,
        0.5467397571984656,  0.9644868606768501,
        0.10449068625097169, 0.6251463634655593,
        0.4107961954910617,  0.7763122912749325,
    };

    var rand = Self.init(0);
    for (expected) |i| {
        try expectEqual(i, rand.float(f64));
    }
}
