const std = @import("std");
const builtin = @import("builtin");

const VtuWriter = @import("vtu_writer");

const s = @cImport({
    @cInclude("ark_heat2D.h");
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

fn index2coord(domain: *const s.UserData, i: usize) struct { usize, usize } {
    const ix = i % @as(usize, @intCast(domain.nx));
    const iy = @divFloor(i, @as(usize, @intCast(domain.nx)));
    return .{ ix, iy };
}

fn coord2index(domain: *const s.UserData, ix: usize, iy: usize) usize {
    return s.IDX(ix, iy, @as(usize, @intCast(domain.nx)));
}

const Plotter = struct {
    mesh_builder: VtuWriter.UnstructuredMeshBuilder,

    fn init(allocator: std.mem.Allocator, domain: *const s.UserData) !Plotter {
        var self = Plotter{ .mesh_builder = VtuWriter.UnstructuredMeshBuilder.init(allocator) };

        const domain_size: usize = @intCast(domain.nodes);
        try self.mesh_builder.reservePoints(domain_size);
        try self.mesh_builder.reserveCells(.VTK_QUAD, @intCast((domain.nx - 1) * (domain.ny - 1)));

        for (0..domain_size) |i| {
            const coord = index2coord(domain, i);
            _ = try self.mesh_builder.addPoint(.{
                domain.dx * @as(f64, @floatFromInt(coord[0])),
                domain.dy * @as(f64, @floatFromInt(coord[1])),
                0,
            });
        }

        for (0..@intCast(domain.ny - 1)) |iy| {
            for (0..@intCast(domain.nx - 1)) |ix| {
                try self.mesh_builder.addCell(.VTK_QUAD, .{
                    @intCast(coord2index(domain, ix, iy)),
                    @intCast(coord2index(domain, ix + 1, iy)),
                    @intCast(coord2index(domain, ix + 1, iy + 1)),
                    @intCast(coord2index(domain, ix, iy + 1)),
                });
            }
        }

        return self;
    }

    fn plot(self: *const Plotter, allocator: std.mem.Allocator, u: s.N_Vector, filename: []const u8) !void {
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
    }

    fn deinit(self: *Plotter) void {
        self.mesh_builder.deinit();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.log.warn("memory leaked!", .{});
    }

    var ctx = s.ark_heat2D_init(0, null);
    if (ctx.udata == null or ctx.arkode_mem == null) {
        return SolverError.Generic;
    }

    var t: s.sunrealtype = 0;
    const dTout: s.sunrealtype = ctx.udata.*.tf / @as(f64, @floatFromInt(ctx.udata.*.nout));
    var tout: s.sunrealtype = dTout;

    var plotter = try Plotter.init(allocator, &ctx.udata.*);
    defer plotter.deinit();
    var strbuf: [256]u8 = undefined;
    var filename = try std.fmt.bufPrint(&strbuf, "heat2d_t{d:0>10.6}.vtu", .{t});

    // Initial output
    try checkedCall(s.OpenOutput, .{ctx.udata});
    try checkedCall(s.WriteOutput, .{ t, ctx.u, ctx.udata });
    try plotter.plot(allocator, ctx.u, filename);

    var timer = try std.time.Timer.start();
    for (0..@intCast(ctx.udata.*.nout)) |_| {
        try checkedCall(s.ARKodeEvolve, .{ ctx.arkode_mem, tout, ctx.u, &t, s.ARK_NORMAL });

        // Update timer
        ctx.udata.*.evolvetime += @as(f64, @floatFromInt(timer.lap())) / std.time.ns_per_s;

        // Output solution and error
        try checkedCall(s.WriteOutput, .{ t, ctx.u, ctx.udata });
        filename = try std.fmt.bufPrint(&strbuf, "heat2d_t{d:0>10.6}.vtu", .{t});
        try plotter.plot(allocator, ctx.u, filename);

        // Update output time
        tout += dTout;
        tout = if (tout > ctx.udata.*.tf) ctx.udata.*.tf else tout;
    }

    const ret = s.ark_heat2D_finish(&ctx, 0);
    if (ret != 0) {
        return SolverError.Generic;
    }
}
