const std = @import("std");
const builtin = @import("builtin");

const VtuWriter = @import("vtu_writer");

const c = @cImport({
    @cInclude("ark_heat2D.h");
});

pub fn main() !void {
    var ctx = c.ark_heat2D_init(0, null);
    if (ctx.udata == null or ctx.arkode_mem == null) {
        return error.GeneralFailure;
    }

    // // -----------------------
    // // Loop over output times
    // // -----------------------

    // sunrealtype t     = ZERO;
    // sunrealtype dTout = udata->tf / udata->nout;
    // sunrealtype tout  = dTout;

    // // Initial output
    // flag = OpenOutput(udata);
    // if (check_flag(&flag, "OpenOutput", 1)) { return 1; }

    // flag = WriteOutput(t, u, udata);
    // if (check_flag(&flag, "WriteOutput", 1)) { return 1; }

    // for (int iout = 0; iout < udata->nout; iout++)
    // {
    //   // Start timer
    //   t1 = chrono::steady_clock::now();

    //   // Evolve in time
    //   flag = ARKodeEvolve(arkode_mem, tout, u, &t, ARK_NORMAL);
    //   if (check_flag(&flag, "ARKodeEvolve", 1)) { break; }

    //   // Stop timer
    //   t2 = chrono::steady_clock::now();

    //   // Update timer
    //   udata->evolvetime += chrono::duration<double>(t2 - t1).count();

    //   // Output solution and error
    //   flag = WriteOutput(t, u, udata);
    //   if (check_flag(&flag, "WriteOutput", 1)) { return 1; }

    //   // Update output time
    //   tout += dTout;
    //   tout = (tout > udata->tf) ? udata->tf : tout;
    // }

    // // Close output
    // flag = CloseOutput(udata);
    // if (check_flag(&flag, "CloseOutput", 1)) { return 1; }

    const ret = c.ark_heat2D_finish(&ctx, 0);
    if (ret != 0) {
        return error.GeneralFailure;
    }
}
