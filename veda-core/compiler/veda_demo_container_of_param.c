// Toolchain Milestone 18 follow-up (research demo, not a shipped milestone
// number): empirically tests whether the already-proven container_of()
// backward-reconstruction pattern (veda_demo_container_of.c,
// TOOLCHAIN_MILESTONE_18_CONTAINER_OF_RESULTS.md) still works when the
// FIELD POINTER container_of starts from crosses a REAL function-call
// boundary, instead of being used inline in the same function that took
// its address -- an explicitly-named open item in that milestone's own
// "Honest scope limits" section.
//
// Two shapes tested in one file (both required by the assignment):
//
//   Shape A (reconstruct-and-return): a separate function
//     `struct container *reconstruct(struct link_node *l)` performs the
//     container_of subtraction and RETURNS the reconstructed pointer;
//     main() dereferences fields on it AFTER the call returns.
//
//   Shape B (reconstruct-and-consume-internally): a separate function
//     `unsigned long reconstruct_and_read_payload(struct link_node *l)`
//     performs the SAME container_of subtraction but also does the
//     dereference itself, inside the callee, returning only a plain
//     scalar (not a pointer) to main().
//
// Hypothesis (stated BEFORE building or running anything):
//
// Independently re-read from VedaShadowPropagation.cpp this session (not
// copied from any prior doc):
//
//   1. Phase A (rewriteSignatures, ~line 403-473) appends a trailing i32
//      shadow parameter for every POINTER-TYPED PARAMETER of every
//      module-defined, non-runtime-helper function, uniformly -- confirmed
//      by direct re-reading, applies regardless of the C-level pointee
//      type. So `reconstruct(struct link_node *l)` and
//      `reconstruct_and_read_payload(struct link_node *l)` both get a
//      real appended `l.shadow` i32 parameter, and the CallInst-rewriting
//      loop (~line 1108-1138) DOES look up the caller's Shadow value for
//      `l` (== `&c->link`, itself GEP-derived from the tracked
//      veda_malloc_raw pointer, so a real Shadow entry exists for it in
//      main()) and writes it into that appended slot at the call site.
//      This half of the plumbing -- passing shadow INTO a callee via a
//      parameter -- is real and should work for BOTH shapes.
//
//   2. Inside the callee, propagateInFunction's own parameter-seeding code
//      (~line 752-764, "Seed: pointer parameters <-> the shadow parameter
//      Phase A appended for them") populates the callee's OWN local
//      Shadow map from `F.getArg(PPI->second[K])` <-> the matching
//      appended shadow argument, BEFORE the rest of the function body is
//      walked. So inside `reconstruct`/`reconstruct_and_read_payload`,
//      `l` starts out tracked, and the GEP that computes `back = (char*)l
//      - offsetof(...)` is the SAME sign-agnostic GEP-propagation case
//      already proven in M18 (`if (Value *S = Shadow.lookup(GEP->getPointerOperand()))
//      Shadow[GEP] = S;` -- no index-sign special-casing). So `back`
//      itself IS tracked inside the callee. This predicts Shape B
//      (dereference happens INSIDE the callee, on a locally-tracked
//      `back`) should work identically to the original inline M18 demo,
//      because from the pass's point of view nothing distinguishes "GEP
//      operand came from a load of a malloc'd base" from "GEP operand
//      came from a shadow-seeded parameter" -- both are just entries
//      already present in the local Shadow DenseMap when the GEP is
//      visited.
//
//   3. The load-bearing GAP, independently re-confirmed this session by
//      grepping the ENTIRE file for `ReturnInst`/`RetInst` handling: there
//      is NONE. The only place `Shadow[Call] = ...` is ever written for a
//      CallInst's OWN result is the single hard-coded special case for
//      `Callee->getName() == kMallocRawName` (~line 1110-1124), which
//      manufactures a shadow value out of the OUT-PARAMETER slot of
//      veda_malloc_raw specifically -- there is no general "does this
//      call's return value need a shadow, and if so, where does it come
//      from" logic for ordinary module-defined functions returning a
//      pointer. This means Shape A's call site (`struct container *back =
//      reconstruct(l);` in main()) can NEVER acquire a Shadow map entry
//      for `back` no matter what happens inside `reconstruct` -- the
//      return-value shadow is simply never wired up, symmetric-opposite of
//      the (real, working) parameter-passing direction.
//
//   Prediction: Shape B (dereference inside the callee, return only a
//   scalar) should reproduce M18's clean SUCCESS, because it never asks
//   the pass to carry a shadow value back OUT of a call. Shape A
//   (dereference in main() on the call's returned pointer) should FAIL --
//   not by hard-trapping (a real, hardware-checked bounds violation) but
//   by SILENTLY becoming an ordinary, unrewritten load/store against the
//   raw pointer bit-pattern (kVedaNullBase + offset, i.e. addresses near
//   0x1000-0x1010), since Shadow.lookup(back) will simply miss in main()
//   and the pass's own dereference-rewrite rule only fires when that
//   lookup succeeds (VedaShadowPropagation.cpp ~line 922, "if (Value
//   *AddrShadow = Shadow.lookup(Addr))" -- no shadow, no rewrite, falls
//   through to a plain, real riscv load/store at a near-null address that
//   almost certainly has no real backing memory mapped there in this
//   linked image, so a genuine implementation-level fault (not a Veda-Core
//   capability trap) is the most likely real outcome).
//
// This file exists to CONFIRM or REFUTE this prediction empirically for
// BOTH shapes, not to assert it -- see the real IR dumps and the real
// sail_riscv_sim PASS/FAIL/CRASH captured alongside this build.

