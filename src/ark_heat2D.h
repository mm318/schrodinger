#include <stdbool.h>

#include "nvector/nvector_serial.h"    // access to the serial N_Vector
#include "sunlinsol/sunlinsol_pcg.h"   // access to PCG SUNLinearSolver
#include "sunlinsol/sunlinsol_spgmr.h" // access to SPGMR SUNLinearSolver
#include "arkode/arkode_arkstep.h"     // access to ARKStep

#ifdef __cplusplus
extern "C" {
#endif



struct OutputFileStreams;
typedef struct OutputFileStreams OutputFileStreams;

struct UserData
{
    // Diffusion coefficients in the x and y directions
  sunrealtype kx;
  sunrealtype ky;

  // Enable/disable forcing
  bool forcing;

  // Final time
  sunrealtype tf;

  // Upper bounds in x and y directions
  sunrealtype xu;
  sunrealtype yu;

  // Number of nodes in the x and y directions
  sunindextype nx;
  sunindextype ny;

  // Total number of nodes
  sunindextype nodes;

  // Mesh spacing in the x and y directions
  sunrealtype dx;
  sunrealtype dy;

  // Integrator settings
  sunrealtype rtol;   // relative tolerance
  sunrealtype atol;   // absolute tolerance
  sunrealtype hfixed; // fixed step size
  int order;          // ARKode method order
  int controller;     // step size adaptivity method: 0=PID, 1=PI,
                      //    2=I, 3=ExpGus, 4=ImpGus, 5=ImExGus,
                      //    6=H0321, 7=H0211, 8=H211, 9=H312
  int maxsteps;       // max number of steps between outputs
  bool linear;        // enable/disable linearly implicit option
  bool diagnostics;   // output diagnostics

  // Linear solver and preconditioner settings
  bool pcg;           // use PCG (true) or GMRES (false)
  bool prec;          // preconditioner on/off
  bool lsinfo;        // output residual history
  int liniters;       // number of linear iterations
  int msbp;           // max number of steps between preconditioner setups
  sunrealtype epslin; // linear solver tolerance factor

  // Inverse of Jacobian diagonal for preconditioner
  N_Vector d;

  // Output variables
  int output;    // output level
  int nout;      // number of output times
  OutputFileStreams * ofstreams;  // output file streams
  N_Vector e;    // error vector

  // Timing variables
  bool timing; // print timings
  double evolvetime;
  double rhstime;
  double psetuptime;
  double psolvetime;
};

struct ArkHeat2DContext {
  struct UserData* udata; // user data structure
  N_Vector u;             // vector for storing solution
  SUNLinearSolver LS;     // linear solver memory structure
  void* arkode_mem;       // ARKODE memory structure
  SUNAdaptController C;   // Adaptivity controller
  SUNContext ctx;         // The SUNDIALS context object for this simulation
};

struct ArkHeat2DContext ark_heat2D_init(int argc, char* argv[]);
int ark_heat2D_finish(struct ArkHeat2DContext * ctx, const sunrealtype t);

// -----------------------------------------------------------------------------
// Functions provided to the SUNDIALS integrator
// -----------------------------------------------------------------------------

// ODE right hand side function
int f(sunrealtype t, N_Vector u, N_Vector f, void* user_data);

// Preconditioner setup and solve functions
int PSetup(sunrealtype t, N_Vector u, N_Vector f, sunbooleantype jok,
           sunbooleantype* jcurPtr, sunrealtype gamma, void* user_data);

int PSolve(sunrealtype t, N_Vector u, N_Vector f, N_Vector r, N_Vector z,
           sunrealtype gamma, sunrealtype delta, int lr, void* user_data);

// -----------------------------------------------------------------------------
// UserData and input functions
// -----------------------------------------------------------------------------

// Set the default values in the UserData structure
int InitUserData(struct UserData* udata);

// Free memory allocated within UserData
int FreeUserData(struct UserData* udata);

// -----------------------------------------------------------------------------
// Output and utility functions
// -----------------------------------------------------------------------------

// Compute the true solution
int Solution(sunrealtype t, N_Vector u, struct UserData* udata);

// Compute the solution error solution
int SolutionError(sunrealtype t, N_Vector u, N_Vector e, struct UserData* udata);

// Print the command line options
void InputHelp();

// Print some UserData information
int PrintUserData(struct UserData* udata);

// Output solution and error
int OpenOutput(struct UserData* udata);
int WriteOutput(sunrealtype t, N_Vector u, struct UserData* udata);
int CloseOutput(struct UserData* udata);

// Print integration statistics
int OutputStats(void* arkode_mem, struct UserData* udata);

// Print integration timing
int OutputTiming(struct UserData* udata);

#ifdef __cplusplus
}
#endif
