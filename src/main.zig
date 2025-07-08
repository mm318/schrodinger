const std = @import("std");
const builtin = @import("builtin");

const VtuWriter = @import("vtu_writer");

const s = @cImport({
    @cInclude("sundials/sundials_types.h"); // defs. of sunrealtype, sunindextype, etc
    @cInclude("sunlinsol/sunlinsol_pcg.h"); // access to PCG SUNLinearSolver
    @cInclude("nvector/nvector_serial.h"); // serial N_Vector types, fcts., macros
    @cInclude("arkode/arkode_arkstep.h"); // prototypes for ARKStep fcts., consts
});

const SundialsError = error{
    ArgCorrupt, // argument provided is NULL or corrupted
    ArgIncompatible, // argument provided is not compatible
    ArgOutOfRange, // argument is out of the valid range
    ArgWrongType, // argument provided is not the right type
    ArgDimsMismatch, // argument dimensions do not agree
    Generic, // an error occurred
    Corrupt, // value is NULL or corrupt
    OutOfRange, // Value is out of the expected range
    FileOpen, // Unable to open file
    OpFail, // an operation failed
    MemFail, // a memory operation failed
    MallocFail, // malloc returned NULL
    ExtFail, // a failure occurred in an external library
    DestroyFail, // a destroy function returned an error
    NotImplemented, // operation is not implemented: function pointer is NULL
    UserFcnFail, // the user provided callback function failed
    ProfilerMapFull, // the number of profiler entries exceeded SUNPROFILER_MAX_ENTRIES
    ProfilerMapGet, // unknown error getting SUNProfiler timer
    ProfilerMapInsert, // unknown error inserting SUNProfiler timer
    ProfilerMapKeyNotFound, // timer was not found in SUNProfiler
    ProfilerMapSort, // error sorting SUNProfiler map
    SunCtxCorrupt, // SUNContext is NULL or corrupt
    MpiFail, // an MPI call returned something other than MPI_SUCCESS
    Unreachable, // Reached code that should be unreachable
    Unknown, // Unknown error occurred
};

const ArkodeError = error{
    TStopReturn,
    RootReturn,
    Warning,
    TooMuchWork,
    TooMuchAcc,
    ErrFailure,
    ConvFailure,
    LInitFail,
    LSetupFail,
    LSolveFail,
    RhsFuncFail,
    FirstRhsFuncErr,
    ReptdRhsFuncErr,
    UnrecRhsFuncErr,
    RtFuncFail,
    LFreeFail,
    MassInitFail,
    MassSetupFail,
    MassSolveFail,
    MassFreeFail,
    MassMultFail,
    ConstrFail,
    MemFail,
    MemNull,
    IllInput,
    NoMalloc,
    BadK,
    BadT,
    BadDky,
    TooClose,
    VectorOpErr,
    NlsInitFail,
    NlsSetupFail,
    NlsSetupRecvr,
    NlsOpErr,
    InnerStepAttachErr,
    InnerStepFail,
    OuterToInnerFail,
    InnerToOuterFail,
    PostProcessStepFail, // ARK_POSTPROCESS_FAIL equals ARK_POSTPROCESS_STEP_FAIL for backwards compatibility
    PostProcessStageFail,
    UserPredictFail,
    InterpFail,
    InvalidTable,
    ContextErr,
    RelaxFail,
    RelaxMemNull,
    RelaxFuncFail,
    RelaxJacFail,
    ControllerErr,
    StepperUnsupported,
    DomeigFail,
    MaxStageLimitFail,
    SunstepperErr,
    StepDirectionErr,
    UnrecognizedError,
};

const SolverError = SundialsError || ArkodeError;

