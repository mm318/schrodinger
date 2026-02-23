# Schrodinger

This project simulates a 2D time-dependent Schrödinger equation on a unit square domain using:

- SUNDIALS ARKODE for time integration
- A custom complex `N_Vector` implementation
- `vtu_writer` for per-timestep VTU output

The current program initializes a Gaussian wave packet near the left-middle of the domain and evolves it toward the right.

It also writes visualization files for each timestep:

- `schrodinger2d_t*.vtu`
- `schrodinger2d.vtu.series`

These can be loaded in ParaView as a time series.


## Requirements

- Zig 0.15.1


## Build

Build the executable:

```bash
zig build -Doptimize=ReleaseSafe
```

The binary will be outputted at `zig-out/bin/schrodinger`.


## Run

Run the simulation:

```bash
zig build -Doptimize=ReleaseSafe run
```

This will:

- print solver diagnostics to stdout
- generate `.vtu` files for each timestep
- generate `schrodinger2d.vtu.series`


## Run Tests

Run unit tests:

```bash
zig build -Doptimize=ReleaseSafe test
```

Current test coverage is focused on the custom complex `N_Vector` implementation in `test/test_nvector_complex.zig`.
