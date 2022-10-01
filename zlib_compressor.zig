const std = @import("std");
const adler32 = @import("adler32.zig");
const io = std.io;
const defl = std.compress.deflate;

/// Zlib Compressor (Deflate) with a writer interface
pub fn ZlibCompressor(comptime WriterType: type) type {
    return struct {
        raw_writer: WriterType,
        adler32_writer: adler32.Adler32Writer(WriterType),
        compressor: defl.Compressor(adler32.Adler32Writer(WriterType).Writer),

        const Self = @This();

        /// Begins a zlib block with the header
        pub fn begin(self: *Self) !void {
            // TODO: customize
            const cmf = 0x78; // 8 = deflate, 7 = log(window size (see std.compress.deflate)) - 8
            const flg = blk: {
                var ret: u8 = 0b11000000; // 11 = max compression
                const rem: usize = (@intCast(usize, cmf) * 256) + ret % 31;
                ret += 31 - @truncate(u8, rem);
                break :blk ret;
            };
            // write the header
            var wr = self.raw_writer;
            try wr.writeByte(cmf);
            try wr.writeByte(flg);
        }

        /// Gets a writer for the compressor
        pub fn writer(self: *Self) @TypeOf(self.compressor).Writer {
            return self.compressor.writer();
        }

        /// Ends a zlib block with the checksum
        pub fn end(self: *Self) !void {
            try self.compressor.flush();
            // Write the checksum
            var wr = self.raw_writer;
            try wr.writeIntBig(u32, self.adler32_writer.adler);
        }
    };
}

/// Makes a zlibcompressor from a writer
pub fn zlibCompressor(alloc: std.mem.Allocator, underlying_stream: anytype) !ZlibCompressor(@TypeOf(underlying_stream)) {
    var ret: ZlibCompressor(@TypeOf(underlying_stream)) = undefined;
    ret.raw_writer = underlying_stream;
    ret.adler32_writer = adler32.writer(ret.raw_writer);
    ret.compressor = try defl.compressor(alloc, ret.adler32_writer.writer(), .{});
    return ret;
}

test "zlib compressor" {
    // TODO: safety on segfaults here
    var gpa: std.heap.GeneralPurposeAllocator(.{ .safety = false }) = .{};
    const alloc = gpa.allocator();

    var list = std.ArrayList(u8).init(alloc);
    defer list.deinit();

    var zlib = try zlibCompressor(alloc, list.writer());

    try zlib.begin();
    try zlib.writer().writeAll("\x63\xF8\xFF\xFF\x3F\x00");
    try zlib.end();

    // TODO: test zlib compressor

    _ = gpa.deinit();
    //try std.testing.expect(!leaks);
}