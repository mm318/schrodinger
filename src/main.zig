const std = @import("std");

const nvector_complex = @import("nvector_complex");
const Complex = nvector_complex.Complex;

const nv = nvector_complex.c;
pub const c = @cImport({
    @cInclude("arkode/arkode.h");
    @cInclude("arkode/arkode_arkstep.h");
    @cInclude("sunnonlinsol/sunnonlinsol_fixedpoint.h");
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

// Grid and simulation size. Odd dimensions keep a cell center exactly at (0.5, 0.5, 0.5).
const Nx: usize = 101;
const Ny: usize = 101;
const Nz: usize = 101;
const neq: usize = Nx * Ny * Nz;
const Nt: usize = 100;

// Domain and initial Gaussian packet parameters.
const domain_length: f64 = 1.0;
const packet_radius: f64 = 0.1;
const packet_x0: f64 = 0.2;
const packet_y0: f64 = 0.5;
const packet_z0: f64 = 0.5;
const packet_kx: f64 = 157.0;
const packet_ky: f64 = 0.0;
const packet_kz: f64 = 0.0;

// Central inverse-square potential: V(r) = -k/r^2 around (0.5, 0.5, 0.5).
const potential_center_x: f64 = 0.5;
const potential_center_y: f64 = 0.5;
const potential_center_z: f64 = 0.5;
const potential_reference_radius: f64 = 0.25;
const potential_reference_abs: f64 = 5.0e2;
const center_potential_abs: f64 = 1.6666666666666667e5;

// Time integration controls.
const T0: f64 = 0.0;
const Tf: f64 = 0.006;
const reltol: f64 = 1.0e-6;
const abstol: f64 = 1.0e-9;
const internal_substeps: usize = 10;

// Derived spatial factors and complex constants used in the RHS stencil.
const dx = domain_length / @as(f64, @floatFromInt(Nx));
const dy = domain_length / @as(f64, @floatFromInt(Ny));
const dz = domain_length / @as(f64, @floatFromInt(Nz));
const inv_dx2 = 1.0 / (dx * dx);
const inv_dy2 = 1.0 / (dy * dy);
const inv_dz2 = 1.0 / (dz * dz);
const cell_volume = dx * dy * dz;
const two = Complex.init(2.0, 0.0);
const i_half = Complex.init(0.0, 0.5);
const inv_dx2_c = Complex.init(inv_dx2, 0.0);
const inv_dy2_c = Complex.init(inv_dy2, 0.0);
const inv_dz2_c = Complex.init(inv_dz2, 0.0);

// k is set so V(r=0.25) = -500. The singularity is clamped so V_min = -center_potential_abs.
const potential_k = potential_reference_abs * potential_reference_radius * potential_reference_radius;
const singularity_radius = @sqrt(potential_k / center_potential_abs);
const singularity_radius2 = singularity_radius * singularity_radius;

const Diagnostics = struct {
    norm: f64,
    x_mean: f64,
    y_mean: f64,
    z_mean: f64,
    sigma_x: f64,
    sigma_y: f64,
    sigma_z: f64,
    peak_amp: f64,
};

inline fn idx(ix: usize, iy: usize, iz: usize) usize {
    return (iz * Ny + iy) * Nx + ix;
}

fn potentialAt(xcoord: f64, ycoord: f64, zcoord: f64) f64 {
    const rx = xcoord - potential_center_x;
    const ry = ycoord - potential_center_y;
    const rz = zcoord - potential_center_z;
    const r2 = rx * rx + ry * ry + rz * rz;
    const safe_r2 = @max(r2, singularity_radius2);
    return -potential_k / safe_r2;
}

const Plotter = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    mesh_builder: VtuWriter.UnstructuredMeshBuilder,
    real_data: []f64,
    imag_data: []f64,
    prob_data: []f64,
    potential_data: []f64,
    series_file: ?std.Io.File = null,
    num_plotted: usize = 0,

    fn init(allocator: std.mem.Allocator, io: std.Io) !Plotter {
        var self = Plotter{
            .allocator = allocator,
            .io = io,
            .mesh_builder = VtuWriter.UnstructuredMeshBuilder.init(allocator),
            .real_data = try allocator.alloc(f64, neq),
            .imag_data = try allocator.alloc(f64, neq),
            .prob_data = try allocator.alloc(f64, neq),
            .potential_data = try allocator.alloc(f64, neq),
        };

        try self.mesh_builder.reservePoints(neq);
        try self.mesh_builder.reserveCells(.VTK_VOXEL, (Nx - 1) * (Ny - 1) * (Nz - 1));

        for (0..Nz) |iz| {
            const zcoord = (@as(f64, @floatFromInt(iz)) + 0.5) * dz;
            for (0..Ny) |iy| {
                const ycoord = (@as(f64, @floatFromInt(iy)) + 0.5) * dy;
                for (0..Nx) |ix| {
                    const xcoord = (@as(f64, @floatFromInt(ix)) + 0.5) * dx;
                    _ = try self.mesh_builder.addPoint(.{ xcoord, ycoord, zcoord });
                    self.potential_data[idx(ix, iy, iz)] = potentialAt(xcoord, ycoord, zcoord);
                }
            }
        }

        for (0..Nz - 1) |iz| {
            for (0..Ny - 1) |iy| {
                for (0..Nx - 1) |ix| {
                    try self.mesh_builder.addCell(.VTK_VOXEL, .{
                        @intCast(idx(ix, iy, iz)),
                        @intCast(idx(ix + 1, iy, iz)),
                        @intCast(idx(ix, iy + 1, iz)),
                        @intCast(idx(ix + 1, iy + 1, iz)),
                        @intCast(idx(ix, iy, iz + 1)),
                        @intCast(idx(ix + 1, iy, iz + 1)),
                        @intCast(idx(ix, iy + 1, iz + 1)),
                        @intCast(idx(ix + 1, iy + 1, iz + 1)),
                    });
                }
            }
        }

        return self;
    }

    fn writeSeriesChunk(self: *Plotter, bytes: []const u8) !void {
        const file = self.series_file orelse return error.SeriesFileNotOpen;
        var buf: [256]u8 = undefined;
        var writer = file.writerStreaming(self.io, &buf);
        try writer.interface.writeAll(bytes);
        try writer.interface.flush();
    }

    fn startSeries(self: *Plotter) !void {
        self.series_file = try std.Io.Dir.cwd().createFile(self.io, "schrodinger3d.vtu.series", .{});
        try self.writeSeriesChunk("{\n  \"file-series-version\" : \"1.0\",\n  \"files\" : [\n");
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
            .{ "potential", VtuWriter.DataSetType.PointData, 1, self.potential_data },
        };

        try VtuWriter.writeVtu(self.allocator, self.io, filename, mesh, &data_sets, .rawbinarycompressed);
        if (self.series_file != null) {
            if (self.num_plotted > 0) {
                try self.writeSeriesChunk(",\n");
            }
            var line_buf: [256]u8 = undefined;
            const line = try std.fmt.bufPrint(
                &line_buf,
                "    {{ \"name\" : \"{s}\", \"time\" : {d:.9} }}",
                .{ filename, t },
            );
            try self.writeSeriesChunk(line);
        }
        self.num_plotted += 1;
    }

    fn deinit(self: *Plotter) void {
        self.mesh_builder.deinit();
        self.allocator.free(self.real_data);
        self.allocator.free(self.imag_data);
        self.allocator.free(self.prob_data);
        self.allocator.free(self.potential_data);

        if (self.series_file) |file| {
            self.writeSeriesChunk("\n  ]\n}\n") catch {};
            file.close(self.io);
        }
    }
};

