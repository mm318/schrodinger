const std = @import("std");

const nvector_complex = @import("nvector_complex");
const Complex = nvector_complex.Complex;

const nv = nvector_complex.c;
pub const c = @cImport({
    @cInclude("arkode/arkode.h");
    @cInclude("arkode/arkode_arkstep.h");
});

inline fn asNVector(v: nv.N_Vector) c.N_Vector {
    return @ptrCast(v);
}

inline fn asComplexNVector(v: c.N_Vector) nv.N_Vector {
    return @ptrCast(v);
}

inline fn asSunContext(ctx: nv.SUNContext) c.SUNContext {
    return @ptrCast(ctx);
}

inline fn asComplexSunContext(ctx: c.SUNContext) nv.SUNContext {
    return @ptrCast(ctx);
}

const neq: usize = 1;
const Nt: usize = 10;
const lambda = Complex.init(-1.0e-2, 10.0);
const T0: f64 = 0.0;
const Tf: f64 = 10.0;
const dtmax: f64 = 0.01;
const reltol: f64 = 1.0e-6;
const abstol: f64 = 1.0e-10;

export fn Rhs(tn: c.sunrealtype, sunvec_y: c.N_Vector, sunvec_f: c.N_Vector, user_data: ?*anyopaque) c_int {
    _ = tn;
    _ = user_data;
    const y = nvector_complex.N_VGetCVec(asComplexNVector(sunvec_y));
    const f = nvector_complex.N_VGetCVec(asComplexNVector(sunvec_f));

    f.data[0] = y.data[0].mul(lambda);
    return 0;
}

fn Sol(tn: f64) Complex {
    // 2.0 * exp(lambda * tn)
    // exp(x + iy) = exp(x) * (cos(y) + i sin(y))
    const lt = lambda.mul(Complex.init(tn, 0.0));
    const exp_re = @exp(lt.re);
    const c_val = Complex.init(exp_re * @cos(lt.im), exp_re * @sin(lt.im));
    return c_val.mul(Complex.init(2.0, 0.0));
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
    var sunctx: c.SUNContext = null;
    if (c.SUNContext_Create(c.SUN_COMM_NULL, &sunctx) != 0) {
        std.debug.print("ERROR: SUNContext_Create failed\n", .{});
        return;
    }
    defer _ = c.SUNContext_Free(&sunctx);

    std.debug.print("  \n", .{});
    std.debug.print("Analytical ODE test problem:\n", .{});
    std.debug.print("    lambda = ( {e} , {e} ) \n", .{ lambda.re, lambda.im });
    std.debug.print("    reltol = {e},  abstol = {e}\n", .{ reltol, abstol });

    const sunvec_y = try nvector_complex.N_VNew_Complex(@intCast(neq), asComplexSunContext(sunctx));
    defer nvector_complex.N_VDestroy_Complex(sunvec_y);
    const y = nvector_complex.N_VGetCVec(sunvec_y);

    y.data[0] = Sol(T0);

    var arkode_mem: ?*anyopaque = c.ARKStepCreate(Rhs, null, T0, asNVector(sunvec_y), sunctx) orelse {
        std.debug.print("ERROR: arkode_mem = NULL\n", .{});
        return;
    };
    defer c.ARKodeFree(&arkode_mem);

    _ = c.ARKodeSStolerances(arkode_mem.?, reltol, abstol);

    var tcur: f64 = T0;
    const dTout = (Tf - T0) / @as(f64, @floatFromInt(Nt));
    var tout = T0 + dTout;
    var yerrI: f64 = 0.0;
    var yerr2: f64 = 0.0;

    std.debug.print(" \n", .{});
    std.debug.print("      t     real(u)    imag(u)    error\n", .{});
    std.debug.print("   -------------------------------------------\n", .{});
    std.debug.print("     {d:4.1}  {e:9.2}  {e:9.2}  {e:8.1}\n", .{ tcur, y.data[0].re, y.data[0].im, 0.0 });

    for (1..Nt + 1) |_| {
        const ierr = c.ARKodeEvolve(arkode_mem.?, tout, asNVector(sunvec_y), &tcur, c.ARK_NORMAL);
        if (ierr < 0) {
            std.debug.print("Error in FARKodeEvolve, ierr = {}; halting\n", .{ierr});
            return error.EvolveFailed;
        }

        const sol = Sol(tcur);
        const diff = y.data[0].sub(sol);
        const yerr = diff.magnitude();

        if (yerr > yerrI) yerrI = yerr;
        yerr2 += yerr * yerr;

        std.debug.print("     {d:4.1}  {e:9.2}  {e:9.2}  {e:8.1}\n", .{ tcur, y.data[0].re, y.data[0].im, yerr });

        tout = @min(tout + dTout, Tf);
    }

    yerr2 = @sqrt(yerr2 / @as(f64, @floatFromInt(Nt)));
    std.debug.print("   -------------------------------------------\n", .{});

    ARKStepStats(arkode_mem.?);
    std.debug.print("    Error: max = {e:9.2}, rms = {e:9.2}\n \n", .{ yerrI, yerr2 });
}
