const std = @import("std");
const io = std.io;

pub fn Adler32Writer(comptime WriterType: type) type {
    return struct {
        raw_writer: WriterType,
        adler: u32 = 1,

        pub const Error = WriterType.Error;
        pub const Writer = io.Writer(*Self, Error, write);

        const Self = @This();

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        pub fn write(self: *Self, bytes: []const u8) Error!usize {
            var s1 = self.adler & 0xffff;
            var s2 = (self.adler >> 16) & 0xffff;

            const amt = try self.raw_writer.write(bytes);
            for (bytes[0..amt]) |b| {
                s1 = (s1 + b) % 65521;
                s2 = (s2 + s1) % 65521;
            }
            self.adler = (s2 << 16) + s1; 

            return amt;
        }
    };
}

// TODO: rename to crcWriter
pub fn writer(underlying_stream: anytype) Adler32Writer(@TypeOf(underlying_stream)) {
    return .{ .raw_writer = underlying_stream };
}