fn checkedCall(func: anytype, args: anytype) SolverError!void {
    const result = @call(.auto, func, args);
    if (result < s.SUN_SUCCESS or result < s.ARK_SUCCESS) {
        return switch (result) {
            s.SUN_ERR_ARG_CORRUPT => SolverError.ArgCorrupt,
            s.SUN_ERR_ARG_INCOMPATIBLE => SolverError.ArgIncompatible,
            s.SUN_ERR_ARG_OUTOFRANGE => SolverError.ArgOutOfRange,
            s.SUN_ERR_ARG_WRONGTYPE => SolverError.ArgWrongType,
            s.SUN_ERR_ARG_DIMSMISMATCH => SolverError.ArgDimsMismatch,
            s.SUN_ERR_GENERIC => SolverError.Generic,
            s.SUN_ERR_CORRUPT => SolverError.Corrupt,
            s.SUN_ERR_OUTOFRANGE => SolverError.OutOfRange,
            s.SUN_ERR_FILE_OPEN => SolverError.FileOpen,
            s.SUN_ERR_OP_FAIL => SolverError.OpFail,
            s.SUN_ERR_MEM_FAIL => SolverError.MemFail,
            s.SUN_ERR_MALLOC_FAIL => SolverError.MallocFail,
            s.SUN_ERR_EXT_FAIL => SolverError.ExtFail,
            s.SUN_ERR_DESTROY_FAIL => SolverError.DestroyFail,
            s.SUN_ERR_NOT_IMPLEMENTED => SolverError.NotImplemented,
            s.SUN_ERR_USER_FCN_FAIL => SolverError.UserFcnFail,
            s.SUN_ERR_PROFILER_MAPFULL => SolverError.ProfilerMapFull,
            s.SUN_ERR_PROFILER_MAPGET => SolverError.ProfilerMapGet,
            s.SUN_ERR_PROFILER_MAPINSERT => SolverError.ProfilerMapInsert,
            s.SUN_ERR_PROFILER_MAPKEYNOTFOUND => SolverError.ProfilerMapKeyNotFound,
            s.SUN_ERR_PROFILER_MAPSORT => SolverError.ProfilerMapSort,
            s.SUN_ERR_SUNCTX_CORRUPT => SolverError.SunCtxCorrupt,
            s.SUN_ERR_MPI_FAIL => SolverError.MpiFail,
            s.SUN_ERR_UNREACHABLE => SolverError.Unreachable,
            s.SUN_ERR_UNKNOWN => SolverError.Unknown,
            s.ARK_TSTOP_RETURN => SolverError.TStopReturn,
            s.ARK_ROOT_RETURN => SolverError.RootReturn,
            s.ARK_WARNING => SolverError.Warning,
            s.ARK_TOO_MUCH_WORK => SolverError.TooMuchWork,
            s.ARK_TOO_MUCH_ACC => SolverError.TooMuchAcc,
            s.ARK_ERR_FAILURE => SolverError.ErrFailure,
            s.ARK_CONV_FAILURE => SolverError.ConvFailure,
            s.ARK_LINIT_FAIL => SolverError.LInitFail,
            s.ARK_LSETUP_FAIL => SolverError.LSetupFail,
            s.ARK_LSOLVE_FAIL => SolverError.LSolveFail,
            s.ARK_RHSFUNC_FAIL => SolverError.RhsFuncFail,
            s.ARK_FIRST_RHSFUNC_ERR => SolverError.FirstRhsFuncErr,
            s.ARK_REPTD_RHSFUNC_ERR => SolverError.ReptdRhsFuncErr,
            s.ARK_UNREC_RHSFUNC_ERR => SolverError.UnrecRhsFuncErr,
            s.ARK_RTFUNC_FAIL => SolverError.RtFuncFail,
            s.ARK_LFREE_FAIL => SolverError.LFreeFail,
            s.ARK_MASSINIT_FAIL => SolverError.MassInitFail,
            s.ARK_MASSSETUP_FAIL => SolverError.MassSetupFail,
            s.ARK_MASSSOLVE_FAIL => SolverError.MassSolveFail,
            s.ARK_MASSFREE_FAIL => SolverError.MassFreeFail,
            s.ARK_MASSMULT_FAIL => SolverError.MassMultFail,
            s.ARK_CONSTR_FAIL => SolverError.ConstrFail,
            s.ARK_MEM_FAIL => SolverError.MemFail,
            s.ARK_MEM_NULL => SolverError.MemNull,
            s.ARK_ILL_INPUT => SolverError.IllInput,
            s.ARK_NO_MALLOC => SolverError.NoMalloc,
            s.ARK_BAD_K => SolverError.BadK,
            s.ARK_BAD_T => SolverError.BadT,
            s.ARK_BAD_DKY => SolverError.BadDky,
            s.ARK_TOO_CLOSE => SolverError.TooClose,
            s.ARK_VECTOROP_ERR => SolverError.VectorOpErr,
            s.ARK_NLS_INIT_FAIL => SolverError.NlsInitFail,
            s.ARK_NLS_SETUP_FAIL => SolverError.NlsSetupFail,
            s.ARK_NLS_SETUP_RECVR => SolverError.NlsSetupRecvr,
            s.ARK_NLS_OP_ERR => SolverError.NlsOpErr,
            s.ARK_INNERSTEP_ATTACH_ERR => SolverError.InnerStepAttachErr,
            s.ARK_INNERSTEP_FAIL => SolverError.InnerStepFail,
            s.ARK_OUTERTOINNER_FAIL => SolverError.OuterToInnerFail,
            s.ARK_INNERTOOUTER_FAIL => SolverError.InnerToOuterFail,
            s.ARK_POSTPROCESS_STEP_FAIL => SolverError.PostProcessStepFail,
            s.ARK_POSTPROCESS_STAGE_FAIL => SolverError.PostProcessStageFail,
            s.ARK_USER_PREDICT_FAIL => SolverError.UserPredictFail,
            s.ARK_INTERP_FAIL => SolverError.InterpFail,
            s.ARK_INVALID_TABLE => SolverError.InvalidTable,
            s.ARK_CONTEXT_ERR => SolverError.ContextErr,
            s.ARK_RELAX_FAIL => SolverError.RelaxFail,
            s.ARK_RELAX_MEM_NULL => SolverError.RelaxMemNull,
            s.ARK_RELAX_FUNC_FAIL => SolverError.RelaxFuncFail,
            s.ARK_RELAX_JAC_FAIL => SolverError.RelaxJacFail,
            s.ARK_CONTROLLER_ERR => SolverError.ControllerErr,
            s.ARK_STEPPER_UNSUPPORTED => SolverError.StepperUnsupported,
            s.ARK_DOMEIG_FAIL => SolverError.DomeigFail,
            s.ARK_MAX_STAGE_LIMIT_FAIL => SolverError.MaxStageLimitFail,
            s.ARK_SUNSTEPPER_ERR => SolverError.SunstepperErr,
            s.ARK_STEP_DIRECTION_ERR => SolverError.StepDirectionErr,
            s.ARK_UNRECOGNIZED_ERROR => SolverError.UnrecognizedError,
            else => SolverError.Unknown,
        };
    }
}

