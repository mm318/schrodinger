#include "nvector/nvector_serial.h"    // access to the serial N_Vector
#include "sunlinsol/sunlinsol_pcg.h"   // access to PCG SUNLinearSolver
#include "sunlinsol/sunlinsol_spgmr.h" // access to SPGMR SUNLinearSolver
#include "arkode/arkode_arkstep.h"     // access to ARKStep

#ifdef __cplusplus
extern "C" {
#endif

struct UserData;
typedef struct UserData UserData;

typedef struct ArkHeat2DContext {
  UserData* udata;      // user data structure
  N_Vector u;           // vector for storing solution
  SUNLinearSolver LS;   // linear solver memory structure
  void* arkode_mem;     // ARKODE memory structure
  SUNAdaptController C; // Adaptivity controller
  SUNContext ctx;       // The SUNDIALS context object for this simulation
} ArkHeat2DContext;

ArkHeat2DContext ark_heat2D_init(int argc, char* argv[]);
int ark_heat2D_finish(ArkHeat2DContext * ctx, const sunrealtype t);

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
int InitUserData(UserData* udata);

// Free memory allocated within UserData
int FreeUserData(UserData* udata);

// -----------------------------------------------------------------------------
// Output and utility functions
// -----------------------------------------------------------------------------

// Compute the true solution
int Solution(sunrealtype t, N_Vector u, UserData* udata);

// Compute the solution error solution
int SolutionError(sunrealtype t, N_Vector u, N_Vector e, UserData* udata);

// Print the command line options
void InputHelp();

// Print some UserData information
int PrintUserData(UserData* udata);

// Output solution and error
int OpenOutput(UserData* udata);
int WriteOutput(sunrealtype t, N_Vector u, UserData* udata);
int CloseOutput(UserData* udata);

// Print integration statistics
int OutputStats(void* arkode_mem, UserData* udata);

// Print integration timing
int OutputTiming(UserData* udata);

#ifdef __cplusplus
}
#endif