fn normalizeWavefunction(y: *nvector_complex.CVec) void {
    var sum_prob: f64 = 0.0;
    for (0..neq) |i| {
        const psi = y.data[i];
        sum_prob += psi.re * psi.re + psi.im * psi.im;
    }

    const norm = sum_prob * cell_volume;
    if (norm == 0.0) return;

    const scale = 1.0 / @sqrt(norm);
    const scale_c = Complex.init(scale, 0.0);
    for (0..neq) |i| {
        y.data[i] = y.data[i].mul(scale_c);
    }
}

fn initializeWavefunction(y: *nvector_complex.CVec) void {
    const sigma2 = packet_radius * packet_radius;
    for (0..Nz) |iz| {
        const zcoord = (@as(f64, @floatFromInt(iz)) + 0.5) * dz;
        for (0..Ny) |iy| {
            const ycoord = (@as(f64, @floatFromInt(iy)) + 0.5) * dy;
            for (0..Nx) |ix| {
                const xcoord = (@as(f64, @floatFromInt(ix)) + 0.5) * dx;
                const rx = xcoord - packet_x0;
                const ry = ycoord - packet_y0;
                const rz = zcoord - packet_z0;
                const r2 = rx * rx + ry * ry + rz * rz;
                const envelope = @exp(-r2 / (2.0 * sigma2));
                const phase = packet_kx * xcoord + packet_ky * ycoord + packet_kz * zcoord;
                y.data[idx(ix, iy, iz)] = Complex.init(
                    envelope * @cos(phase),
                    envelope * @sin(phase),
                );
            }
        }
    }

    normalizeWavefunction(y);
}