fn funcPtrRetType(func: anytype) type {
    return @typeInfo(@TypeOf(func)).@"fn".return_type.?;
}

fn checkedMemOp(func: anytype, args: anytype) !funcPtrRetType(func) {
    const result = @call(.auto, func, args);
    if (result == null) {
        return error.MemoryIssue;
    }
    return result;
}

const Domain = struct {
    Lx: s.sunrealtype, // physical size of domain in x direction
    Ly: s.sunrealtype, // physical size of domain in x direction
    Lz: s.sunrealtype, // physical size of domain in x direction
    Nx: usize, // number of nodes in x-component of space
    Ny: usize, // number of nodes in y-component of space
    Nz: usize, // number of nodes in z-component of space
    dx: s.sunrealtype, // mesh spacing in x direction
    dy: s.sunrealtype, // mesh spacing in y direction
    dz: s.sunrealtype, // mesh spacing in z direction
    kx: s.sunrealtype = 0.5, // x direction heat conductivity, diffusion coefficient
    ky: s.sunrealtype = 0.3, // y direction heat conductivity, diffusion coefficient
    kz: s.sunrealtype = 0.1, // z direction heat conductivity, diffusion coefficient
    h: s.sunrealtype = 1, // heat source power

    const Coord = struct {
        ix: usize,
        iy: usize,
        iz: usize,
    };

    fn init(L: s.sunrealtype, N: usize) Domain {
        return .{
            .Lx = L,
            .Ly = L,
            .Lz = L,
            .Nx = N,
            .Ny = N,
            .Nz = N,
            .dx = L / @as(s.sunrealtype, @floatFromInt(N - 1)),
            .dy = L / @as(s.sunrealtype, @floatFromInt(N - 1)),
            .dz = L / @as(s.sunrealtype, @floatFromInt(N - 1)),
        };
    }

    fn size(self: Domain) usize {
        return self.Nx * self.Ny * self.Nz;
    }

    fn coord2index(self: Domain, c: Coord) usize {
        std.debug.assert(c.ix < self.Nx);
        std.debug.assert(c.iy < self.Ny);
        std.debug.assert(c.iz < self.Nz);
        return c.iz * (self.Nx * self.Ny) + c.iy * self.Nx + c.ix;
    }

    fn index2coord(self: Domain, i: usize) Coord {
        std.debug.assert(i < self.size());
        return .{
            .ix = i % self.Nx,
            .iy = @divFloor(i, self.Nx) % self.Ny,
            .iz = @divFloor(i, self.Nx * self.Ny),
        };
    }
};

