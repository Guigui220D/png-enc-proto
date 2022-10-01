const std = @import("std");

const Image = @import("Image.zig");
const crc = @import("crc.zig");
const adler = @import("adler32.zig");

pub const Options = struct {};

pub fn encode(image: Image, writer: anytype, options: Options) !u64 {
    _ = options;

    var counting_writer = std.io.countingWriter(writer);
    var wr = counting_writer.writer();

    try writeSignature(wr);
    try writeHeader(wr, image.width, image.height);
    try writeData(wr, image);
    try writeTrailer(wr);

    return counting_writer.bytes_written;
}

fn writeSignature(writer: anytype) !void {
    try writer.writeAll("\x89\x50\x4E\x47\x0D\x0A\x1A\x0A");
}

/// Write the IHDR chunk
fn writeHeader(writer: anytype, width: usize, height: usize) !void {
    // header takes up 13 bytes always (25 with len, id and crc)
    try writer.writeIntBig(u32, 13);

    var crc_writer = crc.writer(writer);
    var crc_wr = crc_writer.writer();

    try crc_wr.writeAll("IHDR");

    try crc_wr.writeIntBig(u32, @truncate(u32, width));
    try crc_wr.writeIntBig(u32, @truncate(u32, height));
    try crc_wr.writeIntBig(u8, 8); // 8 bit color depth
    try crc_wr.writeIntBig(u8, 6); // true color with alpha
    try crc_wr.writeIntBig(u8, 0); // default compression (only standard)
    try crc_wr.writeIntBig(u8, 0); // default filter (only standard)
    try crc_wr.writeIntBig(u8, 0); // no interlace

    try writer.writeIntBig(u32, crc_writer.getCrc());
}

/// Write the IDAT chunk
fn writeData(writer: anytype, img: Image) !void {
    const alloc = std.heap.page_allocator;
    // TODO: this shouldn't use an allocator
    // TODO: think about a chunking IDAT writer (kinda like BufferedWriter)
    // TODO: fix this ugly writer stacking
    var buffer = std.ArrayList(u8).init(alloc);
    defer buffer.deinit();

    var crc_writer = crc.writer(buffer.writer());
    var crc_wr = crc_writer.writer();

    try crc_wr.writeAll("IDAT");

    var counting_writer = std.io.countingWriter(crc_wr);
    var counting_wr = counting_writer.writer();

    const cmf = 0x78; // 8 = deflate, 7 = log(window size (see std.compress.deflate)) - 8
     
    var flg: u8 = 0b11000000;
    const rem: usize = (@intCast(usize, cmf) * 256) + flg % 31;
    flg += 31 - @truncate(u8, rem);

    try counting_wr.writeIntBig(u8, cmf);
    try counting_wr.writeIntBig(u8, flg);

    var compressor = try std.compress.deflate.compressor(alloc, counting_wr, .{});
    const checksum = try filter(img, .{ .Specified = .None }, &compressor);
    try compressor.flush();

    try counting_wr.writeIntBig(u32, checksum);

    const size = @truncate(u32, buffer.items.len - 4);

    try writer.writeIntBig(u32, size);
    try writer.writeAll(buffer.items);
    try writer.writeIntBig(u32, crc_writer.getCrc());
}

/// Write the IEND chunk
fn writeTrailer(writer: anytype) !void {
    try writer.writeIntBig(u32, 0);

    var crc_writer = crc.writer(writer);
    var crc_wr = crc_writer.writer();

    try crc_wr.writeAll("IEND");

    try writer.writeIntBig(u32, crc_writer.getCrc());
}

const FilterType = enum(u8) {
    None,
    Sub,
    Up,
    Average,
    Paeth,
};

const FilterChoiceStrategies = enum {
    TryAll,
    Heuristic,
    Specified,
};

const FilterChoice = union(FilterChoiceStrategies) {
    TryAll,
    Heuristic,
    Specified: FilterType,
};

fn filter(img: Image, filter_choice: FilterChoice, compressor: anytype) !u32 {
    var linebuf = std.ArrayList(u8).init(compressor.allocator);
    defer linebuf.deinit();
    var adler_writer = adler.writer(linebuf.writer());
    var wr = adler_writer.writer();
    
    var y: usize = 0;
    while (y < img.height) : (y += 1) {
        const filter_type: FilterType = switch (filter_choice) {
            .TryAll,
            .Heuristic => @panic("Unimplemeted (TODO)"), // TODO: filter choice heuristic
            .Specified => |f| f,
        };

        linebuf.clearRetainingCapacity();

        try wr.writeIntBig(u8, @enumToInt(filter_type));

        switch (filter_type) {
            .None => {
                // Just copy the line
                try wr.writeAll(std.mem.sliceAsBytes(img.pixels[(y * img.width)..((y + 1) * img.width)]));
            },
            .Sub,
            .Up,
            .Average,
            .Paeth => @panic("Unimplemented (TODO)"), // TODO: filters
        }

        _ = try compressor.write(linebuf.items);
    }
    return adler_writer.adler;
}