fn computeDiagnostics(y: *nvector_complex.CVec) Diagnostics {
    var sum_prob: f64 = 0.0;
    var sum_xprob: f64 = 0.0;
    var sum_yprob: f64 = 0.0;
    var sum_zprob: f64 = 0.0;
    var sum_x2prob: f64 = 0.0;
    var sum_y2prob: f64 = 0.0;
    var sum_z2prob: f64 = 0.0;
    var peak_amp: f64 = 0.0;

    for (0..Nz) |iz| {
        const zcoord = (@as(f64, @floatFromInt(iz)) + 0.5) * dz;
        for (0..Ny) |iy| {
            const ycoord = (@as(f64, @floatFromInt(iy)) + 0.5) * dy;
            for (0..Nx) |ix| {
                const xcoord = (@as(f64, @floatFromInt(ix)) + 0.5) * dx;
                const psi = y.data[idx(ix, iy, iz)];
                const prob = psi.re * psi.re + psi.im * psi.im;
                const amp = @sqrt(prob);

                sum_prob += prob;
                sum_xprob += xcoord * prob;
                sum_yprob += ycoord * prob;
                sum_zprob += zcoord * prob;
                sum_x2prob += xcoord * xcoord * prob;
                sum_y2prob += ycoord * ycoord * prob;
                sum_z2prob += zcoord * zcoord * prob;
                if (amp > peak_amp) peak_amp = amp;
            }
        }
    }

    if (sum_prob == 0.0) {
        return .{
            .norm = 0.0,
            .x_mean = 0.0,
            .y_mean = 0.0,
            .z_mean = 0.0,
            .sigma_x = 0.0,
            .sigma_y = 0.0,
            .sigma_z = 0.0,
            .peak_amp = peak_amp,
        };
    }

    const x_mean = sum_xprob / sum_prob;
    const y_mean = sum_yprob / sum_prob;
    const z_mean = sum_zprob / sum_prob;
    const var_x = @max(0.0, sum_x2prob / sum_prob - x_mean * x_mean);
    const var_y = @max(0.0, sum_y2prob / sum_prob - y_mean * y_mean);
    const var_z = @max(0.0, sum_z2prob / sum_prob - z_mean * z_mean);

    return .{
        .norm = sum_prob * cell_volume,
        .x_mean = x_mean,
        .y_mean = y_mean,
        .z_mean = z_mean,
        .sigma_x = @sqrt(var_x),
        .sigma_y = @sqrt(var_y),
        .sigma_z = @sqrt(var_z),
        .peak_amp = peak_amp,
    };
}

export fn Rhs(tn: c.sunrealtype, sunvec_y: c.N_Vector, sunvec_f: c.N_Vector, user_data: ?*anyopaque) c_int {
    _ = tn;
    _ = user_data;
    const y = nvector_complex.N_VGetCVec(asComplexNVector(sunvec_y));
    const f = nvector_complex.N_VGetCVec(asComplexNVector(sunvec_f));

    for (0..Nz) |iz| {
        const zcoord = (@as(f64, @floatFromInt(iz)) + 0.5) * dz;
        const iz_b = if (iz == 0) Nz - 1 else iz - 1;
        const iz_f = if (iz + 1 == Nz) 0 else iz + 1;
        for (0..Ny) |iy| {
            const ycoord = (@as(f64, @floatFromInt(iy)) + 0.5) * dy;
            const iy_d = if (iy == 0) Ny - 1 else iy - 1;
            const iy_u = if (iy + 1 == Ny) 0 else iy + 1;
            for (0..Nx) |ix| {
                const xcoord = (@as(f64, @floatFromInt(ix)) + 0.5) * dx;
                const ix_l = if (ix == 0) Nx - 1 else ix - 1;
                const ix_r = if (ix + 1 == Nx) 0 else ix + 1;

                const center_id = idx(ix, iy, iz);
                const center = y.data[center_id];

                const lap_x = y.data[idx(ix_r, iy, iz)]
                    .add(y.data[idx(ix_l, iy, iz)])
                    .sub(center.mul(two))
                    .mul(inv_dx2_c);
                const lap_y = y.data[idx(ix, iy_u, iz)]
                    .add(y.data[idx(ix, iy_d, iz)])
                    .sub(center.mul(two))
                    .mul(inv_dy2_c);
                const lap_z = y.data[idx(ix, iy, iz_f)]
                    .add(y.data[idx(ix, iy, iz_b)])
                    .sub(center.mul(two))
                    .mul(inv_dz2_c);

                const v = potentialAt(xcoord, ycoord, zcoord);
                const potential_term = center.mul(Complex.init(0.0, -v));
                f.data[center_id] = lap_x.add(lap_y).add(lap_z).mul(i_half).add(potential_term);
            }
        }
    }
    return 0;
}

