const std = @import("std");

const a = @import("arkode-zig");
const cm = @import("cmfem");

const Nt: usize = 100;
const T0: f64 = 0.0;
const Tf: f64 = 0.006;
const reltol: f64 = 1.0e-6;
const abstol: f64 = 1.0e-9;
const internal_substeps: usize = 10;

const fem_order: c_int = 2;
const base_uniform_refs: usize = 0;
const coeff_refiner_max_elements: c_longlong = 300_000;
const coeff_refiner_threshold: f64 = 0.03;
const coeff_refiner_nc_limit: c_int = 0;

const packet_radius: f64 = 0.1;
const packet_x0: f64 = 0.2;
const packet_y0: f64 = 0.5;
const packet_z0: f64 = 0.5;
const packet_kx: f64 = 157.0;
const packet_ky: f64 = 0.0;
const packet_kz: f64 = 0.0;
const packet_group_velocity_x: f64 = packet_kx;

const potential_center_x: f64 = 0.5;
const potential_center_y: f64 = 0.5;
const potential_center_z: f64 = 0.5;
const potential_reference_radius: f64 = 0.25;
const potential_reference_abs: f64 = 5.0e2;
const center_potential_abs: f64 = 1.6666666666666667e5;
const potential_k = potential_reference_abs * potential_reference_radius * potential_reference_radius;
const singularity_radius = @sqrt(potential_k / center_potential_abs);
const singularity_radius2 = singularity_radius * singularity_radius;

const inline_tet_mesh =
    \\MFEM INLINE mesh v1.0
    \\
    \\type = tet
    \\nx = 52
    \\ny = 26
    \\nz = 26
    \\sx = 1.0
    \\sy = 1.0
    \\sz = 1.0
;

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

/// Returns the square of a scalar value.
fn sqr(x: f64) f64 {
    return x * x;
}

/// Reads one coordinate axis from an MFEM point vector.
fn pointCoord(x: ?*const cm.CMFEM_Vector, axis: c_int) f64 {
    return cm.CMFEM_Vector_Get(x orelse @panic("null coordinate vector"), axis);
}

/// Computes the squared distance from a point to the potential center.
fn radius2FromPoint(x: ?*const cm.CMFEM_Vector) f64 {
    const xcoord = pointCoord(x, 0);
    const ycoord = pointCoord(x, 1);
    const zcoord = pointCoord(x, 2);
    return sqr(xcoord - potential_center_x) +
        sqr(ycoord - potential_center_y) +
        sqr(zcoord - potential_center_z);
}

/// Evaluates the attractive inverse-square potential with a clamped core.
fn potentialAtPoint(x: ?*const cm.CMFEM_Vector) f64 {
    return -potential_k / @max(radius2FromPoint(x), singularity_radius2);
}

/// Evaluates the positive refinement indicator matching the potential strength.
fn indicatorAtPoint(x: ?*const cm.CMFEM_Vector) f64 {
    return potential_k / @max(radius2FromPoint(x), singularity_radius2);
}

/// Evaluates the real part of the initial Gaussian wave packet.
fn packetRealAtPoint(x: ?*const cm.CMFEM_Vector) f64 {
    const xcoord = pointCoord(x, 0);
    const ycoord = pointCoord(x, 1);
    const zcoord = pointCoord(x, 2);
    const r2 = sqr(xcoord - packet_x0) + sqr(ycoord - packet_y0) + sqr(zcoord - packet_z0);
    const envelope = @exp(-r2 / (2.0 * packet_radius * packet_radius));
    const phase = packet_kx * xcoord + packet_ky * ycoord + packet_kz * zcoord;
    return envelope * @cos(phase);
}

/// Evaluates the imaginary part of the initial Gaussian wave packet.
fn packetImagAtPoint(x: ?*const cm.CMFEM_Vector) f64 {
    const xcoord = pointCoord(x, 0);
    const ycoord = pointCoord(x, 1);
    const zcoord = pointCoord(x, 2);
    const r2 = sqr(xcoord - packet_x0) + sqr(ycoord - packet_y0) + sqr(zcoord - packet_z0);
    const envelope = @exp(-r2 / (2.0 * packet_radius * packet_radius));
    const phase = packet_kx * xcoord + packet_ky * ycoord + packet_kz * zcoord;
    return envelope * @sin(phase);
}

/// C callback used by MFEM coefficients to project the x coordinate.
fn xCoordCallback(x: ?*const cm.CMFEM_Vector, context: ?*anyopaque) callconv(.c) f64 {
    _ = context;
    return pointCoord(x, 0);
}

/// C callback used by MFEM coefficients to project the y coordinate.
fn yCoordCallback(x: ?*const cm.CMFEM_Vector, context: ?*anyopaque) callconv(.c) f64 {
    _ = context;
    return pointCoord(x, 1);
}

/// C callback used by MFEM coefficients to project the z coordinate.
fn zCoordCallback(x: ?*const cm.CMFEM_Vector, context: ?*anyopaque) callconv(.c) f64 {
    _ = context;
    return pointCoord(x, 2);
}

