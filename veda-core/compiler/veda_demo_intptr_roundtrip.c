// Security scope-limit test: does VedaShadowPropagation.cpp's shadow
// (Object_ID provenance) map survive a pointer being round-tripped
// through (a) `void*` and (b) `unsigned long` (uintptr_t-style) before
// being dereferenced again?
//
// VedaShadowPropagation.cpp's per-instruction dispatch loop (see the
// `for (Instruction &I : ...)` loop around line 816 of that file) has
// explicit propagation rules for GetElementPtrInst, BitCastInst,
// Load/Store (via veda_shadow_store/veda_shadow_load), PHINode, and
// direct-call pointer arguments -- confirmed by re-reading the file this
// session. It has NO dispatch case for IntToPtrInst or PtrToIntInst as a
// user-code-originated propagation edge (the file's own PtrToInt/IntToPtr
// uses are all the pass's OWN internally-generated OCL.D/OCS.D offset
// codegen, not a rule that looks up Shadow for a value coming from a
// ptrtoint/inttoptr the pass did not itself insert).
//
// Four independent sub-cases, all against ONE allocated node so the same
// object's real, single ODT Length (VEDA_RT_SLOT_SIZE) bounds every
// dereference below:
//   1. void*   round-trip, IN-BOUNDS  field read  -- must read correct value
//   2. void*   round-trip, OUT-OF-BOUNDS deref    -- must hard-trap
//   3. ulong   round-trip, IN-BOUNDS  field read  -- must read correct value
//   4. ulong   round-trip, OUT-OF-BOUNDS deref    -- expected(per hypothesis)
//                                                     to NOT trap (gap)
//
// This program runs sub-case (2) only when VEDA_DEMO_SUBCASE=2 and
// sub-case (4) only when VEDA_DEMO_SUBCASE=4 (compile-time -D flag) --
// each OOB sub-case must be its own separate ELF/run, since a real trap
// halts the whole simulation (RVMODEL_HALT_PASS/FAIL via
// veda_demo_trap_catcher.S) and never returns to run further sub-cases.
// The two IN-BOUNDS sub-cases (1,3) are both exercised together in the
// default (no -D) build, since neither one traps -- that combined run
// returns a real, checkable exit code encoding both results.
#include "../runtime/veda_rt.h"

typedef unsigned long u64;
typedef unsigned int u32;

extern void *veda_malloc_raw(u64 size, u32 *out_oid);
extern void veda_demo_install_trap_handler(void);

struct node {
  struct node *next;
  u64 value;
};

int main(void) {
  veda_rt_init(VEDA_RT_SLOT_SIZE, VEDA_PERM_LOAD | VEDA_PERM_STORE);

  u32 oid;
  struct node *n = (struct node *)veda_malloc_raw(sizeof(struct node), &oid);
  n->value = 42;
  n->next = 0;

#if VEDA_DEMO_SUBCASE == 2
  // Sub-case 2: void* round-trip, deliberately OUT-OF-BOUNDS (exactly
  // VEDA_RT_SLOT_SIZE bytes past the object's real base, same OOB offset
  // veda_demo_oob_neg.c uses).
  void *vp = (void *)n;
  struct node *n2 = (struct node *)vp;
  veda_demo_install_trap_handler();
  u64 *bad = (u64 *)((char *)n2 + VEDA_RT_SLOT_SIZE);
  u64 v = *bad;
  (void)v;
  // Reached only if the OOB access wrongly succeeded (no trap fired).
  return 99;

#elif VEDA_DEMO_SUBCASE == 4
  // Sub-case 4: unsigned long (uintptr_t-style) round-trip, deliberately
  // OUT-OF-BOUNDS, same offset.
  u64 ip = (u64)n;
  struct node *n2 = (struct node *)ip;
  veda_demo_install_trap_handler();
  u64 *bad = (u64 *)((char *)n2 + VEDA_RT_SLOT_SIZE);
  u64 v = *bad;
  (void)v;
  // Reached only if the OOB access wrongly succeeded (no trap fired).
  return 99;

#else
  // Default build: both IN-BOUNDS sub-cases (1) and (3), no trap expected
  // from either. Encode PASS/FAIL in the exit code directly (no trap
  // handler needed -- this whole path is expected to run to completion).
  void *vp = (void *)n;
  struct node *n_via_void = (struct node *)vp;
  if (n_via_void->value != 42) return 1; // sub-case 1 FAILED

  u64 ip = (u64)n;
  struct node *n_via_ulong = (struct node *)ip;
  if (n_via_ulong->value != 42) return 2; // sub-case 3 FAILED

  return 0; // both in-bounds sub-cases read correctly
#endif
}
