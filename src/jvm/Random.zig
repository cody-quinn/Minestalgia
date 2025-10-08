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

pub fn float(self: *Self, T: type) T {
    return switch (T) {
        f32 => @as(T, @floatFromInt(self.next(24))) / @as(T, 1 << 24),
        f64 => @as(T, @floatFromInt((@as(i64, @intCast(self.next(26))) << 27) + self.next(27)))
            / @as(T, @floatFromInt(1 << 53)),
        else => @compileError("Unsupported float type"),
    };
}

const expectEqual = std.testing.expectEqual;

test "Random i32 matches Random#nextInt" {
    const expected = [_]i32{
        -1155484576,
        -723955400,
        1033096058,
        -1690734402,
        -1557280266,
    };

    var rand = Self.init(0);
    for (expected) |i| {
        try expectEqual(i, rand.int(i32));
    }
}

test "Random i64 matches Random#nextLong" {
    const expected = [_]i64{
        -4962768465676381896,
        4437113781045784766,
        -6688467811848818630,
        -8292973307042192125,
        -7423979211207825555,
    };

    var rand = Self.init(0);
    for (expected) |i| {
        try expectEqual(i, rand.int(i64));
    }
}

test "Random f32 matches Random#nextFloat" {
    const expected = [_]f32{
        0.73096776,
        0.831441,
        0.24053639,
        0.6063452,
        0.6374174,
    };

    var rand = Self.init(0);
    for (expected) |i| {
        try expectEqual(i, rand.float(f32));
    }
}

test "Random f64 matches Random#nextDouble" {
    const expected = [_]f64{
        0.730967787376657,
        0.24053641567148587,
        0.6374174253501083,
        0.5504370051176339,
        0.5975452777972018,
    };

    var rand = Self.init(0);
    for (expected) |i| {
        try expectEqual(i, rand.float(f64));
    }
}