export fn f(
    t: s.sunrealtype,
    u: s.N_Vector,
    u_dot: s.N_Vector,
    domain_data: ?*anyopaque,
) i32 {
    _ = t;

    const p: *const Domain = @alignCast(@ptrCast(domain_data)); // access problem data
    const U = checkedMemOp(s.N_VGetArrayPointer, .{u}) catch return 1;
    const Udot = checkedMemOp(s.N_VGetArrayPointer, .{u_dot}) catch return 1;
    s.N_VConst(0.0, u_dot); // Initialize ydot to zero

    // iterate over domain, computing all equations
    const c1x: s.sunrealtype = p.kx / p.dx / p.dx;
    const c2x: s.sunrealtype = -2.0 * c1x;
    const c1y: s.sunrealtype = p.ky / p.dy / p.dy;
    const c2y: s.sunrealtype = -2.0 * c1y;
    const c1z: s.sunrealtype = p.kz / p.dz / p.dz;
    const c2z: s.sunrealtype = -2.0 * c1z;

    // slower
    // for (0..@intCast(p.Nz)) |iz| {
    //     for (0..@intCast(p.Ny)) |iy| {
    //         for (0..@intCast(p.Nx)) |ix| {
    //             const i = p.coord2index(.{ .ix = ix, .iy = iy, .iz = iz });
    //             if (ix == 0 or ix == p.Nx - 1 or iy == 0 or iy == p.Ny - 1 or iz == 0 or iz == p.Nz - 1) {
    //                 Udot[i] = 0.0; // boundary condition: adiabatic
    //             } else {
    //                 Udot[i] =
    //                     c1x * U[p.coord2index(.{ .ix = ix - 1, .iy = iy, .iz = iz })] +
    //                     c2x * U[i] +
    //                     c1x * U[p.coord2index(.{ .ix = ix + 1, .iy = iy, .iz = iz })] +
    //                     c1y * U[p.coord2index(.{ .ix = ix, .iy = iy - 1, .iz = iz })] +
    //                     c2y * U[i] +
    //                     c1y * U[p.coord2index(.{ .ix = ix, .iy = iy + 1, .iz = iz })] +
    //                     c1z * U[p.coord2index(.{ .ix = ix, .iy = iy, .iz = iz - 1 })] +
    //                     c2z * U[i] +
    //                     c1z * U[p.coord2index(.{ .ix = ix, .iy = iy, .iz = iz + 1 })];
    //             }
    //         }
    //     }
    // }

    // slow
    // for (0..p.size()) |i| {
    //     const c = p.index2coord(i);
    //     if (c.ix == 0 or c.ix == p.Nx - 1 or c.iy == 0 or c.iy == p.Ny - 1 or c.iz == 0 or c.iz == p.Nz - 1) {
    //         Udot[i] = 0.0; // boundary condition: adiabatic
    //     } else {
    //         const x_prev = i - 1;
    //         const x_next = i + 1;
    //         const y_prev = i - p.Nx;
    //         const y_next = i + p.Nx;
    //         const z_prev = i - (p.Nx * p.Ny);
    //         const z_next = i + (p.Nx * p.Ny);
    //         Udot[i] =
    //             c1x * U[x_prev] + c2x * U[i] + c1x * U[x_next] +
    //             c1y * U[y_prev] + c2y * U[i] + c1y * U[y_next] +
    //             c1z * U[z_prev] + c2z * U[i] + c1z * U[z_next];
    //     }
    // }

    var i: isize = 0;
    var x_prev = i - 1;
    var x_next = i + 1;
    var y_prev = i - @as(isize, @intCast(p.Nx));
    var y_next = i + @as(isize, @intCast(p.Nx));
    var z_prev = i - @as(isize, @intCast(p.Nx * p.Ny));
    var z_next = i + @as(isize, @intCast(p.Nx * p.Ny));
    for (0..@intCast(p.Nz)) |iz| {
        for (0..@intCast(p.Ny)) |iy| {
            for (0..@intCast(p.Nx)) |ix| {
                if (ix == 0 or ix == p.Nx - 1 or iy == 0 or iy == p.Ny - 1 or iz == 0 or iz == p.Nz - 1) {
                    if (ix == 0) {
                        Udot[@intCast(i)] = 2.0; // heat source
                    } else {
                        Udot[@intCast(i)] = 0.0; // boundary condition: adiabatic
                    }
                } else {
                    Udot[@intCast(i)] =
                        c1x * U[@intCast(x_prev)] + c2x * U[@intCast(i)] + c1x * U[@intCast(x_next)] +
                        c1y * U[@intCast(y_prev)] + c2y * U[@intCast(i)] + c1y * U[@intCast(y_next)] +
                        c1z * U[@intCast(z_prev)] + c2z * U[@intCast(i)] + c1z * U[@intCast(z_next)];
                }
                i += 1;
                x_prev += 1;
                x_next += 1;
                y_prev += 1;
                y_next += 1;
                z_prev += 1;
                z_next += 1;
            }
        }
    }

    return 0; // return with success
}

