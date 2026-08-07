// Toolchain Milestone 12: real, empirical proof that separate `alloca`
// -based C local variables inside a veda_compartment function are
// protected from overflowing into each other -- directly modeled on the
// official CHERI "inter-object stack buffer overflow" exercise
// (ctsrd-cheri.github.io/cheri-exercises), the real, primary-sourced
// precedent for exactly this scenario.
//
// Compiled two ways for direct comparison (see
// run_veda_alloca_protect_test.sh), from the SAME source, via a
// VEDA_OOB_INDEX macro:
//   - VEDA_OOB_INDEX=3 (default): writes lower[3], `lower`'s own last
//     valid element -- fully in-bounds, must complete with a real,
//     checkable, non-trapping result.
//   - VEDA_OOB_INDEX=4: writes one element PAST lower[]'s own 16-byte
//     bound, which in an unprotected stack layout would silently corrupt
//     upper[]'s own first element. Under this milestone's real bounds
//     enforcement, this must hard-trap instead (a real Bounds Violation
//     via OCS.D against the narrowed, exactly-16-byte scratch capability
//     CSetBounds derives for `lower` specifically) -- the actual, honest
//     completion criterion, matching this project's own "prove it, don't
//     assert it" standard throughout every prior milestone.
#ifndef VEDA_COMPARTMENT_ATTR
#define VEDA_COMPARTMENT_ATTR __attribute__((veda_compartment))
#endif

#ifndef VEDA_OOB_INDEX
#define VEDA_OOB_INDEX 3
#endif

// Real, hardware-forced element type (not a convenience choice): Veda
// -Core's own real OCL.D/OCS.D only exist in an 8-byte width (confirmed
// from Sail source in Toolchain Milestone 5b/6 -- no .B/.H/.W variants),
// and this pass's own existing dereference-rewrite rule only redirects
// 64-bit-wide loads/stores for exactly that reason (see this file's
// VedaShadowPropagation.cpp header comment). A plain `int` (32-bit)
// array would fall outside that rule entirely and never be protected --
// `unsigned long` matches the real hardware width this milestone
// actually targets.
VEDA_COMPARTMENT_ATTR
unsigned long veda_alloca_protect_thread(void) {
  unsigned long lower[4];
  unsigned long upper[4];
  for (int i = 0; i < 4; i++) {
    lower[i] = i;
    upper[i] = 100 + i;
  }
  lower[VEDA_OOB_INDEX] = 0xd;
  return lower[3] + upper[0];
}
