const std = @import("std");
const png = @import("png.zig");
const Image = @import("Image.zig");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer std.debug.assert(!gpa.deinit());
    const alloc = gpa.allocator();
    
    var img = try Image.create(alloc, 16, 16);
    defer img.destroy(alloc);

    for (img.pixels) |*p, i| {
        if (i < 26) {
            p.* = 0xff0000ff;
        } else if (i < 165) {
            p.* = 0xff00ffff;
        } else
            p.* = 0xffffff00;
    }

    img.setPixel(5, 7, 0xff00ff00) catch unreachable;

    var cwd = std.fs.cwd();
    var file = try cwd.createFile("out.png", .{});
    defer file.close();

    var writer = file.writer();
    var buffered_writer = std.io.bufferedWriter(writer);
    var wr = buffered_writer.writer();

    std.debug.print("Starting encoding to {s}...\n", .{"out.png"});

    const written = try png.encode(img, wr, .{});
    try buffered_writer.flush();

    std.debug.print("Wrote {} bytes, saved.\n", .{written});
}

test "test" {
    var fifo = std.fifo.LinearFifo(u8, .{ .Static = 512 }).init();
    try fifo.write("\x78\x9C\x62\xF8\xFF\x9F\xE1\x3F\x00\x00\x00\xFF\xFF\x26\x7E\x06\x27");

    var zlib = try std.compress.zlib.zlibStream(std.heap.page_allocator, fifo.reader());
    var buf2: [512]u8 = undefined;
    var read = try zlib.read(&buf2);

    var buf = std.BoundedArray(u8, 512).init(0) catch unreachable;
    var adl_writer = @import("adler32.zig").writer(buf.writer());
    var adl_wr = adl_writer.writer();

    try adl_wr.writeAll(buf2[0..read]);

    std.debug.print("{any}\n", .{buf2[0..read]});
    std.debug.print("{x:0>8}\n", .{adl_writer.adler});

    try std.testing.expectEqual(@as(u32, 0x267E0627), adl_writer.adler);
}

test {
    std.testing.refAllDecls(@import("crc.zig"));
    std.testing.refAllDecls(@import("adler32.zig"));
    std.testing.refAllDecls(@import("zlib_compressor.zig"));
}