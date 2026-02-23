const std = @import("std");

const nvector_complex = @import("nvector_complex");
const Complex = nvector_complex.Complex;

const nv = nvector_complex.c;
pub const c = @cImport({
    @cInclude("arkode/arkode.h");
    @cInclude("arkode/arkode_arkstep.h");
});

const VtuWriter = @import("vtu_writer");


inline fn asNVector(v: nv.N_Vector) c.N_Vector {
    return @ptrCast(v);
}

inline fn asComplexNVector(v: c.N_Vector) nv.N_Vector {
    return @ptrCast(v);
}

inline fn asComplexSunContext(ctx: c.SUNContext) nv.SUNContext {
    return @ptrCast(ctx);
}

const Nx: usize = 64;
const Ny: usize = 64;
const neq: usize = Nx * Ny;
const Nt: usize = 50;
const domain_length: f64 = 1.0;
const packet_radius: f64 = 0.1;
const packet_x0: f64 = 0.2;
const packet_y0: f64 = 0.5;
const packet_kx: f64 = 40.0;
const packet_ky: f64 = 0.0;
const T0: f64 = 0.0;
const Tf: f64 = 0.0025;
const reltol: f64 = 1.0e-6;
const abstol: f64 = 1.0e-9;

const dx = domain_length / @as(f64, @floatFromInt(Nx));
const dy = domain_length / @as(f64, @floatFromInt(Ny));
const inv_dx2 = 1.0 / (dx * dx);
const inv_dy2 = 1.0 / (dy * dy);
const cell_area = dx * dy;
const two = Complex.init(2.0, 0.0);
const i_half = Complex.init(0.0, 0.5);
const inv_dx2_c = Complex.init(inv_dx2, 0.0);
const inv_dy2_c = Complex.init(inv_dy2, 0.0);

const Diagnostics = struct {
    norm: f64,
    x_mean: f64,
    y_mean: f64,
    peak_amp: f64,
};

inline fn idx(ix: usize, iy: usize) usize {
    return iy * Nx + ix;
}

const Plotter = struct {
    allocator: std.mem.Allocator,
    mesh_builder: VtuWriter.UnstructuredMeshBuilder,
    real_data: []f64,
    imag_data: []f64,
    prob_data: []f64,
    series_file: ?std.fs.File = null,
    num_plotted: usize = 0,

    fn init(allocator: std.mem.Allocator) !Plotter {
        var self = Plotter{
            .allocator = allocator,
            .mesh_builder = VtuWriter.UnstructuredMeshBuilder.init(allocator),
            .real_data = try allocator.alloc(f64, neq),
            .imag_data = try allocator.alloc(f64, neq),
            .prob_data = try allocator.alloc(f64, neq),
        };

        try self.mesh_builder.reservePoints(neq);
        try self.mesh_builder.reserveCells(.VTK_QUAD, (Nx - 1) * (Ny - 1));

        for (0..Ny) |iy| {
            const ycoord = (@as(f64, @floatFromInt(iy)) + 0.5) * dy;
            for (0..Nx) |ix| {
                const xcoord = (@as(f64, @floatFromInt(ix)) + 0.5) * dx;
                _ = try self.mesh_builder.addPoint(.{ xcoord, ycoord, 0.0 });
            }
        }

        for (0..Ny - 1) |iy| {
            for (0..Nx - 1) |ix| {
                try self.mesh_builder.addCell(.VTK_QUAD, .{
                    @intCast(idx(ix, iy)),
                    @intCast(idx(ix + 1, iy)),
                    @intCast(idx(ix + 1, iy + 1)),
                    @intCast(idx(ix, iy + 1)),
                });
            }
        }

        return self;
    }

    fn startSeries(self: *Plotter) !void {
        self.series_file = try std.fs.cwd().createFile("schrodinger2d.vtu.series", .{});
        try self.series_file.?.writeAll("{\n  \"file-series-version\" : \"1.0\",\n  \"files\" : [\n");
    }

    fn plot(self: *Plotter, y: *const nvector_complex.CVec, t: f64, filename: []const u8) !void {
        for (0..neq) |i| {
            const psi = y.data[i];
            self.real_data[i] = psi.re;
            self.imag_data[i] = psi.im;
            self.prob_data[i] = psi.re * psi.re + psi.im * psi.im;
        }

        const mesh = self.mesh_builder.getUnstructuredMesh();
        const data_sets = [_]VtuWriter.DataSet{
            .{ "psi_real", VtuWriter.DataSetType.PointData, 1, self.real_data },
            .{ "psi_imag", VtuWriter.DataSetType.PointData, 1, self.imag_data },
            .{ "probability_density", VtuWriter.DataSetType.PointData, 1, self.prob_data },
        };

        try VtuWriter.writeVtu(self.allocator, filename, mesh, &data_sets, .rawbinarycompressed);
        if (self.series_file) |file| {
            if (self.num_plotted > 0) {
                try file.writeAll(",\n");
            }
            var line_buf: [256]u8 = undefined;
            const line = try std.fmt.bufPrint(
                &line_buf,
                "    {{ \"name\" : \"{s}\", \"time\" : {d:.9} }}",
                .{ filename, t },
            );
            try file.writeAll(line);
        }
        self.num_plotted += 1;
    }

    fn deinit(self: *Plotter) void {
        self.mesh_builder.deinit();
        self.allocator.free(self.real_data);
        self.allocator.free(self.imag_data);
        self.allocator.free(self.prob_data);

        if (self.series_file) |file| {
            file.writeAll("\n  ]\n}\n") catch {};
            file.close();
        }
    }
};

