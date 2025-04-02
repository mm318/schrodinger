const std = @import("std");

const zzplot = @import("zzplot");
const nvg = zzplot.nanovg;
const Figure = zzplot.Figure;
const Axes = zzplot.Axes;
const Plot = zzplot.Plot;

const c = @cImport({
    @cInclude("GLFW/glfw3.h");
    @cInclude("sundials/sundials_types.h"); // defs. of sunrealtype, sunindextype, etc
});

pub fn plot(
    allocator: std.mem.Allocator,
    x: *const []const c.sunrealtype,
    y_all: *const []const std.ArrayList(c.sunrealtype),
) !void {
    const shared = try zzplot.createShared();

    // nvg context creation goes after gladLoadGL
    const vg = try nvg.gl.init(allocator, .{});

    zzplot.Font.init(vg);

    const fig = try Figure.init(allocator, shared, vg, .{});
    const ax = try Axes.init(fig, .{});
    const plt = try Plot.init(ax, .{});

    ax.set_limits(.{ 0, 1 }, .{ -0.000010, 0.005000 }, .{});

    while (fig.live) {
        fig.begin();

        ax.draw();
        for (y_all.*) |y| {
            plt.plot(c.sunrealtype, x.*, y.items);
        }

        fig.end();
    }

    c.glfwTerminate();
}
