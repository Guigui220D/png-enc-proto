const std = @import("std");

const Image = @This();
pub const Pixel = u32;

/// Creates a new image with a specified size, allocates the data (without setting it), has to be freed with destroy
pub fn create(allocator: std.mem.Allocator, x: usize, y: usize) !Image {
    return Image{
        .width = x,
        .height = y,
        .pixels = try allocator.alloc(Pixel, x * y),
    };
}

/// Destroys an image that was created with create (use the same allocator)
pub fn destroy(self: Image, allocator: std.mem.Allocator) void {
    allocator.free(self.pixels);
}

/// Sets a pixel on the image, checks that the coords are inbounds
pub fn setPixel(self: Image, x: usize, y: usize, color: Pixel) error{OutOfBounds}!void {
    if (x >= self.width or y >= self.height)
        return error.OutOfBounds;

    self.pixels[x + y * self.width] = color;
}

/// Gets a pixel on the image, checks that the coords are inbounds
pub fn getPixel(self: Image, x: usize, y: usize) error{OutOfBounds}!Pixel {
    if (x >= self.width or y >= self.height)
        return error.OutOfBounds;

    return self.pixels[x + y * self.width];
}

/// Width of the image
width: usize,
/// Height of the image
height: usize,
/// Data of the image
pixels: []Pixel,
