// Veda-Core Toolchain Milestone 11: direct, empirical negation of Milestone 10's
// own rejected Attempt 2. TOOLCHAIN_MILESTONE_10_RESULTS.md documents that this
// exact pattern -- a function-local register-pinned counter -- still emitted an
// ABI-mandated callee-saved-register spill (`sd s4, 8(sp)` at -O1) in its own
// prologue, because the ABI requires preserving the caller's incoming value of
// a callee-saved register even when the function pins a local variable to it.
// That spill hard-traps under Milestone 19's purecap rule inside a live
// OCInvoke-bound compartment -- the real problem this milestone (`veda_compartment`
// + SSC) exists to close.
//
// Compiled two ways for direct comparison (see run_veda_compartment_demo_test.sh):
//   - WITHOUT __attribute__((veda_compartment)): reproduces M10's exact failure,
//     kept as a documented negative control that still traps.
//   - WITH the attribute: the identical spill is redirected through OCS.D/OCL.D
//     against the SSC-shadow capability register (C15) instead of ordinary
//     sd/ld, so it survives running inside a live compartment.
#ifndef VEDA_COMPARTMENT_ATTR
#define VEDA_COMPARTMENT_ATTR __attribute__((veda_compartment))
#endif

// A bounded (returning) function, not an infinite loop, so the ABI-mandated
// preserve-on-return contract for the pinned callee-saved register is
// unambiguous -- LLVM can (and does, for a provably-infinite loop) elide a
// callee-saved spill entirely when a function never returns, which would
// make this test depend on that optimization decision rather than on the
// purecap-vs-SSC question this milestone actually targets.
//
// `counter` is threaded through an inert inline-asm barrier as a real input
// operand (and the whole loop guarded by "memory") so the optimizer cannot
// prove the loop is a no-op and elide it -- the first version of this test
// (no asm operand) was optimized away entirely, since `return counter` was
// provably equal to the unmodified input `iterations`. This version
// genuinely forces `counter` to be materialized in the pinned register
// x20/s4 on every iteration. Deliberately no `ecall` here (unlike the real
// scheduler thread bodies): this test's own scope is narrower and more
// direct -- prove the spill/reload sequence itself doesn't purecap-trap,
// not exercise a full trap/resume cycle (already proven separately by the
// Minimal OS Kernel scheduler milestone). The caller does ordinary
// function-call/return, entering and leaving the compartment via two real
// OCInvoke instructions in the hand-written entry point.
VEDA_COMPARTMENT_ATTR
unsigned long veda_compartment_demo_thread(unsigned long iterations) {
  register unsigned long counter asm("x20");
  counter = 0;
  while (counter < iterations) {
    counter++;
    __asm__ volatile("" : : "r"(counter) : "memory");
  }
  return counter;
}
