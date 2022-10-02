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

    const written = try png.encode(wr, alloc, img, .{});
    try buffered_writer.flush();

    std.debug.print("Wrote {} bytes, saved.\n", .{written});

    // TODO: figure out why the file doesn't render in the browser
}

test {
    std.testing.refAllDecls(@import("crc.zig"));
    std.testing.refAllDecls(@import("adler32.zig"));
    std.testing.refAllDecls(@import("zlib_compressor.zig"));
}