fn ARKStepStats(arkode_mem: *anyopaque) void {
    var nsteps: c_long = 0;
    var nst_a: c_long = 0;
    var nfi: c_long = 0;
    var netfails: c_long = 0;

    _ = c.ARKodeGetNumSteps(arkode_mem, &nsteps);
    _ = c.ARKodeGetNumStepAttempts(arkode_mem, &nst_a);
    _ = c.ARKodeGetNumRhsEvals(arkode_mem, 1, &nfi);
    _ = c.ARKodeGetNumErrTestFails(arkode_mem, &netfails);

    std.debug.print("\nFinal Solver Statistics:\n", .{});
    std.debug.print("    Internal solver steps = {}, (attempted = {})\n", .{ nsteps, nst_a });
    std.debug.print("    Total implicit RHS evals = {}\n", .{nfi});
    std.debug.print("    Total number of error test failures ={}\n", .{netfails});
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var sunctx: c.SUNContext = null;
    if (c.SUNContext_Create(c.SUN_COMM_NULL, &sunctx) != 0) {
        std.debug.print("ERROR: SUNContext_Create failed\n", .{});
        return;
    }
    defer _ = c.SUNContext_Free(&sunctx);

    std.debug.print("\n3D Schrödinger simulation on a unit cube:\n", .{});
    std.debug.print("    grid = {} x {} x {}, timesteps = {}\n", .{ Nx, Ny, Nz, Nt });
    std.debug.print("    packet radius = {d:.3}, center = ({d:.3}, {d:.3}, {d:.3})\n", .{
        packet_radius,
        packet_x0,
        packet_y0,
        packet_z0,
    });
    std.debug.print("    packet wavevector = ({d:.3}, {d:.3}, {d:.3})\n", .{
        packet_kx,
        packet_ky,
        packet_kz,
    });
    std.debug.print("    potential: V(x,y,z) = -k/r^2, center = ({d:.3}, {d:.3}, {d:.3})\n", .{
        potential_center_x,
        potential_center_y,
        potential_center_z,
    });
    std.debug.print("    k = {e:.6}, V(r=0.25) = {e:.6}, V(r<=r_clamp) = {e:.6}, r_clamp = {e:.6}\n", .{
        potential_k,
        -potential_k / (potential_reference_radius * potential_reference_radius),
        -center_potential_abs,
        singularity_radius,
    });
    std.debug.print("    ARKODE method = implicit midpoint (DIRK), reltol = {e}, abstol = {e}\n", .{ reltol, abstol });
    std.debug.print("    internal fixed substeps per output step = {}\n", .{internal_substeps});

    const sunvec_y = try nvector_complex.N_VNew_Complex(@intCast(neq), asComplexSunContext(sunctx));
    defer nvector_complex.N_VDestroy_Complex(sunvec_y);
    const y = nvector_complex.N_VGetCVec(sunvec_y);
    initializeWavefunction(y);

    var plotter = try Plotter.init(allocator, io);
    defer plotter.deinit();
    try plotter.startSeries();

    var arkode_mem: ?*anyopaque = c.ARKStepCreate(null, Rhs, T0, asNVector(sunvec_y), sunctx) orelse {
        std.debug.print("ERROR: ARKStepCreate failed\n", .{});
        return error.SolverSetupFailed;
    };
    defer c.ARKodeFree(&arkode_mem);

    if (c.ARKStepSetTableNum(arkode_mem.?, c.ARKODE_IMPLICIT_MIDPOINT_1_2, c.ARKODE_ERK_NONE) != 0) {
        std.debug.print("ERROR: ARKStepSetTableNum failed\n", .{});
        return error.SolverSetupFailed;
    }

    const nls = c.SUNNonlinSol_FixedPoint(asNVector(sunvec_y), 0, sunctx);
    if (nls == null) {
        std.debug.print("ERROR: SUNNonlinSol_FixedPoint failed\n", .{});
        return error.SolverSetupFailed;
    }
    defer _ = c.SUNNonlinSolFree(nls);

    if (c.ARKodeSetNonlinearSolver(arkode_mem.?, nls) != 0) {
        std.debug.print("ERROR: ARKodeSetNonlinearSolver failed\n", .{});
        return error.SolverSetupFailed;
    }

    if (c.ARKodeSStolerances(arkode_mem.?, reltol, abstol) != 0) {
        std.debug.print("ERROR: ARKodeSStolerances failed\n", .{});
        return error.SolverSetupFailed;
    }
    if (c.ARKodeSetMaxNonlinIters(arkode_mem.?, 20) != 0) {
        std.debug.print("ERROR: ARKodeSetMaxNonlinIters failed\n", .{});
        return error.SolverSetupFailed;
    }

    var tcur: f64 = T0;
    const dTout = (Tf - T0) / @as(f64, @floatFromInt(Nt));
    const hfixed = dTout / @as(f64, @floatFromInt(internal_substeps));
    if (c.ARKodeSetFixedStep(arkode_mem.?, hfixed) != 0) {
        std.debug.print("ERROR: ARKodeSetFixedStep failed\n", .{});
        return error.SolverSetupFailed;
    }
    var tout = T0 + dTout;

    var diagnostics = computeDiagnostics(y);
    var filename_buf: [256]u8 = undefined;

    std.debug.print("\n step        t            norm         x_mean     y_mean     z_mean    sigma_x   sigma_y   sigma_z   peak|psi|\n", .{});
    std.debug.print("-----------------------------------------------------------------------------------------------------------------\n", .{});
    std.debug.print(" {:>4}  {d:.6}  {d:.10}  {d:.6}  {d:.6}  {d:.6}  {d:.6}  {d:.6}  {d:.6}  {d:.6}\n", .{
        0,
        tcur,
        diagnostics.norm,
        diagnostics.x_mean,
        diagnostics.y_mean,
        diagnostics.z_mean,
        diagnostics.sigma_x,
        diagnostics.sigma_y,
        diagnostics.sigma_z,
        diagnostics.peak_amp,
    });

    var filename = try std.fmt.bufPrint(&filename_buf, "schrodinger3d_t{d:0>4}.vtu", .{0});
    try plotter.plot(y, tcur, filename);

    for (1..Nt + 1) |step| {
        const ierr = c.ARKodeEvolve(arkode_mem.?, tout, asNVector(sunvec_y), &tcur, c.ARK_NORMAL);
        if (ierr < 0) {
            std.debug.print("ERROR: ARKodeEvolve failed, ierr = {}\n", .{ierr});
            return error.EvolveFailed;
        }

        diagnostics = computeDiagnostics(y);
        std.debug.print(" {:>4}  {d:.6}  {d:.10}  {d:.6}  {d:.6}  {d:.6}  {d:.6}  {d:.6}  {d:.6}  {d:.6}\n", .{
            step,
            tcur,
            diagnostics.norm,
            diagnostics.x_mean,
            diagnostics.y_mean,
            diagnostics.z_mean,
            diagnostics.sigma_x,
            diagnostics.sigma_y,
            diagnostics.sigma_z,
            diagnostics.peak_amp,
        });

        filename = try std.fmt.bufPrint(&filename_buf, "schrodinger3d_t{d:0>4}.vtu", .{step});
        try plotter.plot(y, tcur, filename);

        tout = @min(tout + dTout, Tf);
    }

    std.debug.print("-----------------------------------------------------------------------------------------------------------------\n", .{});
    ARKStepStats(arkode_mem.?);
    std.debug.print("Wrote {} VTU files and schrodinger3d.vtu.series\n", .{plotter.num_plotted});
    std.debug.print("Final packet center: ({d:.6}, {d:.6}, {d:.6}), norm = {d:.6}\n\n", .{
        diagnostics.x_mean,
        diagnostics.y_mean,
        diagnostics.z_mean,
        diagnostics.norm,
    });
}
