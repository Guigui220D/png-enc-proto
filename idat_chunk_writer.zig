const std = @import("std");
const crc = @import("crc.zig");

const io = std.io;
const mem = std.mem;

/// Writer based on buffered writer that will write whole chunks of data of [buffer size]
pub fn IDATWriter(comptime buffer_size: usize, comptime WriterType: type) type {
    return struct {
        unbuffered_writer: WriterType,
        buf: [buffer_size]u8 = undefined,
        end: usize = 0,

        pub const Error = WriterType.Error;
        pub const Writer = io.Writer(*Self, Error, write);

        const Self = @This(); 

        pub fn flush(self: *Self) !void {
            try self.unbuffered_writer.writeIntBig(u32, @truncate(u32, self.end));

            var crc_writer = crc.writer(self.unbuffered_writer);
            var crc_wr = crc_writer.writer();
            try crc_wr.writeAll("IDAT");
            try crc_wr.writeAll(self.buf[0..self.end]);
            try self.unbuffered_writer.writeIntBig(u32, crc_writer.getCrc());

            self.end = 0;
        }

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        pub fn write(self: *Self, bytes: []const u8) Error!usize {
            if (self.end + bytes.len > self.buf.len) {
                try self.flush();
                if (bytes.len > self.buf.len)
                    return self.unbuffered_writer.write(bytes);
            }

            mem.copy(u8, self.buf[self.end..], bytes);
            self.end += bytes.len;
            return bytes.len;
        }
    };
}

pub fn idatWriter(underlying_stream: anytype) IDATWriter(1 << 14, @TypeOf(underlying_stream)) {
    return .{ .unbuffered_writer = underlying_stream };
}

// TODO: test idat writer