#include "../runtime/veda_rt.h"

typedef unsigned long u64;
typedef unsigned int u32;

extern void *veda_malloc_raw(u64 size, u32 *out_oid);

struct link_node {
  struct link_node *next;
};

struct container {
  u64 tag;
  struct link_node link;
  u64 payload;
};

#define container_of(ptr, type, member) \
  ((type *)((char *)(ptr) - __builtin_offsetof(type, member)))

// Shape A: reconstruct in a real callee, RETURN the pointer, dereference
// back in main() -- exercises the (per hypothesis #3) missing
// return-value-shadow path.
struct container *reconstruct(struct link_node *l) {
  return container_of(l, struct container, link);
}

// Shape B: reconstruct AND dereference both inside the callee, return only
// a plain scalar -- exercises the (per hypothesis #1/#2) real,
// parameter-shadow-seeding path, without ever needing a call's return
// value to carry a shadow.
u64 reconstruct_and_read_payload(struct link_node *l) {
  struct container *back = container_of(l, struct container, link);
  return back->payload;
}

int main(void) {
  veda_rt_init(VEDA_RT_SLOT_SIZE, VEDA_PERM_LOAD | VEDA_PERM_STORE);

  u32 oid;
  struct container *c =
      (struct container *)veda_malloc_raw(sizeof(struct container), &oid);
  c->tag = 0xBBBB;
  c->link.next = 0;
  c->payload = 54321;

  struct link_node *l = &c->link;

#if defined(TEST_SHAPE_B_ONLY)
  // Shape B only: helper does reconstruction + dereference internally.
  u64 got_payload_b = reconstruct_and_read_payload(l);
  if (got_payload_b != 54321) return 20;
  return 0;
#else
  // Shape A: reconstruct via a real call, dereference the RETURNED
  // pointer back in main() -- fields OTHER than the one container_of
  // started from, same discipline as M18's own inline demo.
  struct container *back = reconstruct(l);
  u64 got_tag_a = back->tag;
  u64 got_payload_a = back->payload;
  if (got_tag_a != 0xBBBB) return 1;
  if (got_payload_a != 54321) return 2;

  // Shape B: helper does reconstruction + dereference internally, returns
  // only the scalar.
  u64 got_payload_b = reconstruct_and_read_payload(l);
  if (got_payload_b != 54321) return 20;

  return 0; // SUCCESS: both shapes correctly reconstructed and read back
            // the real, originally-stored data across a real function-call
            // boundary.
#endif
}