fn normalizeWavefunction(y: *nvector_complex.CVec) void {
    var sum_prob: f64 = 0.0;
    for (0..neq) |i| {
        const psi = y.data[i];
        sum_prob += psi.re * psi.re + psi.im * psi.im;
    }

    const norm = sum_prob * cell_area;
    if (norm == 0.0) return;

    const scale = 1.0 / @sqrt(norm);
    const scale_c = Complex.init(scale, 0.0);
    for (0..neq) |i| {
        y.data[i] = y.data[i].mul(scale_c);
    }
}

fn initializeWavefunction(y: *nvector_complex.CVec) void {
    const sigma2 = packet_radius * packet_radius;
    for (0..Ny) |iy| {
        const ycoord = (@as(f64, @floatFromInt(iy)) + 0.5) * dy;
        for (0..Nx) |ix| {
            const xcoord = (@as(f64, @floatFromInt(ix)) + 0.5) * dx;
            const rx = xcoord - packet_x0;
            const ry = ycoord - packet_y0;
            const r2 = rx * rx + ry * ry;
            const envelope = @exp(-r2 / (2.0 * sigma2));
            const phase = packet_kx * xcoord + packet_ky * ycoord;
            y.data[idx(ix, iy)] = Complex.init(
                envelope * @cos(phase),
                envelope * @sin(phase),
            );
        }
    }

    normalizeWavefunction(y);
}

fn computeDiagnostics(y: *nvector_complex.CVec) Diagnostics {
    var sum_prob: f64 = 0.0;
    var sum_xprob: f64 = 0.0;
    var sum_yprob: f64 = 0.0;
    var peak_amp: f64 = 0.0;

    for (0..Ny) |iy| {
        const ycoord = (@as(f64, @floatFromInt(iy)) + 0.5) * dy;
        for (0..Nx) |ix| {
            const xcoord = (@as(f64, @floatFromInt(ix)) + 0.5) * dx;
            const psi = y.data[idx(ix, iy)];
            const prob = psi.re * psi.re + psi.im * psi.im;
            const amp = @sqrt(prob);

            sum_prob += prob;
            sum_xprob += xcoord * prob;
            sum_yprob += ycoord * prob;
            if (amp > peak_amp) peak_amp = amp;
        }
    }

    if (sum_prob == 0.0) {
        return .{
            .norm = 0.0,
            .x_mean = 0.0,
            .y_mean = 0.0,
            .peak_amp = peak_amp,
        };
    }

    return .{
        .norm = sum_prob * cell_area,
        .x_mean = sum_xprob / sum_prob,
        .y_mean = sum_yprob / sum_prob,
        .peak_amp = peak_amp,
    };
}

export fn Rhs(tn: c.sunrealtype, sunvec_y: c.N_Vector, sunvec_f: c.N_Vector, user_data: ?*anyopaque) c_int {
    _ = tn;
    _ = user_data;
    const y = nvector_complex.N_VGetCVec(asComplexNVector(sunvec_y));
    const f = nvector_complex.N_VGetCVec(asComplexNVector(sunvec_f));

    for (0..Ny) |iy| {
        const iy_d = if (iy == 0) Ny - 1 else iy - 1;
        const iy_u = if (iy + 1 == Ny) 0 else iy + 1;
        for (0..Nx) |ix| {
            const ix_l = if (ix == 0) Nx - 1 else ix - 1;
            const ix_r = if (ix + 1 == Nx) 0 else ix + 1;

            const center_id = idx(ix, iy);
            const center = y.data[center_id];

            const lap_x = y.data[idx(ix_r, iy)]
                .add(y.data[idx(ix_l, iy)])
                .sub(center.mul(two))
                .mul(inv_dx2_c);
            const lap_y = y.data[idx(ix, iy_u)]
                .add(y.data[idx(ix, iy_d)])
                .sub(center.mul(two))
                .mul(inv_dy2_c);

            f.data[center_id] = lap_x.add(lap_y).mul(i_half);
        }
    }
    return 0;
}