const Solver = struct {
    ctx: s.SUNContext,
    y: s.N_Vector,
    arkode_mem: ?*anyopaque,
    ls: s.SUNLinearSolver,

    fn init(domain: *const Domain, T0: s.sunrealtype) !Solver {
        const rtol: s.sunrealtype = 1e-6; // relative tolerance
        const atol: s.sunrealtype = 1e-10; // absolute tolerance

        var self: Solver = undefined;

        // Create the SUNDIALS context object for this simulation
        try checkedCall(s.SUNContext_Create, .{ s.SUN_COMM_NULL, &self.ctx });

        // Create serial vector for solution
        self.y = try checkedMemOp(s.N_VNew_Serial, .{ @as(s.sunindextype, @intCast(domain.size())), self.ctx });
        s.N_VConst(0.0, self.y);

        // Call ARKStepCreate to initialize the ARK timestepper module and
        // specify the right-hand side function in y'=f(t,y), the initial time
        // T0, and the initial dependent variable vector y.  Note: since this
        // problem is fully implicit, we set f_E to NULL and f_I to f.
        self.arkode_mem = try checkedMemOp(s.ARKStepCreate, .{ null, &f, T0, self.y, self.ctx });

        // Set routines
        try checkedCall(s.ARKodeSetUserData, .{ self.arkode_mem, @as(?*anyopaque, @ptrCast(@constCast(domain))) }); // Pass udata to user functions
        try checkedCall(s.ARKodeSetMaxNumSteps, .{ self.arkode_mem, 10000 }); // Increase max num steps
        try checkedCall(s.ARKodeSetPredictorMethod, .{ self.arkode_mem, 1 }); // Specify maximum-order predictor
        try checkedCall(s.ARKodeSStolerances, .{ self.arkode_mem, rtol, atol }); // Specify tolerances
        self.ls = try checkedMemOp(s.SUNLinSol_PCG, .{ self.y, 0, @as(i32, @intCast(domain.size())), self.ctx }); // Initialize PCG solver -- no preconditioning, with up to N iterations
        try checkedCall(s.ARKodeSetLinearSolver, .{ self.arkode_mem, self.ls, null }); // Attach linear solver to ARKODE
        try checkedCall(s.ARKodeSetLinear, .{ self.arkode_mem, 0 }); // Specify linearly implicit RHS, with non-time-dependent Jacobian

        return self;
    }

    fn getSolution(self: *const Solver) []const f64 {
        const U = checkedMemOp(s.N_VGetArrayPointer, .{self.y}) catch @panic("should have already crashed!");
        const U_size = s.N_VGetLocalLength(self.y);
        var result: []const f64 = undefined;
        result.ptr = U;
        result.len = @intCast(U_size);
        return result;
    }

    fn printStats(self: *const Solver) void {
        var nst: c_long = undefined;
        var nst_a: c_long = undefined;
        var nfe: c_long = undefined;
        var nfi: c_long = undefined;
        var nsetups: c_long = undefined;
        var nli: c_long = undefined;
        var nJv: c_long = undefined;
        var nlcf: c_long = undefined;
        var nni: c_long = undefined;
        var ncfn: c_long = undefined;
        var netf: c_long = undefined;
        checkedCall(s.ARKodeGetNumSteps, .{ self.arkode_mem, &nst }) catch @panic("can't even get an integer?");
        checkedCall(s.ARKodeGetNumStepAttempts, .{ self.arkode_mem, &nst_a }) catch @panic("can't even get an integer?");
        checkedCall(s.ARKodeGetNumRhsEvals, .{ self.arkode_mem, 0, &nfe }) catch @panic("can't even get an integer?");
        checkedCall(s.ARKodeGetNumRhsEvals, .{ self.arkode_mem, 1, &nfi }) catch @panic("can't even get an integer?");
        checkedCall(s.ARKodeGetNumLinSolvSetups, .{ self.arkode_mem, &nsetups }) catch @panic("can't even get an integer?");
        checkedCall(s.ARKodeGetNumErrTestFails, .{ self.arkode_mem, &netf }) catch @panic("can't even get an integer?");
        checkedCall(s.ARKodeGetNumNonlinSolvIters, .{ self.arkode_mem, &nni }) catch @panic("can't even get an integer?");
        checkedCall(s.ARKodeGetNumNonlinSolvConvFails, .{ self.arkode_mem, &ncfn }) catch @panic("can't even get an integer?");
        checkedCall(s.ARKodeGetNumLinIters, .{ self.arkode_mem, &nli }) catch @panic("can't even get an integer?");
        checkedCall(s.ARKodeGetNumJtimesEvals, .{ self.arkode_mem, &nJv }) catch @panic("can't even get an integer?");
        checkedCall(s.ARKodeGetNumLinConvFails, .{ self.arkode_mem, &nlcf }) catch @panic("can't even get an integer?");
        std.log.info("", .{});
        std.log.info("Final Solver Statistics:", .{});
        std.log.info("   Internal solver steps = {} (attempted = {})", .{ nst, nst_a });
        std.log.info("   Total RHS evals:  Fe = {},  Fi = {}", .{ nfe, nfi });
        std.log.info("   Total linear solver setups = {}", .{nsetups});
        std.log.info("   Total linear iterations = {}", .{nli});
        std.log.info("   Total number of Jacobian-vector products = {}", .{nJv});
        std.log.info("   Total number of linear solver convergence failures = {}", .{nlcf});
        std.log.info("   Total number of Newton iterations = {}", .{nni});
        std.log.info("   Total number of nonlinear solver convergence failures = {}", .{ncfn});
        std.log.info("   Total number of error test failures = {}", .{netf});
    }

    fn deinit(self: *Solver) void {
        _ = s.SUNContext_Free(&self.ctx);
        s.N_VDestroy(self.y);
        s.ARKodeFree(&self.arkode_mem);
        _ = s.SUNLinSolFree(self.ls);
    }
};

