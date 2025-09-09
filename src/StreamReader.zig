const std = @import("std");
const posix = std.posix;

const mem = std.mem;

const Self = @This();

pub const Error = error { EndOfStream };
pub const ErrorAllocating = Error || std.mem.Allocator.Error; // For functions that can allocate memory

stream: []const u8,
head: usize,

pub fn init(stream: []const u8) Self {
    return Self{
        .stream = stream,
        .head = 0,
    };
}

pub fn readByte(self: *Self) Error!u8 {
    return self.readInt(u8, .big);
}

pub fn readInt(self: *Self, comptime T: type, endian: std.builtin.Endian) Error!T {
    if (self.head + @sizeOf(T) > self.stream.len) {
        return Error.EndOfStream;
    }

    const value = mem.readInt(T, @constCast(@ptrCast(self.stream[self.head .. self.head + @sizeOf(T)])), endian);
    self.head += @sizeOf(T);
    return value;
}

pub fn readFloat(self: *Self, comptime T: type) Error!T {
    if (self.head + @sizeOf(T) > self.stream.len) {
        return Error.EndOfStream;
    }

    const value: T = @as(*T, @constCast(@ptrCast(&self.stream[self.head .. self.head + @sizeOf(T)]))).*;
    self.head += @sizeOf(T);
    return value;
}

pub fn readBoolean(self: *Self) Error!bool {
    return try self.readInt(u8, .big) != 0;
}

/// Reads UTF-8 strings
pub fn readStringUtf8(self: *Self, alloc: mem.Allocator) ErrorAllocating![]const u8 {
    const length = try self.readInt(u16, .big);
    errdefer self.head -= @sizeOf(u16);

    if (self.head + length > self.stream.len) {
        return Error.EndOfStream;
    }

    const string = try alloc.alloc(u8, length);
    errdefer alloc.free(string);
    @memcpy(string, self.stream[self.head .. self.head + length]);
    return string;
}

/// Reads UTF-16 BE string, converting it to and returning the much more universal UTF-8
pub fn readStringUtf16BE(self: *Self, alloc: mem.Allocator) ErrorAllocating![]const u8 {
    const headReset = self.head;
    errdefer self.head = headReset;
    const sourceLength = try self.readInt(u16, .big);

    if (self.head + sourceLength * 2 > self.stream.len) {
        return Error.EndOfStream;
    }

    var pos: usize = 0;
    var length: usize = sourceLength;
    var string = try alloc.alloc(u8, length);
    errdefer alloc.free(string);

    for (0..sourceLength) |_| {
        const char: u16 = self.readInt(u16, .big) catch unreachable;
        const bytes: u8 = if (char <= 0x7F) 1 else if (char <= 0x77F) 2 else 3;

        if (pos + bytes > length) {
            length = @min(length * 2, sourceLength * 3);
            string = try alloc.realloc(string, length);
        }

        switch (bytes) {
            1 => string[pos]  = @intCast(char),
            2 => {
                string[pos]     = @intCast(char >> 6 & 0b000_11111 | 0b110_00000);
                string[pos + 1] = @intCast(char      & 0b00_111111 | 0b10_000000);
            },
            3 => {
                string[pos]     = @intCast(char >> 12 & 0b0000_1111 | 0b1110_0000);
                string[pos + 1] = @intCast(char >> 6  & 0b00_111111 | 0b10_000000);
                string[pos + 2] = @intCast(char       & 0b00_111111 | 0b10_000000);
            },
            else => unreachable,
        }

        pos += bytes;
    }

    // TODO: Figure out if this is ok to do
    string.len = pos;
    return string;
}

pub fn seek(self: *Self, pos: usize) Error!void {
    if (pos >= self.stream.len) {
        return Error.EndOfStream;
    }

    self.head = pos;
}

pub fn skip(self: *Self, by: usize) Error!void {
    return self.seek(self.head + by);
}