fn ARKStepStats(arkode_mem: *anyopaque) void {
    var nsteps: c_long = 0;
    var nst_a: c_long = 0;
    var nfe: c_long = 0;
    var netfails: c_long = 0;

    _ = c.ARKodeGetNumSteps(arkode_mem, &nsteps);
    _ = c.ARKodeGetNumStepAttempts(arkode_mem, &nst_a);
    _ = c.ARKodeGetNumRhsEvals(arkode_mem, 0, &nfe);
    _ = c.ARKodeGetNumErrTestFails(arkode_mem, &netfails);

    std.debug.print("\nFinal Solver Statistics:\n", .{});
    std.debug.print("    Internal solver steps = {}, (attempted = {})\n", .{ nsteps, nst_a });
    std.debug.print("    Total RHS evals = {}\n", .{nfe});
    std.debug.print("    Total number of error test failures ={}\n", .{netfails});
}

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    var sunctx: c.SUNContext = null;
    if (c.SUNContext_Create(c.SUN_COMM_NULL, &sunctx) != 0) {
        std.debug.print("ERROR: SUNContext_Create failed\n", .{});
        return;
    }
    defer _ = c.SUNContext_Free(&sunctx);

    std.debug.print("\n2D Schrödinger simulation on a unit square:\n", .{});
    std.debug.print("    grid = {} x {}, timesteps = {}\n", .{ Nx, Ny, Nt });
    std.debug.print("    packet radius = {d:.3}, center = ({d:.3}, {d:.3})\n", .{ packet_radius, packet_x0, packet_y0 });
    std.debug.print("    packet wavevector = ({d:.3}, {d:.3})\n", .{ packet_kx, packet_ky });
    std.debug.print("    reltol = {e}, abstol = {e}\n", .{ reltol, abstol });

    const sunvec_y = try nvector_complex.N_VNew_Complex(@intCast(neq), asComplexSunContext(sunctx));
    defer nvector_complex.N_VDestroy_Complex(sunvec_y);
    const y = nvector_complex.N_VGetCVec(sunvec_y);

    initializeWavefunction(y);

    var plotter = try Plotter.init(allocator);
    defer plotter.deinit();
    try plotter.startSeries();

    var arkode_mem: ?*anyopaque = c.ARKStepCreate(Rhs, null, T0, asNVector(sunvec_y), sunctx) orelse {
        std.debug.print("ERROR: arkode_mem = NULL\n", .{});
        return;
    };
    defer c.ARKodeFree(&arkode_mem);

    if (c.ARKodeSStolerances(arkode_mem.?, reltol, abstol) != 0) {
        std.debug.print("ERROR: ARKodeSStolerances failed\n", .{});
        return error.SolverSetupFailed;
    }

    var tcur: f64 = T0;
    const dTout = (Tf - T0) / @as(f64, @floatFromInt(Nt));
    if (c.ARKodeSetFixedStep(arkode_mem.?, dTout) != 0) {
        std.debug.print("ERROR: ARKodeSetFixedStep failed\n", .{});
        return error.SolverSetupFailed;
    }

    var tout = T0 + dTout;
    var diagnostics = computeDiagnostics(y);
    var filename_buf: [256]u8 = undefined;

    std.debug.print("\n step        t          norm       x_mean     y_mean    peak|psi|\n", .{});
    std.debug.print("--------------------------------------------------------------------\n", .{});
    std.debug.print(" {:>4}  {d:.6}  {d:.6}  {d:.6}  {d:.6}  {d:.6}\n", .{
        0,
        tcur,
        diagnostics.norm,
        diagnostics.x_mean,
        diagnostics.y_mean,
        diagnostics.peak_amp,
    });

    var filename = try std.fmt.bufPrint(&filename_buf, "schrodinger2d_t{d:0>10.6}.vtu", .{tcur});
    try plotter.plot(y, tcur, filename);

    for (1..Nt + 1) |step| {
        const ierr = c.ARKodeEvolve(arkode_mem.?, tout, asNVector(sunvec_y), &tcur, c.ARK_NORMAL);
        if (ierr < 0) {
            std.debug.print("ERROR: ARKodeEvolve failed, ierr = {}\n", .{ierr});
            return error.EvolveFailed;
        }

        diagnostics = computeDiagnostics(y);
        std.debug.print(" {:>4}  {d:.6}  {d:.6}  {d:.6}  {d:.6}  {d:.6}\n", .{
            step,
            tcur,
            diagnostics.norm,
            diagnostics.x_mean,
            diagnostics.y_mean,
            diagnostics.peak_amp,
        });

        filename = try std.fmt.bufPrint(&filename_buf, "schrodinger2d_t{d:0>10.6}.vtu", .{tcur});
        try plotter.plot(y, tcur, filename);

        tout = @min(tout + dTout, Tf);
    }

    std.debug.print("--------------------------------------------------------------------\n", .{});

    ARKStepStats(arkode_mem.?);
    std.debug.print("Wrote {} VTU files and schrodinger2d.vtu.series\n", .{plotter.num_plotted});
    std.debug.print("Final packet center: ({d:.6}, {d:.6}), norm = {d:.6}\n\n", .{
        diagnostics.x_mean,
        diagnostics.y_mean,
        diagnostics.norm,
    });
}