const Plotter = struct {
    mesh_builder: VtuWriter.UnstructuredMeshBuilder,
    num_plotted: usize = 0,
    series_file: ?std.fs.File = null,

    fn init(allocator: std.mem.Allocator, domain: *const Domain) !Plotter {
        var self = Plotter{ .mesh_builder = VtuWriter.UnstructuredMeshBuilder.init(allocator) };

        try self.mesh_builder.reservePoints(domain.size());
        try self.mesh_builder.reserveCells(.VTK_HEXAHEDRON, (domain.Nx - 1) * (domain.Ny - 1) * (domain.Nz - 1));

        for (0..domain.size()) |i| {
            const coord = domain.index2coord(i);
            _ = try self.mesh_builder.addPoint(.{
                domain.dx * @as(f64, @floatFromInt(coord.ix)),
                domain.dy * @as(f64, @floatFromInt(coord.iy)),
                domain.dz * @as(f64, @floatFromInt(coord.iz)),
            });
        }

        for (0..domain.Nz - 1) |iz| {
            for (0..domain.Ny - 1) |iy| {
                for (0..domain.Nx - 1) |ix| {
                    try self.mesh_builder.addCell(.VTK_HEXAHEDRON, .{
                        @intCast(domain.coord2index(.{ .ix = ix, .iy = iy, .iz = iz })),
                        @intCast(domain.coord2index(.{ .ix = ix + 1, .iy = iy, .iz = iz })),
                        @intCast(domain.coord2index(.{ .ix = ix + 1, .iy = iy + 1, .iz = iz })),
                        @intCast(domain.coord2index(.{ .ix = ix, .iy = iy + 1, .iz = iz })),
                        @intCast(domain.coord2index(.{ .ix = ix, .iy = iy, .iz = iz + 1 })),
                        @intCast(domain.coord2index(.{ .ix = ix + 1, .iy = iy, .iz = iz + 1 })),
                        @intCast(domain.coord2index(.{ .ix = ix + 1, .iy = iy + 1, .iz = iz + 1 })),
                        @intCast(domain.coord2index(.{ .ix = ix, .iy = iy + 1, .iz = iz + 1 })),
                    });
                }
            }
        }

        return self;
    }

    fn startSeries(self: *Plotter) !void {
        const cwd = std.fs.cwd();
        self.series_file = try cwd.createFile("heat3d.vtu.series", .{});
        try self.series_file.?.writer().print("{{\n  \"file-series-version\" : \"1.0\",\n  \"files\" : [\n", .{});
    }

    fn plot(self: *Plotter, allocator: std.mem.Allocator, point_data: []const f64, filename: []const u8) !void {
        const mesh = self.mesh_builder.getUnstructuredMesh();

        const data_sets = [_]VtuWriter.DataSet{
            .{ "Temperature", VtuWriter.DataSetType.PointData, 1, point_data },
        };

        try VtuWriter.writeVtu(allocator, filename, mesh, &data_sets, .rawbinarycompressed);
        if (self.series_file) |file| {
            try file.writer().print("    {{ \"name\" : \"{s}\", \"time\" : {} }},\n", .{ filename, self.num_plotted });
        }
        self.num_plotted += 1;
    }

    fn deinit(self: *Plotter) void {
        self.mesh_builder.deinit();
        if (self.series_file) |file| {
            file.writer().print("  ]\n}}\n", .{}) catch unreachable;
            file.close();
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.log.warn("memory leaked!", .{});
    }

    var domain = Domain.init(1.0, 32);

    const T0: s.sunrealtype = 0.0; // initial time
    const Tf: s.sunrealtype = 1.0; // final time
    const Nt: usize = 20; // total number of output times

    // Initial problem output
    std.log.info("3D Heat PDE test problem:", .{});
    std.log.info("  L_x = {}", .{domain.Lx});
    std.log.info("  L_y = {}", .{domain.Ly});
    std.log.info("  L_z = {}", .{domain.Lz});
    std.log.info("  N_x = {}", .{domain.Nx});
    std.log.info("  N_y = {}", .{domain.Ny});
    std.log.info("  N_z = {}", .{domain.Nz});
    std.log.info("  diffusion coefficient (x direction): k_x = {}", .{domain.kx});
    std.log.info("  diffusion coefficient (y direction): k_y = {}", .{domain.ky});
    std.log.info("  diffusion coefficient (z direction): k_z = {}", .{domain.kz});

    var solver = try Solver.init(&domain, T0);
    defer solver.deinit();

    var plotter = try Plotter.init(allocator, &domain);
    defer plotter.deinit();
    try plotter.startSeries();
    var strbuf: [256]u8 = undefined;

    var t = T0;
    const dTout = (Tf - T0) / Nt;
    var tout = T0 + dTout;

    // Initial output
    std.log.info("", .{});
    std.log.info("        t      ||u||_rms", .{});
    std.log.info("   -------------------------", .{});
    std.log.info("  {d:10.6}  {e:10.4}", .{ t, @sqrt(s.N_VDotProd(solver.y, solver.y) / @as(f64, @floatFromInt(domain.size()))) });
    var filename = try std.fmt.bufPrint(&strbuf, "heat3d_t{d:0>10.6}.vtu", .{t});
    try plotter.plot(allocator, solver.getSolution(), filename);

    var timer = try std.time.Timer.start();
    for (0..Nt) |_| {
        checkedCall(s.ARKodeEvolve, .{ solver.arkode_mem, tout, solver.y, &t, s.ARK_NORMAL }) catch {
            std.log.err("Solver failure, stopping integration", .{});
            break;
        };

        // successful solve: update output time
        std.log.info("  {d:10.6}  {e:10.4}", .{ t, @sqrt(s.N_VDotProd(solver.y, solver.y) / @as(f64, @floatFromInt(domain.size()))) });
        tout += dTout;
        tout = if (tout > Tf) Tf else tout;

        // plot results of time t
        filename = try std.fmt.bufPrint(&strbuf, "heat3d_t{d:0>10.6}.vtu", .{t});
        try plotter.plot(allocator, solver.getSolution(), filename);
    }
    const elapsed: f64 = @floatFromInt(timer.read());
    std.log.info("", .{});
    std.log.info("Time elapsed is: {d:.3} s", .{elapsed / std.time.ns_per_s});

    // Print some final statistics
    solver.printStats();
}

pub const std_options: std.Options = .{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        else => .info,
    },
};

