const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
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
    if (result < c.SUN_SUCCESS or result < c.ARK_SUCCESS) {
        return switch (result) {
            c.SUN_ERR_ARG_CORRUPT => SolverError.ArgCorrupt,
            c.SUN_ERR_ARG_INCOMPATIBLE => SolverError.ArgIncompatible,
            c.SUN_ERR_ARG_OUTOFRANGE => SolverError.ArgOutOfRange,
            c.SUN_ERR_ARG_WRONGTYPE => SolverError.ArgWrongType,
            c.SUN_ERR_ARG_DIMSMISMATCH => SolverError.ArgDimsMismatch,
            c.SUN_ERR_GENERIC => SolverError.Generic,
            c.SUN_ERR_CORRUPT => SolverError.Corrupt,
            c.SUN_ERR_OUTOFRANGE => SolverError.OutOfRange,
            c.SUN_ERR_FILE_OPEN => SolverError.FileOpen,
            c.SUN_ERR_OP_FAIL => SolverError.OpFail,
            c.SUN_ERR_MEM_FAIL => SolverError.MemFail,
            c.SUN_ERR_MALLOC_FAIL => SolverError.MallocFail,
            c.SUN_ERR_EXT_FAIL => SolverError.ExtFail,
            c.SUN_ERR_DESTROY_FAIL => SolverError.DestroyFail,
            c.SUN_ERR_NOT_IMPLEMENTED => SolverError.NotImplemented,
            c.SUN_ERR_USER_FCN_FAIL => SolverError.UserFcnFail,
            c.SUN_ERR_PROFILER_MAPFULL => SolverError.ProfilerMapFull,
            c.SUN_ERR_PROFILER_MAPGET => SolverError.ProfilerMapGet,
            c.SUN_ERR_PROFILER_MAPINSERT => SolverError.ProfilerMapInsert,
            c.SUN_ERR_PROFILER_MAPKEYNOTFOUND => SolverError.ProfilerMapKeyNotFound,
            c.SUN_ERR_PROFILER_MAPSORT => SolverError.ProfilerMapSort,
            c.SUN_ERR_SUNCTX_CORRUPT => SolverError.SunCtxCorrupt,
            c.SUN_ERR_MPI_FAIL => SolverError.MpiFail,
            c.SUN_ERR_UNREACHABLE => SolverError.Unreachable,
            c.SUN_ERR_UNKNOWN => SolverError.Unknown,
            c.ARK_TSTOP_RETURN => SolverError.TStopReturn,
            c.ARK_ROOT_RETURN => SolverError.RootReturn,
            c.ARK_WARNING => SolverError.Warning,
            c.ARK_TOO_MUCH_WORK => SolverError.TooMuchWork,
            c.ARK_TOO_MUCH_ACC => SolverError.TooMuchAcc,
            c.ARK_ERR_FAILURE => SolverError.ErrFailure,
            c.ARK_CONV_FAILURE => SolverError.ConvFailure,
            c.ARK_LINIT_FAIL => SolverError.LInitFail,
            c.ARK_LSETUP_FAIL => SolverError.LSetupFail,
            c.ARK_LSOLVE_FAIL => SolverError.LSolveFail,
            c.ARK_RHSFUNC_FAIL => SolverError.RhsFuncFail,
            c.ARK_FIRST_RHSFUNC_ERR => SolverError.FirstRhsFuncErr,
            c.ARK_REPTD_RHSFUNC_ERR => SolverError.ReptdRhsFuncErr,
            c.ARK_UNREC_RHSFUNC_ERR => SolverError.UnrecRhsFuncErr,
            c.ARK_RTFUNC_FAIL => SolverError.RtFuncFail,
            c.ARK_LFREE_FAIL => SolverError.LFreeFail,
            c.ARK_MASSINIT_FAIL => SolverError.MassInitFail,
            c.ARK_MASSSETUP_FAIL => SolverError.MassSetupFail,
            c.ARK_MASSSOLVE_FAIL => SolverError.MassSolveFail,
            c.ARK_MASSFREE_FAIL => SolverError.MassFreeFail,
            c.ARK_MASSMULT_FAIL => SolverError.MassMultFail,
            c.ARK_CONSTR_FAIL => SolverError.ConstrFail,
            c.ARK_MEM_FAIL => SolverError.MemFail,
            c.ARK_MEM_NULL => SolverError.MemNull,
            c.ARK_ILL_INPUT => SolverError.IllInput,
            c.ARK_NO_MALLOC => SolverError.NoMalloc,
            c.ARK_BAD_K => SolverError.BadK,
            c.ARK_BAD_T => SolverError.BadT,
            c.ARK_BAD_DKY => SolverError.BadDky,
            c.ARK_TOO_CLOSE => SolverError.TooClose,
            c.ARK_VECTOROP_ERR => SolverError.VectorOpErr,
            c.ARK_NLS_INIT_FAIL => SolverError.NlsInitFail,
            c.ARK_NLS_SETUP_FAIL => SolverError.NlsSetupFail,
            c.ARK_NLS_SETUP_RECVR => SolverError.NlsSetupRecvr,
            c.ARK_NLS_OP_ERR => SolverError.NlsOpErr,
            c.ARK_INNERSTEP_ATTACH_ERR => SolverError.InnerStepAttachErr,
            c.ARK_INNERSTEP_FAIL => SolverError.InnerStepFail,
            c.ARK_OUTERTOINNER_FAIL => SolverError.OuterToInnerFail,
            c.ARK_INNERTOOUTER_FAIL => SolverError.InnerToOuterFail,
            c.ARK_POSTPROCESS_STEP_FAIL => SolverError.PostProcessStepFail,
            c.ARK_POSTPROCESS_STAGE_FAIL => SolverError.PostProcessStageFail,
            c.ARK_USER_PREDICT_FAIL => SolverError.UserPredictFail,
            c.ARK_INTERP_FAIL => SolverError.InterpFail,
            c.ARK_INVALID_TABLE => SolverError.InvalidTable,
            c.ARK_CONTEXT_ERR => SolverError.ContextErr,
            c.ARK_RELAX_FAIL => SolverError.RelaxFail,
            c.ARK_RELAX_MEM_NULL => SolverError.RelaxMemNull,
            c.ARK_RELAX_FUNC_FAIL => SolverError.RelaxFuncFail,
            c.ARK_RELAX_JAC_FAIL => SolverError.RelaxJacFail,
            c.ARK_CONTROLLER_ERR => SolverError.ControllerErr,
            c.ARK_STEPPER_UNSUPPORTED => SolverError.StepperUnsupported,
            c.ARK_DOMEIG_FAIL => SolverError.DomeigFail,
            c.ARK_MAX_STAGE_LIMIT_FAIL => SolverError.MaxStageLimitFail,
            c.ARK_SUNSTEPPER_ERR => SolverError.SunstepperErr,
            c.ARK_STEP_DIRECTION_ERR => SolverError.StepDirectionErr,
            c.ARK_UNRECOGNIZED_ERROR => SolverError.UnrecognizedError,
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

const DomainData = struct {
    Lx: c.sunrealtype, // physical size of domain in x direction
    Ly: c.sunrealtype, // physical size of domain in x direction
    Lz: c.sunrealtype, // physical size of domain in x direction
    Nx: c.sunindextype, // number of nodes in x-component of space
    Ny: c.sunindextype, // number of nodes in y-component of space
    Nz: c.sunindextype, // number of nodes in z-component of space
    dx: c.sunrealtype, // mesh spacing in x direction
    dy: c.sunrealtype, // mesh spacing in y direction
    dz: c.sunrealtype, // mesh spacing in z direction
    kx: c.sunrealtype = 0.5, // x direction heat conductivity, diffusion coefficient
    ky: c.sunrealtype = 0.3, // y direction heat conductivity, diffusion coefficient
    kz: c.sunrealtype = 0.1, // z direction heat conductivity, diffusion coefficient

    fn generate(L: c.sunrealtype, N: c.sunindextype) DomainData {
        return .{
            .Lx = L,
            .Ly = L,
            .Lz = L,
            .Nx = N,
            .Ny = N,
            .Nz = N,
            .dx = L / @as(c.sunrealtype, @floatFromInt(N - 1)),
            .dy = L / @as(c.sunrealtype, @floatFromInt(N - 1)),
            .dz = L / @as(c.sunrealtype, @floatFromInt(N - 1)),
        };
    }

    fn size(self: DomainData) c.sunindextype {
        return self.Nx * self.Ny * self.Nz;
    }

    fn index(self: DomainData, ix: usize, iy: usize, iz: usize) usize {
        std.debug.assert(ix < self.Nx);
        std.debug.assert(iy < self.Ny);
        std.debug.assert(iz < self.Nz);
        return iz * @as(usize, @intCast(self.Nx * self.Ny)) + iy * @as(usize, @intCast(self.Nx)) + ix;
    }
};

export fn f(
    t: c.sunrealtype,
    y: c.N_Vector,
    ydot: c.N_Vector,
    domain_data: ?*anyopaque,
) i32 {
    _ = t;

    const p: *const DomainData = @alignCast(@ptrCast(domain_data)); // access problem data
    const Y = checkedMemOp(c.N_VGetArrayPointer, .{y}) catch return 1;
    const Ydot = checkedMemOp(c.N_VGetArrayPointer, .{ydot}) catch return 1;
    c.N_VConst(0.0, ydot); // Initialize ydot to zero

    // iterate over domain, computing all equations
    const c1x: c.sunrealtype = p.kx / p.dx / p.dx;
    const c2x: c.sunrealtype = -2.0 * c1x;
    const c1y: c.sunrealtype = p.ky / p.dy / p.dy;
    const c2y: c.sunrealtype = -2.0 * c1y;
    const c1z: c.sunrealtype = p.kz / p.dz / p.dz;
    const c2z: c.sunrealtype = -2.0 * c1z;

    for (0..@intCast(p.Nz)) |iz| {
        for (0..@intCast(p.Ny)) |iy| {
            for (0..@intCast(p.Nx)) |ix| {
                const i = p.index(ix, iy, iz);
                if (ix == 0 or ix == p.Nx - 1 or iy == 0 or iy == p.Ny - 1 or iz == 0 or iz == p.Nz - 1) {
                    Ydot[i] = 0.0; // boundary condition: adiabatic
                } else {
                    Ydot[i] = c1x * Y[p.index(ix - 1, iy, iz)] + c2x * Y[i] + c1x * Y[p.index(ix + 1, iy, iz)] +
                        c1y * Y[p.index(ix, iy - 1, iz)] + c2y * Y[i] + c1y * Y[p.index(ix, iy + 1, iz)] +
                        c1z * Y[p.index(ix, iy, iz - 1)] + c2z * Y[i] + c1z * Y[p.index(ix, iy, iz + 1)];
                }
            }
        }
    }

    const isrc = p.index(@intCast(@divTrunc(p.Nx, 2)), @intCast(@divTrunc(p.Ny, 2)), @intCast(@divTrunc(p.Nz, 2))); // heat source location
    Ydot[isrc] += 0.01 / ((p.dx + p.dy + p.dz) / 3); // source term

    return 0; // return with success
}

pub fn main() !void {
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    const N: c.sunindextype = 101;
    var domain = DomainData.generate(1.0, N);

    const T0: c.sunrealtype = 0.0; // initial time
    const Tf: c.sunrealtype = 1.0; // final time
    const Nt: usize = 10; // total number of output times
    const rtol: c.sunrealtype = 1e-6; // relative tolerance
    const atol: c.sunrealtype = 1e-10; // absolute tolerance

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

    // Create the SUNDIALS context object for this simulation
    var ctx: c.SUNContext = undefined;
    try checkedCall(c.SUNContext_Create, .{ c.SUN_COMM_NULL, &ctx });
    defer _ = c.SUNContext_Free(&ctx);

    // Create serial vector for solution
    const y = try checkedMemOp(c.N_VNew_Serial, .{ @as(c.sunindextype, @intCast(domain.size())), ctx });
    defer c.N_VDestroy(y);
    c.N_VConst(0.0, y);

    // Call ARKStepCreate to initialize the ARK timestepper module and
    // specify the right-hand side function in y'=f(t,y), the initial time
    // T0, and the initial dependent variable vector y.  Note: since this
    // problem is fully implicit, we set f_E to NULL and f_I to f.
    var arkode_mem: ?*anyopaque = try checkedMemOp(c.ARKStepCreate, .{ null, &f, T0, y, ctx });
    defer c.ARKodeFree(&arkode_mem);

    // Set routines
    try checkedCall(c.ARKodeSetUserData, .{ arkode_mem, @as(?*anyopaque, @ptrCast(&domain)) }); // Pass udata to user functions
    try checkedCall(c.ARKodeSetMaxNumSteps, .{ arkode_mem, 10000 }); // Increase max num steps
    try checkedCall(c.ARKodeSetPredictorMethod, .{ arkode_mem, 1 }); // Specify maximum-order predictor
    try checkedCall(c.ARKodeSStolerances, .{ arkode_mem, rtol, atol }); // Specify tolerances
    const LS = try checkedMemOp(c.SUNLinSol_PCG, .{ y, 0, @as(i32, @intCast(domain.size())), ctx }); // Initialize PCG solver -- no preconditioning, with up to N iterations
    defer _ = c.SUNLinSolFree(LS);
    try checkedCall(c.ARKodeSetLinearSolver, .{ arkode_mem, LS, null }); // Attach linear solver to ARKODE
    try checkedCall(c.ARKodeSetLinear, .{ arkode_mem, 0 }); // Specify linearly implicit RHS, with non-time-dependent Jacobian

    var t = T0;
    const dTout = (Tf - T0) / Nt;
    var tout = T0 + dTout;

    std.log.info("", .{});
    std.log.info("        t      ||u||_rms", .{});
    std.log.info("   -------------------------", .{});
    std.log.info("  {d:10.6}  {d:10.6}", .{ t, @sqrt(c.N_VDotProd(y, y) / N) });

    for (0..Nt) |_| {
        checkedCall(c.ARKodeEvolve, .{ arkode_mem, tout, y, &t, c.ARK_NORMAL }) catch {
            std.log.err("Solver failure, stopping integration", .{});
            break;
        };

        // successful solve: update output time
        std.log.info("  {d:10.6}  {d:10.6}", .{ t, @sqrt(c.N_VDotProd(y, y) / N) });
        tout += dTout;
        tout = if (tout > Tf) Tf else tout;
    }

    // Print some final statistics
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
    try checkedCall(c.ARKodeGetNumSteps, .{ arkode_mem, &nst });
    try checkedCall(c.ARKodeGetNumStepAttempts, .{ arkode_mem, &nst_a });
    try checkedCall(c.ARKodeGetNumRhsEvals, .{ arkode_mem, 0, &nfe });
    try checkedCall(c.ARKodeGetNumRhsEvals, .{ arkode_mem, 1, &nfi });
    try checkedCall(c.ARKodeGetNumLinSolvSetups, .{ arkode_mem, &nsetups });
    try checkedCall(c.ARKodeGetNumErrTestFails, .{ arkode_mem, &netf });
    try checkedCall(c.ARKodeGetNumNonlinSolvIters, .{ arkode_mem, &nni });
    try checkedCall(c.ARKodeGetNumNonlinSolvConvFails, .{ arkode_mem, &ncfn });
    try checkedCall(c.ARKodeGetNumLinIters, .{ arkode_mem, &nli });
    try checkedCall(c.ARKodeGetNumJtimesEvals, .{ arkode_mem, &nJv });
    try checkedCall(c.ARKodeGetNumLinConvFails, .{ arkode_mem, &nlcf });
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

pub const std_options: std.Options = .{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        else => .info,
    },
};
