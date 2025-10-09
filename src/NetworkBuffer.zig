const Self = @This();

const std = @import("std");

const mem = std.mem;
const net = std.net;
const posix = std.posix;

const Allocator = mem.Allocator;

allocator: Allocator,

read_head: usize,
write_head: usize,

buffer: []u8,

pub fn init(allocator: Allocator, initial_capacity: usize) !Self {
    const buffer = try allocator.alloc(u8, initial_capacity);
    errdefer allocator.free(buffer);

    return Self{
        .allocator = allocator,

        .read_head = 0,
        .write_head = 0,

        .buffer = buffer,
    };
}

pub fn deinit(self: *const Self) void {
    self.allocator.free(self.buffer);
}

pub fn fillBuffer(self: *Self, socket: posix.socket_t) !void {
    while (true) {
        try self.ensureWritable(2048);

        const buffer_slice = self.buffer[self.write_head..];
        const length = posix.read(socket, buffer_slice) catch |err| {
            if (err == error.WouldBlock) {
                return;
            }

            return err;
        };

        self.write_head += length;

        if (length == 0) {
            return error.Disconnected;
        }
    }
}

pub fn flushBuffer(self: *Self, socket: posix.socket_t) !void {
    const initial_read_head = self.read_head;
    errdefer self.read_head = initial_read_head;

    while (self.read_head < self.write_head) {
        const buffer_slice = self.buffer[self.read_head..self.write_head];
        const length = posix.write(socket, buffer_slice) catch |err| {
            if (err == error.WouldBlock) {
                return;
            }

            return err;
        };

        self.read_head += length;
    }
}

fn ensureWritable(self: *Self, length: usize) !void {
    if (self.buffer.len - self.write_head >= length) {
        return;
    }

    if (self.isOptimized()) {
        try self.expandBuffer();
    } else {
        self.optimizeBuffer();
        return self.ensureWritable(length);
    }
}

fn isOptimized(self: *Self) bool {
    return self.read_head == 0 or self.write_head == 0;
}

fn optimizeBuffer(self: *Self) void {
    std.debug.assert(self.read_head <= self.write_head);
    std.mem.copyForwards(u8, self.buffer, self.buffer[self.read_head .. self.write_head]);
    self.write_head -= self.read_head;
    self.read_head = 0;
}

fn expandBuffer(self: *Self) !void {
    const new_size = self.buffer.len * 2;
    self.buffer = self.allocator.remap(self.buffer, new_size) orelse v: {
        const new_buffer = try self.allocator.alloc(u8, new_size);
        @memcpy(new_buffer[0..self.buffer.len], self.buffer);
        self.allocator.free(self.buffer);
        break :v new_buffer;
    };
}

// Writer stuff
// TODO: Replace

const Writer = std.io.Writer(*Self, anyerror, writeFn);

fn writeFn(self: *Self, data: []const u8) !usize {
    try self.ensureWritable(data.len);
    @memcpy(self.buffer[self.write_head..self.write_head + data.len], data);
    self.write_head += data.len;
    return data.len;
}

pub fn writer(self: *Self) Writer {
    return Writer{ .context = self };
}