test "index2coord" {
    var seed: u64 = undefined;
    try std.posix.getrandom(std.mem.asBytes(&seed));
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    const N = rand.intRangeAtMost(usize, 101, 201);
    const p = Domain.init(1.0, N);

    for (0..100) |_| {
        const i = rand.uintLessThan(usize, p.size());
        const c = p.index2coord(i);
        const i_new = p.coord2index(c);
        try std.testing.expectEqual(i, i_new);
    }
}

test "incremental index" {
    var seed: u64 = undefined;
    try std.posix.getrandom(std.mem.asBytes(&seed));
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    const N = rand.intRangeAtMost(usize, 101, 201);
    const p = Domain.init(1.0, N);

    for (0..100) |_| {
        const i = rand.uintLessThan(usize, p.size());
        const c = p.index2coord(i);
        if (c.ix > 0) {
            const x_prev = i - 1;
            try std.testing.expectEqual(p.coord2index(.{ .ix = c.ix - 1, .iy = c.iy, .iz = c.iz }), x_prev);
        }
        if (c.ix + 1 < p.Nx) {
            const x_next = i + 1;
            try std.testing.expectEqual(p.coord2index(.{ .ix = c.ix + 1, .iy = c.iy, .iz = c.iz }), x_next);
        }
        if (c.iy > 0) {
            const y_prev = i - p.Nx;
            try std.testing.expectEqual(p.coord2index(.{ .ix = c.ix, .iy = c.iy - 1, .iz = c.iz }), y_prev);
        }
        if (c.iy + 1 < p.Ny) {
            const y_next = i + p.Nx;
            try std.testing.expectEqual(p.coord2index(.{ .ix = c.ix, .iy = c.iy + 1, .iz = c.iz }), y_next);
        }
        if (c.iz > 0) {
            const z_prev = i - (p.Nx * p.Ny);
            try std.testing.expectEqual(p.coord2index(.{ .ix = c.ix, .iy = c.iy, .iz = c.iz - 1 }), z_prev);
        }
        if (c.iz + 1 < p.Nz) {
            const z_next = i + (p.Nx * p.Ny);
            try std.testing.expectEqual(p.coord2index(.{ .ix = c.ix, .iy = c.iy, .iz = c.iz + 1 }), z_next);
        }
    }
}