/// C callback that exposes the real wave-packet profile to MFEM.
fn packetRealCallback(x: ?*const cm.CMFEM_Vector, context: ?*anyopaque) callconv(.c) f64 {
    _ = context;
    return packetRealAtPoint(x);
}

/// C callback that exposes the imaginary wave-packet profile to MFEM.
fn packetImagCallback(x: ?*const cm.CMFEM_Vector, context: ?*anyopaque) callconv(.c) f64 {
    _ = context;
    return packetImagAtPoint(x);
}

/// C callback that exposes the potential to MFEM.
fn potentialCallback(x: ?*const cm.CMFEM_Vector, context: ?*anyopaque) callconv(.c) f64 {
    _ = context;
    return potentialAtPoint(x);
}

/// C callback that exposes the refinement indicator to MFEM.
fn indicatorCallback(x: ?*const cm.CMFEM_Vector, context: ?*anyopaque) callconv(.c) f64 {
    _ = context;
    return indicatorAtPoint(x);
}

/// Builds a constrained mass matrix with a constant coefficient.
fn buildConstantMassMatrix(
    fes: *cm.CMFEM_FiniteElementSpace,
    ess_tdof_list: *cm.CMFEM_ArrayInt,
    coefficient: *cm.CMFEM_ConstantCoefficient,
) !*cm.CMFEM_SparseMatrix {
    const form = cm.CMFEM_BilinearForm_New(fes) orelse return error.SetupFailed;
    defer cm.CMFEM_BilinearForm_Delete(form);

    // Assemble the bilinear form, then extract the constrained true-dof matrix.
    cm.CMFEM_BilinearForm_SetDiagonalPolicyOne(form);
    cm.CMFEM_BilinearForm_AddDomainIntegratorMiCc(form, coefficient);
    cm.CMFEM_BilinearForm_Assemble(form);
    cm.CMFEM_BilinearForm_Finalize(form);
    const temp = cm.CMFEM_SparseMatrix_New() orelse return error.SetupFailed;
    defer cm.CMFEM_SparseMatrix_Delete(temp);
    cm.CMFEM_BilinearForm_FormSystemMatrixSm(form, ess_tdof_list, temp);
    return cm.CMFEM_SparseMatrix_NewCopy(temp) orelse return error.SetupFailed;
}

/// Builds a constrained mass-like matrix with a spatially varying coefficient.
fn buildFunctionMassMatrix(
    fes: *cm.CMFEM_FiniteElementSpace,
    ess_tdof_list: *cm.CMFEM_ArrayInt,
    coefficient: *cm.CMFEM_FunctionCoefficient,
) !*cm.CMFEM_SparseMatrix {
    const form = cm.CMFEM_BilinearForm_New(fes) orelse return error.SetupFailed;
    defer cm.CMFEM_BilinearForm_Delete(form);

    // Assemble the bilinear form, then extract the constrained true-dof matrix.
    cm.CMFEM_BilinearForm_SetDiagonalPolicyOne(form);
    cm.CMFEM_BilinearForm_AddDomainIntegratorMiFc(form, coefficient);
    cm.CMFEM_BilinearForm_Assemble(form);
    cm.CMFEM_BilinearForm_Finalize(form);
    const temp = cm.CMFEM_SparseMatrix_New() orelse return error.SetupFailed;
    defer cm.CMFEM_SparseMatrix_Delete(temp);
    cm.CMFEM_BilinearForm_FormSystemMatrixSm(form, ess_tdof_list, temp);
    return cm.CMFEM_SparseMatrix_NewCopy(temp) orelse return error.SetupFailed;
}

/// Builds a constrained diffusion matrix for the kinetic-energy operator.
fn buildDiffusionMatrix(
    fes: *cm.CMFEM_FiniteElementSpace,
    ess_tdof_list: *cm.CMFEM_ArrayInt,
    coefficient: *cm.CMFEM_ConstantCoefficient,
) !*cm.CMFEM_SparseMatrix {
    const form = cm.CMFEM_BilinearForm_New(fes) orelse return error.SetupFailed;
    defer cm.CMFEM_BilinearForm_Delete(form);

    // Assemble the bilinear form, then extract the constrained true-dof matrix.
    cm.CMFEM_BilinearForm_SetDiagonalPolicyOne(form);
    cm.CMFEM_BilinearForm_AddDomainIntegratorDiCc(form, coefficient);
    cm.CMFEM_BilinearForm_Assemble(form);
    cm.CMFEM_BilinearForm_Finalize(form);
    const temp = cm.CMFEM_SparseMatrix_New() orelse return error.SetupFailed;
    defer cm.CMFEM_SparseMatrix_Delete(temp);
    cm.CMFEM_BilinearForm_FormSystemMatrixSm(form, ess_tdof_list, temp);
    return cm.CMFEM_SparseMatrix_NewCopy(temp) orelse return error.SetupFailed;
}

