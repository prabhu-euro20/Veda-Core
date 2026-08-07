// Toolchain Milestone 11 follow-up: closes the one gap TOOLCHAIN_MILESTONE_11_RESULTS.md's own
// "Not yet built" section named honestly -- a real nested veda_compartment -> veda_compartment
// call, where BOTH functions pin a local to the SAME physical register (x20/s4), was never
// actually exercised by any test in the base milestone.
//
// Why this specifically tests the SP+offset fix (not just re-tests the base milestone): the fix
// in RISCVFrameLowering.cpp materializes each spill's address as SP + a compile-time-fixed
// FixedCSRFIMap offset, not the bare offset alone. Since SSC is a single whole-region capability
// shared across every nested veda_compartment call within a compartment (SSC_STACK_SPILL_
// CAPABILITY_DESIGN.md), a bare offset would be IDENTICAL for outer_fn's own spill of its
// caller's incoming s4 and inner_fn's own spill of s4 (which, at the moment inner_fn is entered,
// holds outer_fn's own live `counter` value) -- both use RegNum=5 in FixedCSRFIMap, so both
// would compute the exact same SSC-relative offset without the fix, silently aliasing. With the
// fix, SP genuinely differs between outer_fn's own frame and the deeper frame active during
// inner_fn's call, so the two spills land at different real addresses.
//
// Expected value is precisely predictable, not just "doesn't crash": outer_fn starts counter=1
// and doubles it via inner_fn exactly `iterations` times. With iterations=5 (see
// veda_compartment_nested_entry.S), the correct result is 1*2*2*2*2*2 = 32 -- any aliasing
// corruption between the two frames' own s4 spill slots would almost certainly produce a
// different, wrong value, not merely an unclear failure.
#ifndef VEDA_COMPARTMENT_ATTR
#define VEDA_COMPARTMENT_ATTR __attribute__((veda_compartment))
#endif

static __attribute__((noinline)) VEDA_COMPARTMENT_ATTR unsigned long inner_fn(unsigned long seed) {
  register unsigned long y asm("x20");
  y = seed * 2;
  __asm__ volatile("" : : "r"(y) : "memory");
  return y;
}

VEDA_COMPARTMENT_ATTR
unsigned long outer_fn(unsigned long iterations) {
  register unsigned long counter asm("x20");
  counter = 1;
  unsigned long i = 0;
  while (i < iterations) {
    counter = inner_fn(counter);
    i++;
    __asm__ volatile("" : : "r"(counter), "r"(i) : "memory");
  }
  return counter;
}
