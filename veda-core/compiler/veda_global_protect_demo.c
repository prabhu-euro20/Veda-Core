// Toolchain Milestone 13: real, empirical proof that separate C
// global/static variables inside a veda_compartment function are
// protected from overflowing into each other -- directly modeled on
// veda_alloca_protect_demo.c (Milestone 12), itself modeled on the
// official CHERI "inter-object stack buffer overflow" exercise, now
// applied to module-scope globals instead of stack locals.
//
// Compiled two ways for direct comparison (see
// run_veda_global_protect_test.sh), from the SAME source, via a
// VEDA_OOB_INDEX macro:
//   - VEDA_OOB_INDEX=3 (default): writes g_lower[3], g_lower's own last
//     valid element -- fully in-bounds, must complete with a real,
//     checkable, non-trapping result.
//   - VEDA_OOB_INDEX=4: writes one element PAST g_lower[]'s own 32-byte
//     bound, which in an unprotected layout would silently corrupt
//     g_upper[]'s own first element. Under this milestone's real bounds
//     enforcement, this must hard-trap instead -- and, per this
//     milestone's own real design (individually-bounded per-global
//     capabilities, minted once at bootstrap, not one shared region
//     narrowed per access), the trap fires the instant the OOB access
//     escapes g_lower's OWN table-resident capability, before ever
//     reaching g_upper's own bytes at all -- a strictly stronger, more
//     directly CHERI-precedented property than Milestone 12's own
//     shared-region-plus-per-access-narrowing design could offer.
//
// A REAL, hardware-forced element type (not a convenience choice, the
// identical reasoning veda_alloca_protect_demo.c's own header comment
// already established): OCL.D/OCS.D are 8-byte-only; `unsigned long`
// matches the real hardware width this milestone's own dereference
// -rewrite rule requires.
//
// Accessed via a RUNTIME-VARIABLE index in the loop (matching Milestone
// 12's own `lower[i]=i` test pattern, and Toolchain Milestone 13's own
// empirically-confirmed finding that this is the more representative
// real-world access shape -- a GetElementPtrInst instruction, not a GEP
// ConstantExpr) for the initialization, and a mix of runtime-variable and
// compile-time-constant indices for the final OOB-controlled access and
// readback, exercising both real code paths Phase B1 must handle.
#ifndef VEDA_COMPARTMENT_ATTR
#define VEDA_COMPARTMENT_ATTR __attribute__((veda_compartment))
#endif
#ifndef VEDA_OOB_INDEX
#define VEDA_OOB_INDEX 3
#endif

unsigned long g_lower[4];
unsigned long g_upper[4];

VEDA_COMPARTMENT_ATTR
unsigned long veda_global_protect_thread(void) {
  for (int i = 0; i < 4; i++) {
    g_lower[i] = i;
    g_upper[i] = 100 + i;
  }
  g_lower[VEDA_OOB_INDEX] = 0xd;
  return g_lower[3] + g_upper[0];
}