test "incremental index 2" {
    const p = Domain.init(1.0, 201);

    var i: isize = 0;
    var x_prev = i - 1;
    var x_next = i + 1;
    var y_prev = i - @as(isize, @intCast(p.Nx));
    var y_next = i + @as(isize, @intCast(p.Nx));
    var z_prev = i - @as(isize, @intCast(p.Nx * p.Ny));
    var z_next = i + @as(isize, @intCast(p.Nx * p.Ny));
    for (0..@intCast(p.Nz)) |iz| {
        for (0..@intCast(p.Ny)) |iy| {
            for (0..@intCast(p.Nx)) |ix| {
                try std.testing.expectEqual(p.coord2index(.{ .ix = ix, .iy = iy, .iz = iz }), @as(usize, @intCast(i)));
                if (ix > 0) {
                    try std.testing.expectEqual(p.coord2index(.{ .ix = ix - 1, .iy = iy, .iz = iz }), @as(usize, @intCast(x_prev)));
                }
                if (ix + 1 < p.Nx) {
                    try std.testing.expectEqual(p.coord2index(.{ .ix = ix + 1, .iy = iy, .iz = iz }), @as(usize, @intCast(x_next)));
                }
                if (iy > 0) {
                    try std.testing.expectEqual(p.coord2index(.{ .ix = ix, .iy = iy - 1, .iz = iz }), @as(usize, @intCast(y_prev)));
                }
                if (iy + 1 < p.Ny) {
                    try std.testing.expectEqual(p.coord2index(.{ .ix = ix, .iy = iy + 1, .iz = iz }), @as(usize, @intCast(y_next)));
                }
                if (iz > 0) {
                    try std.testing.expectEqual(p.coord2index(.{ .ix = ix, .iy = iy, .iz = iz - 1 }), @as(usize, @intCast(z_prev)));
                }
                if (iz + 1 < p.Nz) {
                    try std.testing.expectEqual(p.coord2index(.{ .ix = ix, .iy = iy, .iz = iz + 1 }), @as(usize, @intCast(z_next)));
                }

                i += 1;
                x_prev += 1;
                x_next += 1;
                y_prev += 1;
                y_next += 1;
                z_prev += 1;
                z_next += 1;
            }
        }
    }
}
