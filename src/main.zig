const std = @import("std");
const builtin = @import("builtin");

const VtuWriter = @import("vtu_writer");

const s = @cImport({
    @cInclude("nvector/nvector_serial.h"); // access to the serial N_Vector
    @cInclude("sunlinsol/sunlinsol_pcg.h"); // access to PCG SUNLinearSolver
    @cInclude("sunlinsol/sunlinsol_spgmr.h"); // access to SPGMR SUNLinearSolver
    @cInclude("arkode/arkode_arkstep.h"); // access to ARKStep
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

// Macros for problem constants
const PI = s.SUN_RCONST(3.141592653589793238462643383279502884197169);
const ZERO = s.SUN_RCONST(0.0);
const ONE = s.SUN_RCONST(1.0);
const TWO = s.SUN_RCONST(2.0);

const Domain = struct {
    const Coord = struct {
        ix: usize,
        iy: usize,
    };

    // Diffusion coefficients in the x and y directions
    kx: s.sunrealtype,
    ky: s.sunrealtype,

    // Final time
    tf: s.sunrealtype,

    // Upper bounds in x and y directions
    xu: s.sunrealtype,
    yu: s.sunrealtype,

    // Number of nodes in the x and y directions
    nx: s.sunindextype,
    ny: s.sunindextype,

    // Total number of nodes
    nodes: s.sunindextype,

    // Mesh spacing in the x and y directions
    dx: s.sunrealtype,
    dy: s.sunrealtype,

    // Enable/disable forcing
    forcing: bool,

    fn init(n: s.sunindextype) Domain {
        var domain: Domain = undefined;

        // Diffusion coefficient
        domain.kx = ONE;
        domain.ky = ONE;

        // Final time
        domain.tf = ONE;

        // Upper bounds in x and y directions
        domain.xu = ONE;
        domain.yu = ONE;

        // Number of nodes in the x and y directions
        domain.nx = n;
        domain.ny = n;
        domain.nodes = domain.nx * domain.ny;

        // Mesh spacing in the x and y directions
        domain.dx = domain.xu / @as(f64, @floatFromInt(domain.nx - 1));
        domain.dy = domain.yu / @as(f64, @floatFromInt(domain.ny - 1));

        domain.forcing = true;

        return domain;
    }

    fn size(self: Domain) usize {
        return @intCast(self.nodes);
    }

    fn coord2index(self: Domain, c: Coord) usize {
        std.debug.assert(c.ix < self.nx);
        std.debug.assert(c.iy < self.ny);
        return c.iy * @as(usize, @intCast(self.nx)) + c.ix;
    }

    fn index2coord(self: Domain, i: usize) Coord {
        std.debug.assert(i < self.size());
        return .{
            .ix = i % @as(usize, @intCast(self.nx)),
            .iy = @divFloor(i, @as(usize, @intCast(self.nx))) % @as(usize, @intCast(self.ny)),
        };
    }

    // f routine to compute the ODE RHS function f(t,y).
    export fn f(
        t: s.sunrealtype,
        u: s.N_Vector,
        u_dot: s.N_Vector,
        user_data: ?*anyopaque,
    ) i32 {
        // Start timer
        var timer = std.time.Timer.start() catch return -1;

        // Access problem data
        const solver: *Solver = @alignCast(@ptrCast(user_data));
        const udata: *const Domain = solver.domain;

        // Shortcuts to number of nodes
        const nx: usize = @intCast(udata.nx);
        const ny: usize = @intCast(udata.ny);

        // Constants for computing diffusion term
        const cx: s.sunrealtype = udata.kx / (udata.dx * udata.dx);
        const cy: s.sunrealtype = udata.ky / (udata.dy * udata.dy);
        const cc: s.sunrealtype = -TWO * (cx + cy);

        // Access data arrays
        const uarray = checkedMemOp(s.N_VGetArrayPointer, .{u}) catch return -1;
        const farray = checkedMemOp(s.N_VGetArrayPointer, .{u_dot}) catch return -1;

        // Initialize rhs vector to zero (handles boundary conditions)
        s.N_VConst(ZERO, u_dot);

        // Iterate over domain interior and compute rhs forcing term
        if (udata.forcing) {
            const bx: s.sunrealtype = (udata.kx) * TWO * PI * PI;
            const by: s.sunrealtype = (udata.ky) * TWO * PI * PI;

            const sin_t_cos_t: s.sunrealtype = std.math.sin(PI * t) * std.math.cos(PI * t);
            const cos_sqr_t: s.sunrealtype = std.math.cos(PI * t) * std.math.cos(PI * t);

            for (1..(ny - 1)) |j| {
                for (1..(nx - 1)) |i| {
                    const x: s.sunrealtype = @as(s.sunrealtype, @floatFromInt(i)) * udata.dx;
                    const y: s.sunrealtype = @as(s.sunrealtype, @floatFromInt(j)) * udata.dy;

                    const sin_sqr_x: s.sunrealtype = std.math.sin(PI * x) * std.math.sin(PI * x);
                    const sin_sqr_y: s.sunrealtype = std.math.sin(PI * y) * std.math.sin(PI * y);

                    const cos_sqr_x: s.sunrealtype = std.math.cos(PI * x) * std.math.cos(PI * x);
                    const cos_sqr_y: s.sunrealtype = std.math.cos(PI * y) * std.math.cos(PI * y);

                    farray[udata.coord2index(.{ .ix = i, .iy = j })] =
                        -TWO * PI * sin_sqr_x * sin_sqr_y * sin_t_cos_t -
                        bx * (cos_sqr_x - sin_sqr_x) * sin_sqr_y * cos_sqr_t -
                        by * (cos_sqr_y - sin_sqr_y) * sin_sqr_x * cos_sqr_t;
                }
            }
        }

        // Iterate over domain interior and add rhs diffusion term
        for (1..(ny - 1)) |j| {
            for (1..(nx - 1)) |i| {
                farray[udata.coord2index(.{ .ix = i, .iy = j })] +=
                    cc * uarray[udata.coord2index(.{ .ix = i, .iy = j })] +
                    cx * (uarray[udata.coord2index(.{ .ix = i - 1, .iy = j })] + uarray[udata.coord2index(.{ .ix = i + 1, .iy = j })]) +
                    cy * (uarray[udata.coord2index(.{ .ix = i, .iy = j - 1 })] + uarray[udata.coord2index(.{ .ix = i, .iy = j + 1 })]);
            }
        }

        // Update timer
        solver.rhstime += @as(f64, @floatFromInt(timer.read())) / std.time.ns_per_s;

        // Return success
        return 0;
    }

    fn printData(self: Domain) void {
        std.log.info("", .{});
        std.log.info("2D Heat PDE test problem:", .{});
        std.log.info(" --------------------------------- ", .{});
        std.log.info("  kx             = {}", .{self.kx});
        std.log.info("  ky             = {}", .{self.ky});
        std.log.info("  tf             = {}", .{self.tf});
        std.log.info("  xu             = {}", .{self.xu});
        std.log.info("  yu             = {}", .{self.yu});
        std.log.info("  nx             = {}", .{self.nx});
        std.log.info("  ny             = {}", .{self.ny});
        std.log.info("  dx             = {}", .{self.dx});
        std.log.info("  dy             = {}", .{self.dy});
        std.log.info("  forcing        = {}", .{self.forcing});
        std.log.info(" --------------------------------- ", .{});
    }

    fn solution(self: Domain, t: s.sunrealtype, u: s.N_Vector) !void {
        // Constants for computing solution
        const cos_sqr_t: s.sunrealtype = std.math.cos(PI * t) * std.math.cos(PI * t);

        // Initialize u to zero (handles boundary conditions)
        s.N_VConst(ZERO, u);

        const uarray = try checkedMemOp(s.N_VGetArrayPointer, .{u});

        for (1..@intCast(self.ny - 1)) |j| {
            for (1..@intCast(self.nx - 1)) |i| {
                const x: s.sunrealtype = @as(s.sunrealtype, @floatFromInt(i)) * self.dx;
                const y: s.sunrealtype = @as(s.sunrealtype, @floatFromInt(j)) * self.dy;

                const sin_sqr_x: s.sunrealtype = std.math.sin(PI * x) * std.math.sin(PI * x);
                const sin_sqr_y: s.sunrealtype = std.math.sin(PI * y) * std.math.sin(PI * y);

                uarray[self.coord2index(.{ .ix = i, .iy = j })] = sin_sqr_x * sin_sqr_y * cos_sqr_t;
            }
        }
    }

    fn solutionError(self: Domain, t: s.sunrealtype, u: s.N_Vector, e: s.N_Vector) !void {
        // Compute true solution
        try self.solution(t, e);

        // Compute absolute error
        s.N_VLinearSum(ONE, u, -ONE, e, e);
        s.N_VAbs(e, e);
    }
};

const Solver = struct {
    const Options = struct {
        // Integrator settings
        rtol: s.sunrealtype, // relative tolerance
        atol: s.sunrealtype, // absolute tolerance
        hfixed: s.sunrealtype, // fixed step size
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
        epslin: s.sunrealtype, // linear solver tolerance factor

        // Output variables
        output: i32, // output level
        nout: i32, // number of output times
        timing: bool, // print timings

        fn default() Options {
            var opts: Options = undefined;

            // Integrator settings
            opts.rtol = s.SUN_RCONST(1e-5); // relative tolerance
            opts.atol = s.SUN_RCONST(1e-10); // absolute tolerance
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

    ctx: s.SUNContext, // The SUNDIALS context object for this simulation
    arkode_mem: ?*anyopaque, // ARKODE memory structure
    LS: s.SUNLinearSolver, // linear solver memory structure
    C: s.SUNAdaptController, // Adaptivity controller

    domain: *const Domain,
    d: s.N_Vector, // Inverse of Jacobian diagonal for preconditioner
    u: s.N_Vector, // vector for storing solution
    e: s.N_Vector, // error vector

    // Timing variables
    evolvetime: f64 = 0.0,
    rhstime: f64 = 0.0,
    psetuptime: f64 = 0.0,
    psolvetime: f64 = 0.0,

    // Preconditioner setup routine
    export fn PSetup(
        _: s.sunrealtype,
        _: s.N_Vector,
        _: s.N_Vector,
        _: s.sunbooleantype,
        _: [*c]s.sunbooleantype,
        gamma: s.sunrealtype,
        user_data: ?*anyopaque,
    ) i32 {
        // Start timer
        var timer = std.time.Timer.start() catch return -1;

        // Access problem data
        const solver: *Solver = @alignCast(@ptrCast(user_data));
        const udata: *const Domain = solver.domain;

        // Access data array
        _ = checkedMemOp(s.N_VGetArrayPointer, .{solver.d}) catch return -1;

        // Constants for computing diffusion
        const cx: s.sunrealtype = udata.kx / (udata.dx * udata.dx);
        const cy: s.sunrealtype = udata.ky / (udata.dy * udata.dy);
        const cc: s.sunrealtype = -TWO * (cx + cy);

        // Set all entries of d to the inverse diagonal values of interior
        // (since boundary RHS is 0, set boundary diagonals to the same)
        const c: s.sunrealtype = ONE / (ONE - gamma * cc);
        s.N_VConst(c, solver.d);

        // Update timer
        solver.psetuptime += @as(f64, @floatFromInt(timer.read())) / std.time.ns_per_s;

        // Return success
        return 0;
    }

    // Preconditioner solve routine for Pz = r
    export fn PSolve(
        _: s.sunrealtype,
        _: s.N_Vector,
        _: s.N_Vector,
        r: s.N_Vector,
        z: s.N_Vector,
        _: s.sunrealtype,
        _: s.sunrealtype,
        _: i32,
        user_data: ?*anyopaque,
    ) i32 {
        // Start timer
        var timer = std.time.Timer.start() catch return -1;

        // Access user_data structure
        const solver: *Solver = @alignCast(@ptrCast(user_data));

        // Perform Jacobi iteration
        s.N_VProd(solver.d, r, z);

        // Update timer
        solver.psolvetime += @as(f64, @floatFromInt(timer.read())) / std.time.ns_per_s;

        // Return success
        return 0;
    }

    fn init(allocator: std.mem.Allocator, domain: *Domain, opts: Options) !*Solver {
        const solver = try allocator.create(Solver);
        solver.options = opts;
        solver.domain = domain;
        solver.ctx = null;
        solver.arkode_mem = null;
        solver.LS = null;
        solver.C = null;

        try checkedCall(s.SUNContext_Create, .{ s.SUN_COMM_NULL, &solver.ctx });

        if (opts.diagnostics or opts.lsinfo) {
            var logger: s.SUNLogger = null;
            try checkedCall(s.SUNContext_GetLogger, .{ solver.ctx, &logger });
            try checkedCall(s.SUNLogger_SetInfoFilename, .{ logger, "diagnostics.txt" });
            try checkedCall(s.SUNLogger_SetDebugFilename, .{ logger, "diagnostics.txt" });
        }

        // ----------------------
        // Create serial vectors
        // ----------------------

        // Create vector for solution
        solver.u = try checkedMemOp(s.N_VNew_Serial, .{ domain.nodes, solver.ctx });

        // Set initial condition
        try domain.solution(ZERO, solver.u);

        // Create vector for error
        solver.e = try checkedMemOp(s.N_VClone, .{solver.u});

        // ---------------------
        // Create linear solver
        // ---------------------

        // Create linear solver
        const prectype: i32 = if (opts.prec) s.SUN_PREC_RIGHT else s.SUN_PREC_NONE;

        if (opts.pcg) {
            solver.LS = try checkedMemOp(s.SUNLinSol_PCG, .{ solver.u, prectype, opts.liniters, solver.ctx });
        } else {
            solver.LS = try checkedMemOp(s.SUNLinSol_SPGMR, .{ solver.u, prectype, opts.liniters, solver.ctx });
        }

        // Allocate preconditioner workspace
        if (opts.prec) {
            solver.d = try checkedMemOp(s.N_VClone, .{solver.u});
        } else {
            solver.d = null;
        }

        // --------------
        // Setup ARKODE
        // --------------

        // Create integrator
        solver.arkode_mem = try checkedMemOp(s.ARKStepCreate, .{ null, &Domain.f, ZERO, solver.u, solver.ctx });

        // Specify tolerances
        try checkedCall(s.ARKodeSStolerances, .{ solver.arkode_mem, opts.rtol, opts.atol });

        // Attach user data
        try checkedCall(s.ARKodeSetUserData, .{ solver.arkode_mem, @as(?*anyopaque, @ptrCast(solver)) });

        // Attach linear solver
        try checkedCall(s.ARKodeSetLinearSolver, .{ solver.arkode_mem, solver.LS, null });

        if (opts.prec) {
            // Attach preconditioner
            try checkedCall(s.ARKodeSetPreconditioner, .{ solver.arkode_mem, Solver.PSetup, Solver.PSolve });

            // Set linear solver setup frequency (update preconditioner)
            try checkedCall(s.ARKodeSetLSetupFrequency, .{ solver.arkode_mem, opts.msbp });
        }

        // Set linear solver tolerance factor
        try checkedCall(s.ARKodeSetEpsLin, .{ solver.arkode_mem, opts.epslin });

        // Select method order
        if (opts.order > 1) {
            // Use an ARKode provided table
            try checkedCall(s.ARKodeSetOrder, .{ solver.arkode_mem, opts.order });
        } else {
            // Use implicit Euler (requires fixed step size)
            var A: [1]s.sunrealtype = .{ONE};
            var b: [1]s.sunrealtype = .{ONE};
            var c: [1]s.sunrealtype = .{ONE};

            // Create implicit Euler Butcher table
            const B: s.ARKodeButcherTable = try checkedMemOp(
                s.ARKodeButcherTable_Create,
                .{ 1, 1, 0, &c, &A, &b, null },
            );

            // Attach the Butcher table
            try checkedCall(s.ARKStepSetTables, .{ solver.arkode_mem, 1, 0, B, null });

            // Free the Butcher table
            s.ARKodeButcherTable_Free(B);
        }

        // Set fixed step size or adaptivity method
        if (opts.hfixed > ZERO) {
            try checkedCall(s.ARKodeSetFixedStep, .{ solver.arkode_mem, opts.hfixed });
        } else {
            solver.C = switch (opts.controller) {
                0 => s.SUNAdaptController_PID(solver.ctx),
                1 => s.SUNAdaptController_PI(solver.ctx),
                2 => s.SUNAdaptController_I(solver.ctx),
                3 => s.SUNAdaptController_ExpGus(solver.ctx),
                4 => s.SUNAdaptController_ImpGus(solver.ctx),
                5 => s.SUNAdaptController_ImExGus(solver.ctx),
                // 6:=> s.SUNAdaptController_H0321(ctx.ctx),
                // 7:=> s.SUNAdaptController_H0211(ctx.ctx),
                // 8:=> s.SUNAdaptController_H211(ctx.ctx),
                // 9:=> s.SUNAdaptController_H312(ctx.ctx),
                else => return SolverError.ArgOutOfRange,
            };
            try checkedCall(s.ARKodeSetAdaptController, .{ solver.arkode_mem, solver.C });
        }

        // Specify linearly implicit non-time-dependent RHS
        if (opts.linear) {
            try checkedCall(s.ARKodeSetLinear, .{ solver.arkode_mem, 0 });
        }

        // Set max steps between outputs
        try checkedCall(s.ARKodeSetMaxNumSteps, .{ solver.arkode_mem, opts.maxsteps });

        // Set stopping time
        try checkedCall(s.ARKodeSetStopTime, .{ solver.arkode_mem, domain.tf });

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

        checkedCall(s.ARKodeGetNumSteps, .{ self.arkode_mem, &nst }) catch {
            std.log.err("Unable to ARKodeGetNumSteps", .{});
        };
        checkedCall(s.ARKodeGetNumStepAttempts, .{ self.arkode_mem, &nst_a }) catch {
            std.log.err("Unable to ARKodeGetNumStepAttempts", .{});
        };
        checkedCall(s.ARKodeGetNumErrTestFails, .{ self.arkode_mem, &netf }) catch {
            std.log.err("Unable to ARKodeGetNumErrTestFails", .{});
        };
        checkedCall(s.ARKodeGetNumRhsEvals, .{ self.arkode_mem, 1, &nfi }) catch {
            std.log.err("Unable to ARKodeGetNumRhsEvals", .{});
        };
        checkedCall(s.ARKodeGetNumNonlinSolvIters, .{ self.arkode_mem, &nni }) catch {
            std.log.err("Unable to ARKodeGetNumNonlinSolvIters", .{});
        };
        checkedCall(s.ARKodeGetNumNonlinSolvConvFails, .{ self.arkode_mem, &ncfn }) catch {
            std.log.err("Unable to ARKodeGetNumNonlinSolvConvFails", .{});
        };
        checkedCall(s.ARKodeGetNumLinIters, .{ self.arkode_mem, &nli }) catch {
            std.log.err("Unable to ARKodeGetNumLinIters", .{});
        };
        checkedCall(s.ARKodeGetNumLinConvFails, .{ self.arkode_mem, &nlcf }) catch {
            std.log.err("Unable to ARKodeGetNumLinConvFails", .{});
        };
        checkedCall(s.ARKodeGetNumLinSolvSetups, .{ self.arkode_mem, &nsetups }) catch {
            std.log.err("Unable to ARKodeGetNumLinSolvSetups", .{});
        };
        checkedCall(s.ARKodeGetNumLinRhsEvals, .{ self.arkode_mem, &nfi_ls }) catch {
            std.log.err("Unable to ARKodeGetNumLinRhsEvals", .{});
        };
        checkedCall(s.ARKodeGetNumJtimesEvals, .{ self.arkode_mem, &nJv }) catch {
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
        const avgnli: s.sunrealtype = @as(s.sunrealtype, @floatFromInt(nni)) / @as(s.sunrealtype, @floatFromInt(nst_a));
        const avgli: s.sunrealtype = @as(s.sunrealtype, @floatFromInt(nli)) / @as(s.sunrealtype, @floatFromInt(nni));
        std.log.info("  Avg NLS iters per step attempt = {d:.6}", .{avgnli});
        std.log.info("  Avg LS iters per NLS iter      = {d:.6}", .{avgli});
        std.log.info("", .{});

        // Get preconditioner stats
        if (self.options.prec) {
            var npe: c_long = undefined;
            var nps: c_long = undefined;

            checkedCall(s.ARKodeGetNumPrecEvals, .{ self.arkode_mem, &npe }) catch {
                std.log.err("Unable to ARKodeGetNumPrecEvals", .{});
            };
            checkedCall(s.ARKodeGetNumPrecSolves, .{ self.arkode_mem, &nps }) catch {
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
        s.ARKodeFree(&self.arkode_mem); // Free integrator memory
        _ = s.SUNLinSolFree(self.LS); // Free linear solver
        s.N_VDestroy(self.u); // Free vectors
        s.N_VDestroy(self.d); // Free vectors
        s.N_VDestroy(self.e); // Free vectors
        _ = s.SUNAdaptController_Destroy(self.C); // Free time adaptivity controller
        _ = s.SUNContext_Free(&self.ctx); // Free context

        allocator.destroy(self);
    }
};

fn OpenOutput(solver: *const Solver) void {
    // Header for status output
    if (solver.options.output > 0) {
        if (solver.domain.forcing) {
            std.log.info("          t                     ||u||_rms                max error      ", .{});
            std.log.info(" -----------------------------------------------------------------------", .{});
        } else {
            std.log.info("          t                     ||u||_rms      ", .{});
            std.log.info(" ----------------------------------------------", .{});
        }
    }
}

fn WriteOutput(solver: *const Solver, t: s.sunrealtype) void {
    if (solver.options.output > 0) {
        const udata: *const Domain = solver.domain;

        // Compute rms norm of the state
        const urms: s.sunrealtype = std.math.sqrt(
            s.N_VDotProd(solver.u, solver.u) / @as(f64, @floatFromInt(udata.nx)) / @as(f64, @floatFromInt(udata.ny)),
        );

        // Output current status
        if (udata.forcing) {
            // Compute the error
            udata.solutionError(t, solver.u, solver.e) catch {
                std.log.err("unable to calculate solution error!", .{});
            };

            // Compute max error
            const max: s.sunrealtype = s.N_VMaxNorm(solver.e);

            std.log.info("{e:22.15}{e:25.15}{e:25.15}", .{ t, urms, max });
        } else {
            std.log.info("{e:22.15}{e:25.15}", .{ t, urms });
        }
    }
}

fn CloseOutput(solver: *const Solver) void {
    // Footer for status output
    if (solver.options.output > 0) {
        if (solver.domain.forcing) {
            std.log.info(" -----------------------------------------------------------------------", .{});
        } else {
            std.log.info(" ----------------------------------------------", .{});
        }
    }
}

const Plotter = struct {
    mesh_builder: VtuWriter.UnstructuredMeshBuilder,
    num_plotted: usize = 0,
    series_file: ?std.fs.File = null,

    fn init(allocator: std.mem.Allocator, domain: *const Domain) !Plotter {
        var self = Plotter{ .mesh_builder = VtuWriter.UnstructuredMeshBuilder.init(allocator) };

        try self.mesh_builder.reservePoints(domain.size());
        try self.mesh_builder.reserveCells(.VTK_QUAD, @intCast((domain.nx - 1) * (domain.ny - 1)));

        for (0..domain.size()) |i| {
            const coord = domain.index2coord(i);
            _ = try self.mesh_builder.addPoint(.{
                domain.dx * @as(f64, @floatFromInt(coord.ix)),
                domain.dy * @as(f64, @floatFromInt(coord.iy)),
                0,
            });
        }

        for (0..@intCast(domain.ny - 1)) |iy| {
            for (0..@intCast(domain.nx - 1)) |ix| {
                try self.mesh_builder.addCell(.VTK_QUAD, .{
                    @intCast(domain.coord2index(.{ .ix = ix, .iy = iy })),
                    @intCast(domain.coord2index(.{ .ix = ix + 1, .iy = iy })),
                    @intCast(domain.coord2index(.{ .ix = ix + 1, .iy = iy + 1 })),
                    @intCast(domain.coord2index(.{ .ix = ix, .iy = iy + 1 })),
                });
            }
        }

        return self;
    }

    fn startSeries(self: *Plotter) !void {
        const cwd = std.fs.cwd();
        self.series_file = try cwd.createFile("heat2d.vtu.series", .{});
        try self.series_file.?.writer().print("{{\n  \"file-series-version\" : \"1.0\",\n  \"files\" : [\n", .{});
    }

    fn plot(self: *Plotter, allocator: std.mem.Allocator, u: s.N_Vector, filename: []const u8) !void {
        const mesh = self.mesh_builder.getUnstructuredMesh();

        const u_array = checkedMemOp(s.N_VGetArrayPointer, .{u}) catch unreachable;
        const u_array_size = s.N_VGetLocalLength(u);
        var point_data: []const f64 = undefined;
        point_data.ptr = u_array;
        point_data.len = @intCast(u_array_size);
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

    var domain = Domain.init(32);
    domain.printData();

    const solver = try Solver.init(allocator, &domain, Solver.Options.default());
    defer solver.deinit(allocator);
    solver.printOptions();

    var plotter = try Plotter.init(allocator, solver.domain);
    defer plotter.deinit();
    var strbuf: [256]u8 = undefined;

    var t: s.sunrealtype = 0;
    const dTout: s.sunrealtype = solver.domain.tf / @as(f64, @floatFromInt(solver.options.nout));
    var tout: s.sunrealtype = dTout;

    // Initial output
    OpenOutput(solver);
    WriteOutput(solver, t);
    try plotter.startSeries();
    var filename = try std.fmt.bufPrint(&strbuf, "heat2d_t{d:0>10.6}.vtu", .{t});
    try plotter.plot(allocator, solver.u, filename);

    var timer = try std.time.Timer.start();
    for (0..@intCast(solver.options.nout)) |_| {
        try checkedCall(s.ARKodeEvolve, .{ solver.arkode_mem, tout, solver.u, &t, s.ARK_NORMAL });

        // Update timer
        solver.evolvetime += @as(f64, @floatFromInt(timer.lap())) / std.time.ns_per_s;

        // Output solution and error
        WriteOutput(solver, t);
        filename = try std.fmt.bufPrint(&strbuf, "heat2d_t{d:0>10.6}.vtu", .{t});
        try plotter.plot(allocator, solver.u, filename);

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
    var seed: u64 = undefined;
    try std.posix.getrandom(std.mem.asBytes(&seed));
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    const N = rand.intRangeAtMost(s.sunindextype, 101, 201);
    const p = Domain.init(N);

    for (0..100) |_| {
        const i = rand.uintLessThan(usize, p.size());
        const c = p.index2coord(i);
        const i_new = p.coord2index(c);
        try std.testing.expectEqual(i, i_new);
    }
}
