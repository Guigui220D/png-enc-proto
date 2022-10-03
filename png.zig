const std = @import("std");

const Image = @import("Image.zig");
const crc = @import("crc.zig");
const ZlibCompressor = @import("zlib_compressor.zig").ZlibCompressor;

// TODO: encoder options
pub const Options = struct {};

pub fn encode(writer: anytype, alloc: std.mem.Allocator, image: Image, options: Options) !u64 {
    _ = options;

    var counting_writer = std.io.countingWriter(writer);
    var wr = counting_writer.writer();

    try writeSignature(wr);
    try writeHeader(wr, image.width, image.height);
    try writeData(wr, alloc, image);
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
fn writeData(writer: anytype, alloc: std.mem.Allocator, img: Image) !void {
    // TODO: think about a chunking IDAT writer (kinda like BufferedWriter)
    // TODO: fix this ugly writer stacking
    var buffer = std.ArrayList(u8).init(alloc);
    defer buffer.deinit();

    var crc_writer = crc.writer(buffer.writer());
    var crc_wr = crc_writer.writer();

    try crc_wr.writeAll("IDAT");

    var counting_writer = std.io.countingWriter(crc_wr);
    var counting_wr = counting_writer.writer();

    var zlib: ZlibCompressor(@TypeOf(counting_wr)) = undefined;
    try zlib.init(alloc, counting_wr);

    // Zlib frame
    try zlib.begin();
    try filter(img, .Heuristic, zlib.writer());
    try zlib.end();

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
    None = 0,
    Sub = 1,
    Up = 2,
    Average = 3,
    Paeth = 4,
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

fn filter(img: Image, filter_choice: FilterChoice, writer: anytype) !void {    
    var y: usize = 0;
    var prev_bytes: ?[]const u8 = null;

    while (y < img.height) : (y += 1) {
        const bytes = std.mem.sliceAsBytes(img.pixels[(y * img.width)..((y + 1) * img.width)]);

        const filter_type: FilterType = switch (filter_choice) {
            .TryAll => @panic("Unimplemented"),
            .Heuristic => filterChoiceHeuristic(bytes, prev_bytes),
            .Specified => |f| f,
        };

        try writer.writeByte(@enumToInt(filter_type));

        

        // TODO: for other things than 32bpp
        switch (filter_type) {
            .None => {
                // Just copy the line
                try writer.writeAll(bytes);
            },
            .Sub => {
                // Substract each pixel with the previous one
                for (bytes) |pix, i| {
                    const prev: u8 = if (i >= 4) bytes[i - 4] else 0;
                    const diff: u8 = pix -% prev;
                    try writer.writeByte(diff);
                }
            },
            .Up => {
                // Substract each pixel from the one above
                for (bytes) |pix, i| {
                    const above: u8 = if (prev_bytes) |b| b[i] else 0;
                    const diff: u8 = pix -% above;
                    try writer.writeByte(diff);
                }
            },
            .Average => {
                for (bytes) |pix, i| {
                    const prev: u8 = if (i >= 4) bytes[i - 4] else 0;
                    const above: u8 = if (prev_bytes) |b| b[i] else 0;
                    const avg: u8 = @truncate(u8, (@intCast(u9, prev) + above) / 2);
                    const diff = pix -% avg;
                    try writer.writeByte(diff);
                }
            },
            .Paeth => {
                for (bytes) |pix, i| {
                    const prev: u8 = if (i >= 4) bytes[i - 4] else 0;
                    const above: u8 = if (prev_bytes) |b| b[i] else 0;
                    const prev_above = if (prev_bytes) |b| (if (i >= 4) b[i - 4] else 0) else 0;
                    const diff = pix -% paeth(prev, above, prev_above);
                    try writer.writeByte(diff);
                }
            }
        }

        prev_bytes = bytes;
    }
}

fn filterChoiceHeuristic(scanline: []const u8, scanline_above: ?[]const u8) FilterType {
    var max_score: usize = 0;
    var best: FilterType = .None;
    inline for ([_]FilterType{ .None, .Sub, .Up, .Average, .Paeth }) |filter_type| {
        var prevb: u8 = 0;
        var combo: usize = 0;
        var score: usize = 0;
        switch (filter_type) {
            .None => {
                for (scanline) |b| {
                    if (b == prevb) {
                        combo += 1;
                    } else {
                        score += combo * combo;
                        combo = 0;
                        prevb = b;
                    }
                }
            },
            .Sub => {
                for (scanline) |pix, i| {
                    const prev: u8 = if (i >= 4) scanline[i - 4] else 0;
                    const diff: u8 = pix -% prev;

                    if (diff == prevb) {
                        combo += 1;
                    } else {
                        score += combo * combo;
                        combo = 0;
                        prevb = diff;
                    }
                }
            },
            .Up => {
                for (scanline) |pix, i| {
                    const above: u8 = if (scanline_above) |b| b[i] else 0;
                    const diff: u8 = pix -% above;

                    if (diff == prevb) {
                        combo += 1;
                    } else {
                        score += combo * combo;
                        combo = 0;
                        prevb = diff;
                    }
                }
            },
            .Average => {
                for (scanline) |pix, i| {
                    const prev: u8 = if (i >= 4) scanline[i - 4] else 0;
                    const above: u8 = if (scanline_above) |b| b[i] else 0;
                    const avg: u8 = @truncate(u8, (@intCast(u9, prev) + above) / 2);
                    const diff = pix -% avg;

                    if (diff == prevb) {
                        combo += 1;
                    } else {
                        score += combo * combo;
                        combo = 0;
                        prevb = diff;
                    }
                }
            },
            .Paeth => {
                for (scanline) |pix, i| {
                    const prev: u8 = if (i >= 4) scanline[i - 4] else 0;
                    const above: u8 = if (scanline_above) |b| b[i] else 0;
                    const prev_above = if (scanline_above) |b| (if (i >= 4) b[i - 4] else 0) else 0;
                    const diff = pix -% paeth(prev, above, prev_above);

                    if (diff == prevb) {
                        combo += 1;
                    } else {
                        score += combo * combo;
                        combo = 0;
                        prevb = diff;
                    }
                }
            }
        }
        if (score > max_score) {
            max_score = score;
            best = filter_type;
        }
    }
    return best;
}

fn paeth(b4: u8, up: u8, b4_up: u8) u8 {
    const p: i16 = @intCast(i16, b4) + up - b4_up;
    const pa = std.math.absInt(p - b4) catch unreachable;
    const pb = std.math.absInt(p - up) catch unreachable;
    const pc = std.math.absInt(p - b4_up) catch unreachable;

    if (pa <= pb and pa <= pc) {
        return b4;
    } else if (pb <= pc) {
        return up;
    } else {
        return b4_up;
    }
}

