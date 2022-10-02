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

        // TODO: find why doing it an other way segfaults
        /// Inits a zlibcompressor
        /// This is made this way because not doing it in place segfaults for a reason
        pub fn init(self: *Self, alloc: std.mem.Allocator, stream: WriterType) !void {
            self.raw_writer = stream;
            self.adler32_writer = adler32.writer(self.raw_writer);
            self.compressor = try defl.compressor(alloc, self.adler32_writer.writer(), .{});
        }

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
            self.compressor.deinit();
            // Write the checksum
            var wr = self.raw_writer;
            try wr.writeIntBig(u32, self.adler32_writer.adler);
        }
    };
}

test "zlib compressor" {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const alloc = gpa.allocator();

    var list = std.ArrayList(u8).init(alloc);

    //var zlib = try zlibCompressor(alloc, list.writer());
    var zlib: ZlibCompressor(@TypeOf(list.writer())) = undefined;
    try zlib.init(alloc, list.writer());

    try zlib.begin();
    try zlib.writer().writeAll("\x63\xF8\xFF\xFF\x3F\x00");
    try zlib.end();

    // TODO: test zlib compressor

    list.deinit();

    const leaks = gpa.deinit();
    try std.testing.expect(!leaks);
}