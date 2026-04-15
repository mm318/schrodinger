const std = @import("std");
const builtin = @import("builtin");

const a = @import("arkode-zig");
const VtuWriter = @import("vtu_writer");

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
    if (result < a.SUN_SUCCESS or result < a.ARK_SUCCESS) {
        return switch (result) {
            a.SUN_ERR_ARG_CORRUPT => SolverError.ArgCorrupt,
            a.SUN_ERR_ARG_INCOMPATIBLE => SolverError.ArgIncompatible,
            a.SUN_ERR_ARG_OUTOFRANGE => SolverError.ArgOutOfRange,
            a.SUN_ERR_ARG_WRONGTYPE => SolverError.ArgWrongType,
            a.SUN_ERR_ARG_DIMSMISMATCH => SolverError.ArgDimsMismatch,
            a.SUN_ERR_GENERIC => SolverError.Generic,
            a.SUN_ERR_CORRUPT => SolverError.Corrupt,
            a.SUN_ERR_OUTOFRANGE => SolverError.OutOfRange,
            a.SUN_ERR_FILE_OPEN => SolverError.FileOpen,
            a.SUN_ERR_OP_FAIL => SolverError.OpFail,
            a.SUN_ERR_MEM_FAIL => SolverError.MemFail,
            a.SUN_ERR_MALLOC_FAIL => SolverError.MallocFail,
            a.SUN_ERR_EXT_FAIL => SolverError.ExtFail,
            a.SUN_ERR_DESTROY_FAIL => SolverError.DestroyFail,
            a.SUN_ERR_NOT_IMPLEMENTED => SolverError.NotImplemented,
            a.SUN_ERR_USER_FCN_FAIL => SolverError.UserFcnFail,
            a.SUN_ERR_PROFILER_MAPFULL => SolverError.ProfilerMapFull,
            a.SUN_ERR_PROFILER_MAPGET => SolverError.ProfilerMapGet,
            a.SUN_ERR_PROFILER_MAPINSERT => SolverError.ProfilerMapInsert,
            a.SUN_ERR_PROFILER_MAPKEYNOTFOUND => SolverError.ProfilerMapKeyNotFound,
            a.SUN_ERR_PROFILER_MAPSORT => SolverError.ProfilerMapSort,
            a.SUN_ERR_SUNCTX_CORRUPT => SolverError.SunCtxCorrupt,
            a.SUN_ERR_MPI_FAIL => SolverError.MpiFail,
            a.SUN_ERR_UNREACHABLE => SolverError.Unreachable,
            a.SUN_ERR_UNKNOWN => SolverError.Unknown,
            a.ARK_TSTOP_RETURN => SolverError.TStopReturn,
            a.ARK_ROOT_RETURN => SolverError.RootReturn,
            a.ARK_WARNING => SolverError.Warning,
            a.ARK_TOO_MUCH_WORK => SolverError.TooMuchWork,
            a.ARK_TOO_MUCH_ACC => SolverError.TooMuchAcc,
            a.ARK_ERR_FAILURE => SolverError.ErrFailure,
            a.ARK_CONV_FAILURE => SolverError.ConvFailure,
            a.ARK_LINIT_FAIL => SolverError.LInitFail,
            a.ARK_LSETUP_FAIL => SolverError.LSetupFail,
            a.ARK_LSOLVE_FAIL => SolverError.LSolveFail,
            a.ARK_RHSFUNC_FAIL => SolverError.RhsFuncFail,
            a.ARK_FIRST_RHSFUNC_ERR => SolverError.FirstRhsFuncErr,
            a.ARK_REPTD_RHSFUNC_ERR => SolverError.ReptdRhsFuncErr,
            a.ARK_UNREC_RHSFUNC_ERR => SolverError.UnrecRhsFuncErr,
            a.ARK_RTFUNC_FAIL => SolverError.RtFuncFail,
            a.ARK_LFREE_FAIL => SolverError.LFreeFail,
            a.ARK_MASSINIT_FAIL => SolverError.MassInitFail,
            a.ARK_MASSSETUP_FAIL => SolverError.MassSetupFail,
            a.ARK_MASSSOLVE_FAIL => SolverError.MassSolveFail,
            a.ARK_MASSFREE_FAIL => SolverError.MassFreeFail,
            a.ARK_MASSMULT_FAIL => SolverError.MassMultFail,
            a.ARK_CONSTR_FAIL => SolverError.ConstrFail,
            a.ARK_MEM_FAIL => SolverError.MemFail,
            a.ARK_MEM_NULL => SolverError.MemNull,
            a.ARK_ILL_INPUT => SolverError.IllInput,
            a.ARK_NO_MALLOC => SolverError.NoMalloc,
            a.ARK_BAD_K => SolverError.BadK,
            a.ARK_BAD_T => SolverError.BadT,
            a.ARK_BAD_DKY => SolverError.BadDky,
            a.ARK_TOO_CLOSE => SolverError.TooClose,
            a.ARK_VECTOROP_ERR => SolverError.VectorOpErr,
            a.ARK_NLS_INIT_FAIL => SolverError.NlsInitFail,
            a.ARK_NLS_SETUP_FAIL => SolverError.NlsSetupFail,
            a.ARK_NLS_SETUP_RECVR => SolverError.NlsSetupRecvr,
            a.ARK_NLS_OP_ERR => SolverError.NlsOpErr,
            a.ARK_INNERSTEP_ATTACH_ERR => SolverError.InnerStepAttachErr,
            a.ARK_INNERSTEP_FAIL => SolverError.InnerStepFail,
            a.ARK_OUTERTOINNER_FAIL => SolverError.OuterToInnerFail,
            a.ARK_INNERTOOUTER_FAIL => SolverError.InnerToOuterFail,
            a.ARK_POSTPROCESS_STEP_FAIL => SolverError.PostProcessStepFail,
            a.ARK_POSTPROCESS_STAGE_FAIL => SolverError.PostProcessStageFail,
            a.ARK_USER_PREDICT_FAIL => SolverError.UserPredictFail,
            a.ARK_INTERP_FAIL => SolverError.InterpFail,
            a.ARK_INVALID_TABLE => SolverError.InvalidTable,
            a.ARK_CONTEXT_ERR => SolverError.ContextErr,
            a.ARK_RELAX_FAIL => SolverError.RelaxFail,
            a.ARK_RELAX_MEM_NULL => SolverError.RelaxMemNull,
            a.ARK_RELAX_FUNC_FAIL => SolverError.RelaxFuncFail,
            a.ARK_RELAX_JAC_FAIL => SolverError.RelaxJacFail,
            a.ARK_CONTROLLER_ERR => SolverError.ControllerErr,
            a.ARK_STEPPER_UNSUPPORTED => SolverError.StepperUnsupported,
            a.ARK_DOMEIG_FAIL => SolverError.DomeigFail,
            a.ARK_MAX_STAGE_LIMIT_FAIL => SolverError.MaxStageLimitFail,
            a.ARK_SUNSTEPPER_ERR => SolverError.SunstepperErr,
            a.ARK_STEP_DIRECTION_ERR => SolverError.StepDirectionErr,
            a.ARK_UNRECOGNIZED_ERROR => SolverError.UnrecognizedError,
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

fn elapsedSecondsSince(io: std.Io, start: std.Io.Timestamp) f64 {
    const elapsed_ns = start.untilNow(io, .awake).toNanoseconds();
    return @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(std.time.ns_per_s));
}

// Macros for problem constants
const PI = a.SUN_RCONST(3.141592653589793238462643383279502884197169);
const ZERO = a.SUN_RCONST(0.0);
const ONE = a.SUN_RCONST(1.0);
const TWO = a.SUN_RCONST(2.0);

const Domain = struct {
    const Coord = struct {
        ix: usize,
        iy: usize,
        iz: usize,
    };

    // Diffusion coefficients in the x and y directions
    kx: a.sunrealtype,
    ky: a.sunrealtype,
    kz: a.sunrealtype,

    // Upper bounds in x and y directions
    xu: a.sunrealtype,
    yu: a.sunrealtype,
    zu: a.sunrealtype,

    // Number of nodes in the x and y directions
    nx: a.sunindextype,
    ny: a.sunindextype,
    nz: a.sunindextype,

    // Total number of nodes
    nodes: a.sunindextype,

    // Mesh spacing in the x and y directions
    dx: a.sunrealtype,
    dy: a.sunrealtype,
    dz: a.sunrealtype,

    // Final time
    tf: a.sunrealtype,

    fn init(l: a.sunrealtype, n: a.sunindextype) Domain {
        var domain: Domain = undefined;

        // Diffusion coefficient
        domain.kx = 0.5;
        domain.ky = 0.3;
        domain.kz = 0.1;

        // Upper bounds in x and y directions
        domain.xu = l;
        domain.yu = l;
        domain.zu = l;

        // Number of nodes in the x and y directions
        domain.nx = n;
        domain.ny = n;
        domain.nz = n;
        domain.nodes = domain.nx * domain.ny * domain.nz;

        // Mesh spacing in the x and y directions
        domain.dx = domain.xu / @as(f64, @floatFromInt(domain.nx - 1));
        domain.dy = domain.yu / @as(f64, @floatFromInt(domain.ny - 1));
        domain.dz = domain.zu / @as(f64, @floatFromInt(domain.nz - 1));

        // Final time
        domain.tf = ONE;

        return domain;
    }

    fn size(self: Domain) usize {
        return @intCast(self.nodes);
    }

    fn coord2index(self: Domain, c: Coord) usize {
        std.debug.assert(c.ix < self.nx);
        std.debug.assert(c.iy < self.ny);
        std.debug.assert(c.iz < self.nz);

        // Shortcuts to number of nodes
        const nx: usize = @intCast(self.nx);
        const ny: usize = @intCast(self.ny);

        return c.iz * (nx * ny) + c.iy * nx + c.ix;
    }

    fn index2coord(self: Domain, i: usize) Coord {
        std.debug.assert(i < self.size());

        // Shortcuts to number of nodes
        const nx: usize = @intCast(self.nx);
        const ny: usize = @intCast(self.ny);

        return .{
            .ix = i % nx,
            .iy = @divFloor(i, nx) % ny,
            .iz = @divFloor(i, nx * ny),
        };
    }

    // f routine to compute the ODE RHS function f(t,y).
    export fn f(
        _: a.sunrealtype,
        u: a.N_Vector,
        u_dot: a.N_Vector,
        user_data: ?*anyopaque,
    ) i32 {
        // Access problem data
        const solver: *Solver = @ptrCast(@alignCast(user_data));
        const start = std.Io.Timestamp.now(solver.io, .awake);
        const p: *const Domain = solver.domain;

        const U = checkedMemOp(a.N_VGetArrayPointer, .{u}) catch return 1;
        const Udot = checkedMemOp(a.N_VGetArrayPointer, .{u_dot}) catch return 1;
        a.N_VConst(0.0, u_dot); // Initialize ydot to zero

        // iterate over domain, computing all equations
        const c1x: a.sunrealtype = p.kx / p.dx / p.dx;
        const c2x: a.sunrealtype = -2.0 * c1x;
        const c1y: a.sunrealtype = p.ky / p.dy / p.dy;
        const c2y: a.sunrealtype = -2.0 * c1y;
        const c1z: a.sunrealtype = p.kz / p.dz / p.dz;
        const c2z: a.sunrealtype = -2.0 * c1z;

        var i: isize = 0;
        var x_prev = i - 1;
        var x_next = i + 1;
        var y_prev = i - @as(isize, @intCast(p.nx));
        var y_next = i + @as(isize, @intCast(p.nx));
        var z_prev = i - @as(isize, @intCast(p.nx * p.ny));
        var z_next = i + @as(isize, @intCast(p.nx * p.ny));
        for (0..@intCast(p.nz)) |iz| {
            for (0..@intCast(p.ny)) |iy| {
                for (0..@intCast(p.nx)) |ix| {
                    if (ix == 0 or ix == p.nx - 1 or iy == 0 or iy == p.ny - 1 or iz == 0 or iz == p.nz - 1) {
                        if (ix == 0) {
                            Udot[@intCast(i)] = TWO; // heat source
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

        // Update timer
        solver.rhstime += elapsedSecondsSince(solver.io, start);

        return 0; // return with success
    }

    fn printData(self: Domain) void {
        std.log.info("", .{});
        std.log.info("3D Heat PDE test problem:", .{});
        std.log.info(" --------------------------------- ", .{});
        std.log.info("  kx             = {}", .{self.kx});
        std.log.info("  ky             = {}", .{self.ky});
        std.log.info("  kz             = {}", .{self.kz});
        std.log.info("  tf             = {}", .{self.tf});
        std.log.info("  xu             = {}", .{self.xu});
        std.log.info("  yu             = {}", .{self.yu});
        std.log.info("  zu             = {}", .{self.zu});
        std.log.info("  nx             = {}", .{self.nx});
        std.log.info("  ny             = {}", .{self.ny});
        std.log.info("  nz             = {}", .{self.nz});
        std.log.info("  dx             = {}", .{self.dx});
        std.log.info("  dy             = {}", .{self.dy});
        std.log.info("  dz             = {}", .{self.dz});
        std.log.info(" --------------------------------- ", .{});
    }
};

const Solver = struct {
    const Options = struct {
        // Integrator settings
        rtol: a.sunrealtype, // relative tolerance
        atol: a.sunrealtype, // absolute tolerance
        hfixed: a.sunrealtype, // fixed step size
        order: i32, // ARKode method order
        // step size adaptivity method: 0=PID, 1=PI,
        //   2=I, 3=ExpGus, 4=ImpGus, 5=ImExGus,
        //   6=H0321, 7=H0211, 8=H211, 9=H312
        controller: i32,
        maxsteps: i32, // max number of steps between outputs
        linear: bool, // enable/disable linearly implicit option
        diagnostics: bool, // output diagnostics

        // Linear solver and preconditioner settings
        pcg: bool, // use PCG (true) or GMRES (false)
        prec: bool, // preconditioner on/off
        lsinfo: bool, // output residual history
        liniters: i32, // number of linear iterations
        msbp: i32, // max number of steps between preconditioner setups
        epslin: a.sunrealtype, // linear solver tolerance factor

        // Output variables
        output: i32, // output level
        nout: i32, // number of output times
        timing: bool, // print timings

        fn default() Options {
            var opts: Options = undefined;

            // Integrator settings
            opts.rtol = a.SUN_RCONST(1e-5); // relative tolerance
            opts.atol = a.SUN_RCONST(1e-10); // absolute tolerance
            opts.hfixed = ZERO; // using adaptive step sizes
            opts.order = 3; // method order
            opts.controller = 0; // PID controller
            opts.maxsteps = 0; // use default
            opts.linear = true; // linearly implicit problem
            opts.diagnostics = false; // output diagnostics

            // Linear solver and preconditioner settings
            opts.pcg = true; // use PCG (true) or GMRES (false)
            opts.prec = true; // enable preconditioning
            opts.lsinfo = false; // output residual history
            opts.liniters = 40; // max linear iterations
            opts.msbp = 0; // use default (20 steps)
            opts.epslin = ZERO; // use default (0.05)

            // Output variables
            opts.output = 1; // 0 = no output, 1 = stats output, 2 = output to disk
            opts.nout = 20; // Number of output times
            opts.timing = true;

            return opts;
        }

        fn print(self: Options) void {
            std.log.info("  rtol           = {}", .{self.rtol});
            std.log.info("  atol           = {}", .{self.atol});
            std.log.info("  order          = {}", .{self.order});
            std.log.info("  fixed h        = {}", .{self.hfixed});
            std.log.info("  controller     = {}", .{self.controller});
            std.log.info("  linear         = {}", .{self.linear});
            std.log.info(" --------------------------------- ", .{});
            if (self.pcg) {
                std.log.info("  linear solver  = PCG", .{});
            } else {
                std.log.info("  linear solver  = GMRES", .{});
            }
            std.log.info("  lin iters      = {}", .{self.liniters});
            std.log.info("  eps lin        = {}", .{self.epslin});
            std.log.info("  prec           = {}", .{self.prec});
            std.log.info("  msbp           = {}", .{self.msbp});
            std.log.info(" --------------------------------- ", .{});
            std.log.info("  output         = {}", .{self.output});
            std.log.info(" --------------------------------- ", .{});
            std.log.info("", .{});
        }
    };

    options: Options,

    ctx: a.SUNContext, // The SUNDIALS context object for this simulation
    arkode_mem: ?*anyopaque, // ARKODE memory structure
    LS: a.SUNLinearSolver, // linear solver memory structure
    C: a.SUNAdaptController, // Adaptivity controller

    domain: *const Domain,
    d: a.N_Vector, // Inverse of Jacobian diagonal for preconditioner
    u: a.N_Vector, // vector for storing solution

    // Timing variables
    io: std.Io,
    evolvetime: f64 = 0.0,
    rhstime: f64 = 0.0,
    psetuptime: f64 = 0.0,
    psolvetime: f64 = 0.0,

    // Preconditioner setup routine
    export fn PSetup(
        _: a.sunrealtype,
        _: a.N_Vector,
        _: a.N_Vector,
        _: a.sunbooleantype,
        _: [*c]a.sunbooleantype,
        gamma: a.sunrealtype,
        user_data: ?*anyopaque,
    ) i32 {
        // Access problem data
        const solver: *Solver = @ptrCast(@alignCast(user_data));
        const start = std.Io.Timestamp.now(solver.io, .awake);
        const udata: *const Domain = solver.domain;

        // Access data array
        _ = checkedMemOp(a.N_VGetArrayPointer, .{solver.d}) catch return -1;

        // Constants for computing diffusion
        const cx: a.sunrealtype = udata.kx / (udata.dx * udata.dx);
        const cy: a.sunrealtype = udata.ky / (udata.dy * udata.dy);
        const cz: a.sunrealtype = udata.kz / (udata.dz * udata.dz);
        const cc: a.sunrealtype = -TWO * (cx + cy + cz);

        // Set all entries of d to the inverse diagonal values of interior
        // (since boundary RHS is 0, set boundary diagonals to the same)
        const c: a.sunrealtype = ONE / (ONE - gamma * cc);
        a.N_VConst(c, solver.d);

        // Update timer
        solver.psetuptime += elapsedSecondsSince(solver.io, start);

        // Return success
        return 0;
    }

    // Preconditioner solve routine for Pz = r
    export fn PSolve(
        _: a.sunrealtype,
        _: a.N_Vector,
        _: a.N_Vector,
        r: a.N_Vector,
        z: a.N_Vector,
        _: a.sunrealtype,
        _: a.sunrealtype,
        _: i32,
        user_data: ?*anyopaque,
    ) i32 {
        // Access user_data structure
        const solver: *Solver = @ptrCast(@alignCast(user_data));
        const start = std.Io.Timestamp.now(solver.io, .awake);

        // Perform Jacobi iteration
        a.N_VProd(solver.d, r, z);

        // Update timer
        solver.psolvetime += elapsedSecondsSince(solver.io, start);

        // Return success
        return 0;
    }

    fn init(allocator: std.mem.Allocator, io: std.Io, domain: *Domain, opts: Options) !*Solver {
        const solver = try allocator.create(Solver);
        solver.options = opts;
        solver.io = io;
        solver.domain = domain;
        solver.ctx = null;
        solver.arkode_mem = null;
        solver.LS = null;
        solver.C = null;

        try checkedCall(a.SUNContext_Create, .{ a.SUN_COMM_NULL, &solver.ctx });

        if (opts.diagnostics or opts.lsinfo) {
            var logger: a.SUNLogger = null;
            try checkedCall(a.SUNContext_GetLogger, .{ solver.ctx, &logger });
            try checkedCall(a.SUNLogger_SetInfoFilename, .{ logger, "diagnostics.txt" });
            try checkedCall(a.SUNLogger_SetDebugFilename, .{ logger, "diagnostics.txt" });
        }

        // ----------------------
        // Create serial vectors
        // ----------------------

        // Create vector for solution
        solver.u = try checkedMemOp(a.N_VNew_Serial, .{ domain.nodes, solver.ctx });

        // Set initial condition: Initialize u to zero (handles boundary conditions)
        a.N_VConst(ZERO, solver.u);

        // ---------------------
        // Create linear solver
        // ---------------------

        // Create linear solver
        const prectype: i32 = if (opts.prec) a.SUN_PREC_RIGHT else a.SUN_PREC_NONE;

        if (opts.pcg) {
            solver.LS = try checkedMemOp(a.SUNLinSol_PCG, .{ solver.u, prectype, opts.liniters, solver.ctx });
        } else {
            solver.LS = try checkedMemOp(a.SUNLinSol_SPGMR, .{ solver.u, prectype, opts.liniters, solver.ctx });
        }

        // Allocate preconditioner workspace
        if (opts.prec) {
            solver.d = try checkedMemOp(a.N_VClone, .{solver.u});
        } else {
            solver.d = null;
        }

        // --------------
        // Setup ARKODE
        // --------------

        // Create integrator
        solver.arkode_mem = try checkedMemOp(a.ARKStepCreate, .{ null, &Domain.f, ZERO, solver.u, solver.ctx });

        // Specify tolerances
        try checkedCall(a.ARKodeSStolerances, .{ solver.arkode_mem, opts.rtol, opts.atol });

        // Attach user data
        try checkedCall(a.ARKodeSetUserData, .{ solver.arkode_mem, @as(?*anyopaque, @ptrCast(solver)) });

        // Attach linear solver
        try checkedCall(a.ARKodeSetLinearSolver, .{ solver.arkode_mem, solver.LS, null });

        if (opts.prec) {
            // Attach preconditioner
            try checkedCall(a.ARKodeSetPreconditioner, .{ solver.arkode_mem, Solver.PSetup, Solver.PSolve });

            // Set linear solver setup frequency (update preconditioner)
            try checkedCall(a.ARKodeSetLSetupFrequency, .{ solver.arkode_mem, opts.msbp });
        }

        // Set linear solver tolerance factor
        try checkedCall(a.ARKodeSetEpsLin, .{ solver.arkode_mem, opts.epslin });

        // Select method order
        if (opts.order > 1) {
            // Use an ARKode provided table
            try checkedCall(a.ARKodeSetOrder, .{ solver.arkode_mem, opts.order });
        } else {
            // Use implicit Euler (requires fixed step size)
            var A: [1]a.sunrealtype = .{ONE};
            var b: [1]a.sunrealtype = .{ONE};
            var c: [1]a.sunrealtype = .{ONE};

            // Create implicit Euler Butcher table
            const B: a.ARKodeButcherTable = try checkedMemOp(
                a.ARKodeButcherTable_Create,
                .{ 1, 1, 0, &c, &A, &b, null },
            );

            // Attach the Butcher table
            try checkedCall(a.ARKStepSetTables, .{ solver.arkode_mem, 1, 0, B, null });

            // Free the Butcher table
            a.ARKodeButcherTable_Free(B);
        }

        // Set fixed step size or adaptivity method
        if (opts.hfixed > ZERO) {
            try checkedCall(a.ARKodeSetFixedStep, .{ solver.arkode_mem, opts.hfixed });
        } else {
            solver.C = switch (opts.controller) {
                0 => a.SUNAdaptController_PID(solver.ctx),
                1 => a.SUNAdaptController_PI(solver.ctx),
                2 => a.SUNAdaptController_I(solver.ctx),
                3 => a.SUNAdaptController_ExpGus(solver.ctx),
                4 => a.SUNAdaptController_ImpGus(solver.ctx),
                5 => a.SUNAdaptController_ImExGus(solver.ctx),
                // 6:=> a.SUNAdaptController_H0321(ctx.ctx),
                // 7:=> a.SUNAdaptController_H0211(ctx.ctx),
                // 8:=> a.SUNAdaptController_H211(ctx.ctx),
                // 9:=> a.SUNAdaptController_H312(ctx.ctx),
                else => return SolverError.ArgOutOfRange,
            };
            try checkedCall(a.ARKodeSetAdaptController, .{ solver.arkode_mem, solver.C });
        }

        // Specify linearly implicit non-time-dependent RHS
        if (opts.linear) {
            try checkedCall(a.ARKodeSetLinear, .{ solver.arkode_mem, 0 });
        }

        // Set max steps between outputs
        try checkedCall(a.ARKodeSetMaxNumSteps, .{ solver.arkode_mem, opts.maxsteps });

        // Set stopping time
        try checkedCall(a.ARKodeSetStopTime, .{ solver.arkode_mem, domain.tf });

        return solver;
    }

    fn printOptions(self: *const Solver) void {
        self.options.print();
    }

    fn printStats(self: *const Solver) void {
        // Get integrator and solver stats
        var nst: c_long = undefined;
        var nst_a: c_long = undefined;
        var netf: c_long = undefined;
        var nfi: c_long = undefined;
        var nni: c_long = undefined;
        var ncfn: c_long = undefined;
        var nli: c_long = undefined;
        var nlcf: c_long = undefined;
        var nsetups: c_long = undefined;
        var nfi_ls: c_long = undefined;
        var nJv: c_long = undefined;

        checkedCall(a.ARKodeGetNumSteps, .{ self.arkode_mem, &nst }) catch {
            std.log.err("Unable to ARKodeGetNumSteps", .{});
        };
        checkedCall(a.ARKodeGetNumStepAttempts, .{ self.arkode_mem, &nst_a }) catch {
            std.log.err("Unable to ARKodeGetNumStepAttempts", .{});
        };
        checkedCall(a.ARKodeGetNumErrTestFails, .{ self.arkode_mem, &netf }) catch {
            std.log.err("Unable to ARKodeGetNumErrTestFails", .{});
        };
        checkedCall(a.ARKodeGetNumRhsEvals, .{ self.arkode_mem, 1, &nfi }) catch {
            std.log.err("Unable to ARKodeGetNumRhsEvals", .{});
        };
        checkedCall(a.ARKodeGetNumNonlinSolvIters, .{ self.arkode_mem, &nni }) catch {
            std.log.err("Unable to ARKodeGetNumNonlinSolvIters", .{});
        };
        checkedCall(a.ARKodeGetNumNonlinSolvConvFails, .{ self.arkode_mem, &ncfn }) catch {
            std.log.err("Unable to ARKodeGetNumNonlinSolvConvFails", .{});
        };
        checkedCall(a.ARKodeGetNumLinIters, .{ self.arkode_mem, &nli }) catch {
            std.log.err("Unable to ARKodeGetNumLinIters", .{});
        };
        checkedCall(a.ARKodeGetNumLinConvFails, .{ self.arkode_mem, &nlcf }) catch {
            std.log.err("Unable to ARKodeGetNumLinConvFails", .{});
        };
        checkedCall(a.ARKodeGetNumLinSolvSetups, .{ self.arkode_mem, &nsetups }) catch {
            std.log.err("Unable to ARKodeGetNumLinSolvSetups", .{});
        };
        checkedCall(a.ARKodeGetNumLinRhsEvals, .{ self.arkode_mem, &nfi_ls }) catch {
            std.log.err("Unable to ARKodeGetNumLinRhsEvals", .{});
        };
        checkedCall(a.ARKodeGetNumJtimesEvals, .{ self.arkode_mem, &nJv }) catch {
            std.log.err("Unable to ARKodeGetNumJtimesEvals", .{});
        };

        std.log.info("Final integrator statistics:", .{});
        std.log.info("  Steps            = {d:.6}", .{nst});
        std.log.info("  Step attempts    = {d:.6}", .{nst_a});
        std.log.info("  Error test fails = {d:.6}", .{netf});
        std.log.info("  RHS evals        = {d:.6}", .{nfi});
        std.log.info("  NLS iters        = {d:.6}", .{nni});
        std.log.info("  NLS fails        = {d:.6}", .{ncfn});
        std.log.info("  LS iters         = {d:.6}", .{nli});
        std.log.info("  LS fails         = {d:.6}", .{nlcf});
        std.log.info("  LS setups        = {d:.6}", .{nsetups});
        std.log.info("  LS RHS evals     = {d:.6}", .{nfi_ls});
        std.log.info("  Jv products      = {d:.6}", .{nJv});
        std.log.info("", .{});

        // Compute average nls iters per step attempt and ls iters per nls iter
        const avgnli: a.sunrealtype = @as(a.sunrealtype, @floatFromInt(nni)) / @as(a.sunrealtype, @floatFromInt(nst_a));
        const avgli: a.sunrealtype = @as(a.sunrealtype, @floatFromInt(nli)) / @as(a.sunrealtype, @floatFromInt(nni));
        std.log.info("  Avg NLS iters per step attempt = {d:.6}", .{avgnli});
        std.log.info("  Avg LS iters per NLS iter      = {d:.6}", .{avgli});
        std.log.info("", .{});

        // Get preconditioner stats
        if (self.options.prec) {
            var npe: c_long = undefined;
            var nps: c_long = undefined;

            checkedCall(a.ARKodeGetNumPrecEvals, .{ self.arkode_mem, &npe }) catch {
                std.log.err("Unable to ARKodeGetNumPrecEvals", .{});
            };
            checkedCall(a.ARKodeGetNumPrecSolves, .{ self.arkode_mem, &nps }) catch {
                std.log.err("Unable to ARKodeGetNumPrecSolves", .{});
            };

            std.log.info("  Preconditioner setups = {d:.6}", .{npe});
            std.log.info("  Preconditioner solves = {d:.6}", .{nps});
            std.log.info("", .{});
        }
    }

    fn printTiming(self: *const Solver) void {
        std.log.info("  Evolve time = {d:.6} sec", .{self.evolvetime});
        std.log.info("  RHS time    = {d:.6} sec", .{self.rhstime});
        std.log.info("", .{});

        if (self.options.prec) {
            std.log.info("  PSetup time = {d:.6} sec", .{self.psetuptime});
            std.log.info("  PSolve time = {d:.6} sec", .{self.psolvetime});
            std.log.info("", .{});
        }
    }

    fn deinit(self: *Solver, allocator: std.mem.Allocator) void {
        // --------------------
        // Clean up and return
        // --------------------
        a.ARKodeFree(&self.arkode_mem); // Free integrator memory
        _ = a.SUNLinSolFree(self.LS); // Free linear solver
        a.N_VDestroy(self.u); // Free vectors
        a.N_VDestroy(self.d); // Free vectors
        _ = a.SUNAdaptController_Destroy(self.C); // Free time adaptivity controller
        _ = a.SUNContext_Free(&self.ctx); // Free context

        allocator.destroy(self);
    }
};

fn OpenOutput(solver: *const Solver) void {
    // Header for status output
    if (solver.options.output > 0) {
        std.log.info("          t                     ||u||_rms      ", .{});
        std.log.info(" ----------------------------------------------", .{});
    }
}

fn WriteOutput(solver: *const Solver, t: a.sunrealtype) void {
    if (solver.options.output > 0) {
        const udata: *const Domain = solver.domain;

        // Compute rms norm of the state
        const urms: a.sunrealtype = std.math.sqrt(
            a.N_VDotProd(solver.u, solver.u) / @as(f64, @floatFromInt(udata.size())),
        );

        // Output current status
        std.log.info("{e:22.15}{e:25.15}", .{ t, urms });
    }
}

fn CloseOutput(solver: *const Solver) void {
    // Footer for status output
    if (solver.options.output > 0) {
        std.log.info(" ----------------------------------------------", .{});
        std.log.info("", .{});
    }
}

const Plotter = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    mesh_builder: VtuWriter.UnstructuredMeshBuilder,
    num_plotted: usize = 0,
    series_file: ?std.Io.File = null,

    fn init(allocator: std.mem.Allocator, io: std.Io, domain: *const Domain) !Plotter {
        var self = Plotter{
            .allocator = allocator,
            .io = io,
            .mesh_builder = VtuWriter.UnstructuredMeshBuilder.init(allocator),
        };

        try self.mesh_builder.reservePoints(domain.size());
        try self.mesh_builder.reserveCells(.VTK_HEXAHEDRON, @intCast((domain.nx - 1) * (domain.ny - 1) * (domain.nz - 1)));

        for (0..domain.size()) |i| {
            const coord = domain.index2coord(i);
            _ = try self.mesh_builder.addPoint(.{
                domain.dx * @as(f64, @floatFromInt(coord.ix)),
                domain.dy * @as(f64, @floatFromInt(coord.iy)),
                domain.dz * @as(f64, @floatFromInt(coord.iz)),
            });
        }

        for (0..@intCast(domain.nz - 1)) |iz| {
            for (0..@intCast(domain.ny - 1)) |iy| {
                for (0..@intCast(domain.nx - 1)) |ix| {
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

    fn writeSeriesChunk(self: *Plotter, bytes: []const u8) !void {
        const file = self.series_file orelse return error.SeriesFileNotOpen;
        var buf: [256]u8 = undefined;
        var writer = file.writerStreaming(self.io, &buf);
        try writer.interface.writeAll(bytes);
        try writer.interface.flush();
    }

    fn startSeries(self: *Plotter) !void {
        self.series_file = try std.Io.Dir.cwd().createFile(self.io, "heat3d.vtu.series", .{});
        try self.writeSeriesChunk("{\n  \"file-series-version\" : \"1.0\",\n  \"files\" : [\n");
    }

    fn plot(self: *Plotter, u: a.N_Vector, filename: []const u8) !void {
        const mesh = self.mesh_builder.getUnstructuredMesh();

        const u_array = checkedMemOp(a.N_VGetArrayPointer, .{u}) catch unreachable;
        const u_array_size = a.N_VGetLocalLength(u);
        var point_data: []const f64 = undefined;
        point_data.ptr = u_array;
        point_data.len = @intCast(u_array_size);
        const data_sets = [_]VtuWriter.DataSet{
            .{ "Temperature", VtuWriter.DataSetType.PointData, 1, point_data },
        };

        try VtuWriter.writeVtu(self.allocator, self.io, filename, mesh, &data_sets, .rawbinarycompressed);
        if (self.series_file != null) {
            var line_buf: [256]u8 = undefined;
            const line = try std.fmt.bufPrint(
                &line_buf,
                "    {{ \"name\" : \"{s}\", \"time\" : {} }},\n",
                .{ filename, self.num_plotted },
            );
            try self.writeSeriesChunk(line);
        }
        self.num_plotted += 1;
    }

    fn deinit(self: *Plotter) void {
        self.mesh_builder.deinit();

        if (self.series_file) |file| {
            self.writeSeriesChunk("  ]\n}\n") catch {};
            file.close(self.io);
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var domain = Domain.init(1.0, 32);
    domain.printData();

    const solver = try Solver.init(allocator, io, &domain, Solver.Options.default());
    defer solver.deinit(allocator);
    solver.printOptions();

    var plotter = try Plotter.init(allocator, io, solver.domain);
    defer plotter.deinit();
    try plotter.startSeries();
    var strbuf: [256]u8 = undefined;

    var t: a.sunrealtype = 0;
    const dTout: a.sunrealtype = solver.domain.tf / @as(f64, @floatFromInt(solver.options.nout));
    var tout: a.sunrealtype = dTout;

    // Initial output
    OpenOutput(solver);
    WriteOutput(solver, t);
    var filename = try std.fmt.bufPrint(&strbuf, "heat3d_t{d:0>10.6}.vtu", .{t});
    try plotter.plot(solver.u, filename);

    for (0..@intCast(solver.options.nout)) |_| {
        const start = std.Io.Timestamp.now(io, .awake);
        try checkedCall(a.ARKodeEvolve, .{ solver.arkode_mem, tout, solver.u, &t, a.ARK_NORMAL });

        // Update timer
        solver.evolvetime += elapsedSecondsSince(io, start);

        // Output solution and error
        WriteOutput(solver, t);
        filename = try std.fmt.bufPrint(&strbuf, "heat3d_t{d:0>10.6}.vtu", .{t});
        try plotter.plot(solver.u, filename);

        // Update output time
        tout += dTout;
        tout = if (tout > solver.domain.tf) solver.domain.tf else tout;
    }

    CloseOutput(solver);

    // Print some final statistics
    solver.printStats();
    if (solver.options.timing) {
        solver.printTiming();
    }
}

pub const std_options: std.Options = .{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        else => .info,
    },
};

test "index2coord" {
    var prng = std.Random.DefaultPrng.init(0);
    const rand = prng.random();

    const N = rand.intRangeAtMost(a.sunindextype, 101, 201);
    const p = Domain.init(1.0, N);

    for (0..100) |_| {
        const i = rand.uintLessThan(usize, p.size());
        const c = p.index2coord(i);
        const i_new = p.coord2index(c);
        try std.testing.expectEqual(i, i_new);
    }
}

test "index iteration" {
    const p = Domain.init(1.0, 201);

    var i: isize = 0;
    var x_prev = i - 1;
    var x_next = i + 1;
    var y_prev = i - @as(isize, @intCast(p.nx));
    var y_next = i + @as(isize, @intCast(p.nx));
    var z_prev = i - @as(isize, @intCast(p.nx * p.ny));
    var z_next = i + @as(isize, @intCast(p.nx * p.ny));
    for (0..@intCast(p.nz)) |iz| {
        for (0..@intCast(p.ny)) |iy| {
            for (0..@intCast(p.nx)) |ix| {
                try std.testing.expectEqual(p.coord2index(.{ .ix = ix, .iy = iy, .iz = iz }), @as(usize, @intCast(i)));
                if (ix > 0) {
                    try std.testing.expectEqual(p.coord2index(.{ .ix = ix - 1, .iy = iy, .iz = iz }), @as(usize, @intCast(x_prev)));
                }
                if (ix + 1 < p.nx) {
                    try std.testing.expectEqual(p.coord2index(.{ .ix = ix + 1, .iy = iy, .iz = iz }), @as(usize, @intCast(x_next)));
                }
                if (iy > 0) {
                    try std.testing.expectEqual(p.coord2index(.{ .ix = ix, .iy = iy - 1, .iz = iz }), @as(usize, @intCast(y_prev)));
                }
                if (iy + 1 < p.ny) {
                    try std.testing.expectEqual(p.coord2index(.{ .ix = ix, .iy = iy + 1, .iz = iz }), @as(usize, @intCast(y_next)));
                }
                if (iz > 0) {
                    try std.testing.expectEqual(p.coord2index(.{ .ix = ix, .iy = iy, .iz = iz - 1 }), @as(usize, @intCast(z_prev)));
                }
                if (iz + 1 < p.nz) {
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
