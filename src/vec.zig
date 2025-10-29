pub fn Vec2(comptime T: type) type {
    return struct {
        const Self = @This();

        x: T,
        z: T,

        pub fn toVec3(self: Self, y: T) Vec3(T) {
            return Vec3(T){
                .x = self.x,
                .y = y,
                .z = self.z,
            };
        }

        pub fn init(x: T, z: T) Vec2(T) {
            return Self {
                .x = x,
                .z = z,
            };
        }

        pub fn splat(v: T) Vec2(T) {
            return Self.init(v, v);
        }

        pub fn scale(self: Self, v: T) Vec2(T) {
            return Self.init(self.x * v, self.z * v);
        }
    };
}

pub fn Vec3(comptime T: type) type {
    return struct {
        const Self = @This();

        x: T,
        y: T,
        z: T,

        pub fn toVec2(self: Self) Vec2(T) {
            return Vec2(T){
                .x = self.x,
                .z = self.z,
            };
        }

        pub fn init(x: T, y: T, z: T) Vec3(T) {
            return Self {
                .x = x,
                .y = y,
                .z = z,
            };
        }

        pub fn splat(v: T) Vec3(T) {
            return Self.init(v, v, v);
        }

        pub fn scale(self: Self, v: T) Vec3(T) {
            return Self.init(self.x * v, self.y * v, self.z * v);
        }
    };
}
