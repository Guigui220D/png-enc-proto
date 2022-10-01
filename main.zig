const std = @import("std");
const png = @import("png.zig");
const Image = @import("Image.zig");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer std.debug.assert(!gpa.deinit());
    const alloc = gpa.allocator();
    
    var img = try Image.create(alloc, 8, 8);
    defer img.destroy(alloc);

    img.setPixel(1, 1, 0xff00ffff) catch unreachable;
    img.setPixel(0, 1, 0xff000000) catch unreachable;
    img.setPixel(1, 0, 0x00ff00ff) catch unreachable;

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

test {
    std.testing.refAllDecls(@import("crc.zig"));
    std.testing.refAllDecls(@import("adler32.zig"));
    std.testing.refAllDecls(@import("zlib_compressor.zig"));
}