const SetupTimer = struct {
    io: std.Io,
    last: std.Io.Timestamp,

    /// Starts a setup timer using the provided I/O clock.
    fn init(io: std.Io) SetupTimer {
        return .{
            .io = io,
            .last = std.Io.Timestamp.now(io, .awake),
        };
    }

    /// Prints the elapsed setup time since the previous timer checkpoint.
    fn print(self: *SetupTimer, comptime label: []const u8) void {
        const now = std.Io.Timestamp.now(self.io, .awake);
        const elapsed = self.last.durationTo(now);
        self.last = now;
        const seconds = @as(f64, @floatFromInt(elapsed.toNanoseconds())) /
            @as(f64, @floatFromInt(std.time.ns_per_s));
        std.debug.print("    setup {s}: {d:.3}s\n", .{ label, seconds });
    }
};

const Simulation = struct {
    mesh: *cm.CMFEM_Mesh,
    fec: *cm.CMFEM_H1FeCollection,
    fes: *cm.CMFEM_FiniteElementSpace,
    ess_bdr: *cm.CMFEM_ArrayInt,
    ess_tdof_list: *cm.CMFEM_ArrayInt,
    stiffness_mat: *cm.CMFEM_SparseMatrix,
    potential_mat: *cm.CMFEM_SparseMatrix,
    mass_diag: *cm.CMFEM_Vector,
    x_coord: *cm.CMFEM_Vector,
    y_coord: *cm.CMFEM_Vector,
    z_coord: *cm.CMFEM_Vector,
    state_real: *cm.CMFEM_Vector,
    state_imag: *cm.CMFEM_Vector,
    rhs_vec: *cm.CMFEM_Vector,
    solve_vec: *cm.CMFEM_Vector,
    real_gf: *cm.CMFEM_GridFunction,
    imag_gf: *cm.CMFEM_GridFunction,
    prob_gf: *cm.CMFEM_GridFunction,
    potential_gf: *cm.CMFEM_GridFunction,
    paraview: *cm.CMFEM_ParaViewDataCollection,
    ndofs: usize,

    /// Creates all mesh, FEM, operator, state, and output resources.
    fn init(io: std.Io) !Simulation {
        std.debug.print("\n3D Schrödinger FEM setup:\n", .{});
        var setup_timer = SetupTimer.init(io);

        // Build the base tetrahedral mesh before localized coefficient refinement.
        var mesh = cm.CMFEM_Mesh_New() orelse return error.SetupFailed;
        errdefer cm.CMFEM_Mesh_Delete(mesh);
        cm.CMFEM_Mesh_Load(mesh, inline_tet_mesh, 1, 0, 0);

        for (0..base_uniform_refs) |_| {
            cm.CMFEM_Mesh_UniformRefinement(mesh);
        }
        cm.CMFEM_Mesh_FinalizeTetMesh(mesh, 1, 1, 1);
        setup_timer.print("base tet mesh");

        // Refine around the clamped singular potential so the center is resolved.
        const indicator = cm.CMFEM_FunctionCoefficient_New(indicatorCallback, null) orelse return error.SetupFailed;
        defer cm.CMFEM_FunctionCoefficient_Delete(indicator);
        const coeff_refiner = cm.CMFEM_CoefficientRefiner_NewFc(indicator, fem_order) orelse return error.SetupFailed;
        defer cm.CMFEM_CoefficientRefiner_Delete(coeff_refiner);
        cm.CMFEM_CoefficientRefiner_SetIntRuleOrder(coeff_refiner, 2 * fem_order + 4);
        cm.CMFEM_CoefficientRefiner_SetMaxElements(coeff_refiner, coeff_refiner_max_elements);
        cm.CMFEM_CoefficientRefiner_SetThreshold(coeff_refiner, coeff_refiner_threshold);
        cm.CMFEM_CoefficientRefiner_SetNCLimit(coeff_refiner, coeff_refiner_nc_limit);
        _ = cm.CMFEM_CoefficientRefiner_PreprocessMesh(coeff_refiner, mesh);
        setup_timer.print("center refinement");

        // Convert opposite cube faces to periodic identifications.
        const periodic_mesh = cm.CMFEM_Mesh_NewPeriodic(mesh, 1.0, 1.0, 1.0) orelse return error.SetupFailed;
        cm.CMFEM_Mesh_Delete(mesh);
        mesh = periodic_mesh;
        setup_timer.print("periodic identification");

        // Create the finite element space and the empty essential-dof lists.
        const dim = cm.CMFEM_Mesh_Dimension(mesh);
        const fec = cm.CMFEM_H1FeCollection_NewOrderDim(fem_order, dim) orelse return error.SetupFailed;
        errdefer cm.CMFEM_H1FeCollection_Delete(fec);
        const fes = cm.CMFEM_FiniteElementSpace_NewMeshH1(mesh, fec) orelse return error.SetupFailed;
        errdefer cm.CMFEM_FiniteElementSpace_Delete(fes);
        setup_timer.print("finite element space");

        const ess_bdr = cm.CMFEM_ArrayInt_New() orelse return error.SetupFailed;
        errdefer cm.CMFEM_ArrayInt_Delete(ess_bdr);
        const ess_tdof_list = cm.CMFEM_ArrayInt_New() orelse return error.SetupFailed;
        errdefer cm.CMFEM_ArrayInt_Delete(ess_tdof_list);

        // Prepare coefficient objects shared by operator assembly and projections.
        const one = cm.CMFEM_ConstantCoefficient_New(1.0) orelse return error.SetupFailed;
        defer cm.CMFEM_ConstantCoefficient_Delete(one);
        const potential_coef = cm.CMFEM_FunctionCoefficient_New(potentialCallback, null) orelse return error.SetupFailed;
        defer cm.CMFEM_FunctionCoefficient_Delete(potential_coef);
        const x_coef = cm.CMFEM_FunctionCoefficient_New(xCoordCallback, null) orelse return error.SetupFailed;
        defer cm.CMFEM_FunctionCoefficient_Delete(x_coef);
        const y_coef = cm.CMFEM_FunctionCoefficient_New(yCoordCallback, null) orelse return error.SetupFailed;
        defer cm.CMFEM_FunctionCoefficient_Delete(y_coef);
        const z_coef = cm.CMFEM_FunctionCoefficient_New(zCoordCallback, null) orelse return error.SetupFailed;
        defer cm.CMFEM_FunctionCoefficient_Delete(z_coef);

        // Assemble the time-independent operators used by the Hamiltonian.
        const mass_mat = try buildConstantMassMatrix(fes, ess_tdof_list, one);
        defer cm.CMFEM_SparseMatrix_Delete(mass_mat);
        setup_timer.print("mass matrix");
        const stiffness_mat = try buildDiffusionMatrix(fes, ess_tdof_list, one);
        errdefer cm.CMFEM_SparseMatrix_Delete(stiffness_mat);
        setup_timer.print("stiffness matrix");
        const potential_mat = try buildFunctionMassMatrix(fes, ess_tdof_list, potential_coef);
        errdefer cm.CMFEM_SparseMatrix_Delete(potential_mat);
        setup_timer.print("potential matrix");

        const ndofs = @as(usize, @intCast(cm.CMFEM_FiniteElementSpace_GetTrueVSize(fes)));

        // The consistent mass solve is too expensive here, while row-sum lumping is
        // not valid for standard quadratic tetrahedra. Use the positive diagonal as
        // the diagonal mass for both evolution and diagnostics.
        const mass_diag = cm.CMFEM_Vector_NewSize(@intCast(ndofs)) orelse return error.SetupFailed;
        errdefer cm.CMFEM_Vector_Delete(mass_diag);
        cm.CMFEM_SparseMatrix_GetDiag(mass_mat, mass_diag);

        // Allocate cached coordinates, state vectors, and reusable RHS work space.
        const x_coord = cm.CMFEM_Vector_NewSize(@intCast(ndofs)) orelse return error.SetupFailed;
        errdefer cm.CMFEM_Vector_Delete(x_coord);
        const y_coord = cm.CMFEM_Vector_NewSize(@intCast(ndofs)) orelse return error.SetupFailed;
        errdefer cm.CMFEM_Vector_Delete(y_coord);
        const z_coord = cm.CMFEM_Vector_NewSize(@intCast(ndofs)) orelse return error.SetupFailed;
        errdefer cm.CMFEM_Vector_Delete(z_coord);

        const state_real = cm.CMFEM_Vector_NewSize(@intCast(ndofs)) orelse return error.SetupFailed;
        errdefer cm.CMFEM_Vector_Delete(state_real);
        const state_imag = cm.CMFEM_Vector_NewSize(@intCast(ndofs)) orelse return error.SetupFailed;
        errdefer cm.CMFEM_Vector_Delete(state_imag);
        const rhs_vec = cm.CMFEM_Vector_NewSize(@intCast(ndofs)) orelse return error.SetupFailed;
        errdefer cm.CMFEM_Vector_Delete(rhs_vec);
        const solve_vec = cm.CMFEM_Vector_NewSize(@intCast(ndofs)) orelse return error.SetupFailed;
        errdefer cm.CMFEM_Vector_Delete(solve_vec);

        // Allocate grid functions for projections, diagnostics, and output fields.
        const real_gf = cm.CMFEM_GridFunction_New(fes) orelse return error.SetupFailed;
        errdefer cm.CMFEM_GridFunction_Delete(real_gf);
        const imag_gf = cm.CMFEM_GridFunction_New(fes) orelse return error.SetupFailed;
        errdefer cm.CMFEM_GridFunction_Delete(imag_gf);
        const prob_gf = cm.CMFEM_GridFunction_New(fes) orelse return error.SetupFailed;
        errdefer cm.CMFEM_GridFunction_Delete(prob_gf);
        const potential_gf = cm.CMFEM_GridFunction_New(fes) orelse return error.SetupFailed;
        errdefer cm.CMFEM_GridFunction_Delete(potential_gf);
        cm.CMFEM_GridFunction_ProjectCoefficientFc(potential_gf, potential_coef);

        // Project physical coordinates once so diagnostics can use true-dof values.
        const coord_gf = cm.CMFEM_GridFunction_New(fes) orelse return error.SetupFailed;
        defer cm.CMFEM_GridFunction_Delete(coord_gf);
        cm.CMFEM_GridFunction_ProjectCoefficientFc(coord_gf, x_coef);
        cm.CMFEM_GridFunction_GetTrueDofs(coord_gf, x_coord);
        cm.CMFEM_GridFunction_ProjectCoefficientFc(coord_gf, y_coef);
        cm.CMFEM_GridFunction_GetTrueDofs(coord_gf, y_coord);
        cm.CMFEM_GridFunction_ProjectCoefficientFc(coord_gf, z_coef);
        cm.CMFEM_GridFunction_GetTrueDofs(coord_gf, z_coord);
        setup_timer.print("state storage");

        // Register all visualization fields with the ParaView data collection.
        const paraview = cm.CMFEM_ParaViewDataCollection_New("schrodinger3d", mesh) orelse return error.SetupFailed;
        errdefer cm.CMFEM_ParaViewDataCollection_Delete(paraview);
        cm.CMFEM_ParaViewDataCollection_SetLevelsOfDetail(paraview, 2);
        cm.CMFEM_ParaViewDataCollection_SetDataFormatBinary(paraview);
        cm.CMFEM_ParaViewDataCollection_SetHighOrderOutput(paraview, 1);
        cm.CMFEM_ParaViewDataCollection_RegisterFieldGf(paraview, "psi_real", real_gf);
        cm.CMFEM_ParaViewDataCollection_RegisterFieldGf(paraview, "psi_imag", imag_gf);
        cm.CMFEM_ParaViewDataCollection_RegisterFieldGf(paraview, "probability_density", prob_gf);
        cm.CMFEM_ParaViewDataCollection_RegisterFieldGf(paraview, "potential", potential_gf);

        return .{
            .mesh = mesh,
            .fec = fec,
            .fes = fes,
            .ess_bdr = ess_bdr,
            .ess_tdof_list = ess_tdof_list,
            .stiffness_mat = stiffness_mat,
            .potential_mat = potential_mat,
            .mass_diag = mass_diag,
            .x_coord = x_coord,
            .y_coord = y_coord,
            .z_coord = z_coord,
            .state_real = state_real,
            .state_imag = state_imag,
            .rhs_vec = rhs_vec,
            .solve_vec = solve_vec,
            .real_gf = real_gf,
            .imag_gf = imag_gf,
            .prob_gf = prob_gf,
            .potential_gf = potential_gf,
            .paraview = paraview,
            .ndofs = ndofs,
        };
    }

    /// Releases the MFEM and output resources owned by the simulation.
    fn deinit(self: *Simulation) void {
        cm.CMFEM_ParaViewDataCollection_Delete(self.paraview);
        cm.CMFEM_GridFunction_Delete(self.potential_gf);
        cm.CMFEM_GridFunction_Delete(self.prob_gf);
        cm.CMFEM_GridFunction_Delete(self.imag_gf);
        cm.CMFEM_GridFunction_Delete(self.real_gf);
        cm.CMFEM_Vector_Delete(self.solve_vec);
        cm.CMFEM_Vector_Delete(self.rhs_vec);
        cm.CMFEM_Vector_Delete(self.state_imag);
        cm.CMFEM_Vector_Delete(self.state_real);
        cm.CMFEM_Vector_Delete(self.z_coord);
        cm.CMFEM_Vector_Delete(self.y_coord);
        cm.CMFEM_Vector_Delete(self.x_coord);
        cm.CMFEM_Vector_Delete(self.mass_diag);
        cm.CMFEM_SparseMatrix_Delete(self.potential_mat);
        cm.CMFEM_SparseMatrix_Delete(self.stiffness_mat);
        cm.CMFEM_ArrayInt_Delete(self.ess_tdof_list);
        cm.CMFEM_ArrayInt_Delete(self.ess_bdr);
        cm.CMFEM_FiniteElementSpace_Delete(self.fes);
        cm.CMFEM_H1FeCollection_Delete(self.fec);
        cm.CMFEM_Mesh_Delete(self.mesh);
    }

    /// Enforces homogeneous values on the essential true dofs of a vector.
    fn zeroEssentialDofs(self: *Simulation, vector: *cm.CMFEM_Vector) void {
        cm.CMFEM_Vector_SetSubVectorAi(vector, self.ess_tdof_list, 0.0);
    }

    /// Projects, normalizes, and copies the initial wave packet into ARKODE state.
    fn initializeState(self: *Simulation, sunvec_y: a.N_Vector) !void {
        const real_coef = cm.CMFEM_FunctionCoefficient_New(packetRealCallback, null) orelse return error.SetupFailed;
        defer cm.CMFEM_FunctionCoefficient_Delete(real_coef);
        const imag_coef = cm.CMFEM_FunctionCoefficient_New(packetImagCallback, null) orelse return error.SetupFailed;
        defer cm.CMFEM_FunctionCoefficient_Delete(imag_coef);

        // Project the analytic packet and pull the true dofs into evolution vectors.
        cm.CMFEM_GridFunction_ProjectCoefficientFc(self.real_gf, real_coef);
        cm.CMFEM_GridFunction_ProjectCoefficientFc(self.imag_gf, imag_coef);
        cm.CMFEM_GridFunction_GetTrueDofs(self.real_gf, self.state_real);
        cm.CMFEM_GridFunction_GetTrueDofs(self.imag_gf, self.state_imag);
        self.zeroEssentialDofs(self.state_real);
        self.zeroEssentialDofs(self.state_imag);

        // Normalize with the same diagonal mass approximation used during evolution.
        const norm2 = self.diagonalNorm();
        if (norm2 > 0.0) {
            const scale = 1.0 / @sqrt(norm2);
            cm.CMFEM_Vector_Scale(self.state_real, scale);
            cm.CMFEM_Vector_Scale(self.state_imag, scale);
        }

        _ = self.updateGridFunctionsFromStateVectors();

        // Pack the real and imaginary true-dof vectors into SUNDIALS complex storage.
        const y = a.N_VGetCVec(sunvec_y);
        for (0..self.ndofs) |i| {
            y.data[i] = a.Complex.init(
                cm.CMFEM_Vector_Get(self.state_real, @intCast(i)),
                cm.CMFEM_Vector_Get(self.state_imag, @intCast(i)),
            );
        }
    }

    /// Copies ARKODE complex state values into the MFEM real and imaginary vectors.
    fn syncStateVectors(self: *Simulation, y: *const a.CVec) void {
        for (0..self.ndofs) |i| {
            cm.CMFEM_Vector_Set(self.state_real, @intCast(i), y.data[i].re);
            cm.CMFEM_Vector_Set(self.state_imag, @intCast(i), y.data[i].im);
        }
    }

    /// Updates output grid functions from state vectors and returns peak amplitude.
    fn updateGridFunctionsFromStateVectors(self: *Simulation) f64 {
        cm.CMFEM_GridFunction_SetFromTrueDofs(self.real_gf, self.state_real);
        cm.CMFEM_GridFunction_SetFromTrueDofs(self.imag_gf, self.state_imag);

        // Derive probability density from the reconstructed real and imaginary fields.
        const local_size = @as(usize, @intCast(cm.CMFEM_GridFunction_Size(self.real_gf)));
        var peak_amp: f64 = 0.0;
        for (0..local_size) |i| {
            const dof = @as(c_int, @intCast(i));
            const real_value = cm.CMFEM_GridFunction_Get(self.real_gf, dof);
            const imag_value = cm.CMFEM_GridFunction_Get(self.imag_gf, dof);
            const prob = real_value * real_value + imag_value * imag_value;
            cm.CMFEM_GridFunction_Set(self.prob_gf, dof, prob);
            peak_amp = @max(peak_amp, @sqrt(prob));
        }
        return peak_amp;
    }

    /// Computes the diagonal-mass approximation of the wavefunction norm squared.
    fn diagonalNorm(self: *Simulation) f64 {
        var total: f64 = 0.0;

        for (0..self.ndofs) |i| {
            const dof = @as(c_int, @intCast(i));
            const real_value = cm.CMFEM_Vector_Get(self.state_real, dof);
            const imag_value = cm.CMFEM_Vector_Get(self.state_imag, dof);
            total += cm.CMFEM_Vector_Get(self.mass_diag, dof) *
                (real_value * real_value + imag_value * imag_value);
        }

        return total;
    }

    /// Computes norm, position moments, widths, and peak amplitude diagnostics.
    fn computeDiagnostics(self: *Simulation, y: *const a.CVec) Diagnostics {
        // Synchronize solver state before updating fields and moment sums.
        self.syncStateVectors(y);
        const peak_amp = self.updateGridFunctionsFromStateVectors();

        var norm: f64 = 0.0;
        var sum_x: f64 = 0.0;
        var sum_y: f64 = 0.0;
        var sum_z: f64 = 0.0;
        var sum_x2: f64 = 0.0;
        var sum_y2: f64 = 0.0;
        var sum_z2: f64 = 0.0;

        // Accumulate diagonal-mass weighted first and second coordinate moments.
        for (0..self.ndofs) |i| {
            const dof = @as(c_int, @intCast(i));
            const real_value = cm.CMFEM_Vector_Get(self.state_real, dof);
            const imag_value = cm.CMFEM_Vector_Get(self.state_imag, dof);
            const weighted_prob = cm.CMFEM_Vector_Get(self.mass_diag, dof) *
                (real_value * real_value + imag_value * imag_value);
            const x = cm.CMFEM_Vector_Get(self.x_coord, dof);
            const y_coord = cm.CMFEM_Vector_Get(self.y_coord, dof);
            const z = cm.CMFEM_Vector_Get(self.z_coord, dof);

            norm += weighted_prob;
            sum_x += x * weighted_prob;
            sum_y += y_coord * weighted_prob;
            sum_z += z * weighted_prob;
            sum_x2 += x * x * weighted_prob;
            sum_y2 += y_coord * y_coord * weighted_prob;
            sum_z2 += z * z * weighted_prob;
        }

        if (norm <= 0.0) {
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

        // Convert raw moments to means and standard deviations.
        const x_mean = sum_x / norm;
        const y_mean = sum_y / norm;
        const z_mean = sum_z / norm;
        const x2_mean = sum_x2 / norm;
        const y2_mean = sum_y2 / norm;
        const z2_mean = sum_z2 / norm;

        return .{
            .norm = norm,
            .x_mean = x_mean,
            .y_mean = y_mean,
            .z_mean = z_mean,
            .sigma_x = @sqrt(@max(0.0, x2_mean - x_mean * x_mean)),
            .sigma_y = @sqrt(@max(0.0, y2_mean - y_mean * y_mean)),
            .sigma_z = @sqrt(@max(0.0, z2_mean - z_mean * z_mean)),
            .peak_amp = peak_amp,
        };
    }

    /// Applies the discrete Hamiltonian H = -0.5 Laplacian + V to a state vector.
    fn applyHamiltonian(self: *Simulation, state: *cm.CMFEM_Vector) void {
        cm.CMFEM_SparseMatrix_Mult(self.stiffness_mat, state, self.rhs_vec);
        cm.CMFEM_Vector_Scale(self.rhs_vec, 0.5);
        cm.CMFEM_SparseMatrix_Mult(self.potential_mat, state, self.solve_vec);
        cm.CMFEM_Vector_Add(self.rhs_vec, self.solve_vec);
    }

    /// Solves the diagonal mass approximation into the reusable solve vector.
    fn solveMass(self: *Simulation) void {
        for (0..self.ndofs) |i| {
            const dof = @as(c_int, @intCast(i));
            const mass = cm.CMFEM_Vector_Get(self.mass_diag, dof);
            const rhs = cm.CMFEM_Vector_Get(self.rhs_vec, dof);
            cm.CMFEM_Vector_Set(self.solve_vec, dof, rhs / mass);
        }
    }

    /// Saves the currently registered grid functions at one output step.
    fn save(self: *Simulation, step: usize, time: f64) void {
        cm.CMFEM_ParaViewDataCollection_SetCycle(self.paraview, @intCast(step));
        cm.CMFEM_ParaViewDataCollection_SetTime(self.paraview, time);
        cm.CMFEM_ParaViewDataCollection_Save(self.paraview);
    }
};

/// ARKODE RHS callback for the split real/imaginary Schrödinger system.
export fn Rhs(
    tn: a.sunrealtype,
    sunvec_y: a.N_Vector,
    sunvec_f: a.N_Vector,
    user_data: ?*anyopaque,
) c_int {
    _ = tn;
    const simulation: *Simulation = @ptrCast(@alignCast(user_data orelse return -1));
    const y = a.N_VGetCVec(sunvec_y);
    const f = a.N_VGetCVec(sunvec_f);

    // Bring the MFEM state vectors in sync with ARKODE's complex state.
    simulation.syncStateVectors(y);

    // d(real(psi))/dt = M^-1 H imag(psi).
    simulation.applyHamiltonian(simulation.state_imag);
    simulation.solveMass();
    for (0..simulation.ndofs) |i| {
        f.data[i].re = cm.CMFEM_Vector_Get(simulation.solve_vec, @intCast(i));
    }

    // d(imag(psi))/dt = -M^-1 H real(psi).
    simulation.applyHamiltonian(simulation.state_real);
    simulation.solveMass();
    for (0..simulation.ndofs) |i| {
        f.data[i].im = -cm.CMFEM_Vector_Get(simulation.solve_vec, @intCast(i));
    }

    return 0;
}

/// Prints selected final ARKODE solver counters.
fn ARKStepStats(arkode_mem: *anyopaque) void {
    var nsteps: c_long = 0;
    var nst_a: c_long = 0;
    var nfi: c_long = 0;
    var netfails: c_long = 0;

    _ = a.ARKodeGetNumSteps(arkode_mem, &nsteps);
    _ = a.ARKodeGetNumStepAttempts(arkode_mem, &nst_a);
    _ = a.ARKodeGetNumRhsEvals(arkode_mem, 1, &nfi);
    _ = a.ARKodeGetNumErrTestFails(arkode_mem, &netfails);

    std.debug.print("\nFinal Solver Statistics:\n", .{});
    std.debug.print("    Internal solver steps = {}, (attempted = {})\n", .{ nsteps, nst_a });
    std.debug.print("    Total implicit RHS evals = {}\n", .{nfi});
    std.debug.print("    Total number of error test failures = {}\n", .{netfails});
}

/// Runs the full 3D finite-element Schrödinger simulation.
pub fn main(init: std.process.Init) !void {
    _ = init.gpa;

    // Build FEM data structures and seed ARKODE's state vector.
    var simulation = try Simulation.init(init.io);
    defer simulation.deinit();

    var sunctx: a.SUNContext = null;
    if (a.SUNContext_Create(a.SUN_COMM_NULL, &sunctx) != 0) {
        std.debug.print("ERROR: SUNContext_Create failed\n", .{});
        return error.SetupFailed;
    }
    defer _ = a.SUNContext_Free(&sunctx);

    const sunvec_y = try a.N_VNew_Complex(@intCast(simulation.ndofs), sunctx);
    defer a.N_VDestroy_Complex(sunvec_y);
    try simulation.initializeState(sunvec_y);

    // Report the run configuration before configuring the time integrator.
    std.debug.print("\n3D Schrödinger FEM simulation on a unit cube:\n", .{});
    std.debug.print("    FE space = H1 order {}, true dofs = {}, timesteps = {}\n", .{ fem_order, simulation.ndofs, Nt });
    std.debug.print("    mesh elements after center refinement = {}\n", .{cm.CMFEM_Mesh_GetNE(simulation.mesh)});
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
    std.debug.print("    initial packet phase = exp(i k.x), continuum free-packet x velocity ~= {d:.3}\n", .{packet_group_velocity_x});
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

    // Configure ARKODE for fixed-step implicit midpoint evolution.
    var arkode_mem: ?*anyopaque = a.ARKStepCreate(null, Rhs, T0, sunvec_y, sunctx) orelse {
        std.debug.print("ERROR: ARKStepCreate failed\n", .{});
        return error.SetupFailed;
    };
    defer a.ARKodeFree(&arkode_mem);

    if (a.ARKodeSetUserData(arkode_mem.?, &simulation) != 0) {
        std.debug.print("ERROR: ARKodeSetUserData failed\n", .{});
        return error.SetupFailed;
    }
    if (a.ARKStepSetTableNum(arkode_mem.?, a.ARKODE_IMPLICIT_MIDPOINT_1_2, a.ARKODE_ERK_NONE) != 0) {
        std.debug.print("ERROR: ARKStepSetTableNum failed\n", .{});
        return error.SetupFailed;
    }

    const nls = a.SUNNonlinSol_FixedPoint(sunvec_y, 0, sunctx);
    if (nls == null) {
        std.debug.print("ERROR: SUNNonlinSol_FixedPoint failed\n", .{});
        return error.SetupFailed;
    }
    defer _ = a.SUNNonlinSolFree(nls);

    if (a.ARKodeSetNonlinearSolver(arkode_mem.?, nls) != 0) {
        std.debug.print("ERROR: ARKodeSetNonlinearSolver failed\n", .{});
        return error.SetupFailed;
    }
    if (a.ARKodeSStolerances(arkode_mem.?, reltol, abstol) != 0) {
        std.debug.print("ERROR: ARKodeSStolerances failed\n", .{});
        return error.SetupFailed;
    }
    if (a.ARKodeSetMaxNonlinIters(arkode_mem.?, 20) != 0) {
        std.debug.print("ERROR: ARKodeSetMaxNonlinIters failed\n", .{});
        return error.SetupFailed;
    }

    // Set a fixed internal step size and the first requested output time.
    var tcur: f64 = T0;
    const dTout = (Tf - T0) / @as(f64, @floatFromInt(Nt));
    const hfixed = dTout / @as(f64, @floatFromInt(internal_substeps));
    if (a.ARKodeSetFixedStep(arkode_mem.?, hfixed) != 0) {
        std.debug.print("ERROR: ARKodeSetFixedStep failed\n", .{});
        return error.SetupFailed;
    }
    var tout = T0 + dTout;

    const y = a.N_VGetCVec(sunvec_y);
    var diagnostics = simulation.computeDiagnostics(y);

    // Emit the initial diagnostics row and visualization frame.
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
    simulation.save(0, tcur);

    // Advance one output interval at a time, saving diagnostics after each interval.
    for (1..Nt + 1) |step| {
        const ierr = a.ARKodeEvolve(arkode_mem.?, tout, sunvec_y, &tcur, a.ARK_NORMAL);
        if (ierr < 0) {
            std.debug.print("ERROR: ARKodeEvolve failed, ierr = {}\n", .{ierr});
            return error.EvolveFailed;
        }

        diagnostics = simulation.computeDiagnostics(y);
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
        simulation.save(step, tcur);
        tout = @min(tout + dTout, Tf);
    }

    // Close with final solver counters and packet diagnostics.
    std.debug.print("-----------------------------------------------------------------------------------------------------------------\n", .{});
    ARKStepStats(arkode_mem.?);
    std.debug.print("Wrote ParaView output under schrodinger3d/\n", .{});
    std.debug.print("Final packet center: ({d:.6}, {d:.6}, {d:.6}), norm = {d:.6}\n\n", .{
        diagnostics.x_mean,
        diagnostics.y_mean,
        diagnostics.z_mean,
        diagnostics.norm,
    });
}
