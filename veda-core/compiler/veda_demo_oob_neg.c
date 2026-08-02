// Toolchain Milestone 9 negative demo: a single node allocated, then a
// deliberate out-of-bounds field access (64 bytes past the object's real
// base -- VEDA_RT_SLOT_SIZE, the object's real, configured Length) via
// ordinary-looking pointer arithmetic. The compiler pass rewrites this
// into a real veda_rt_ocl_d call exactly as it would for any in-bounds
// access -- it does NOT itself bounds-check (real, stated scope: that is
// hardware's job) -- so this must genuinely hard-trap inside the real
// OCL.D instruction's own veda_check_access bounds check, not be silently
// caught or masked anywhere in the compiler or runtime.
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

  veda_demo_install_trap_handler();

  // Deliberately out of bounds: n's real object Length is
  // VEDA_RT_SLOT_SIZE (64) bytes; this reads 8 bytes starting exactly at
  // that boundary, entirely outside the real, allocated object.
  u64 *bad = (u64 *)((char *)n + VEDA_RT_SLOT_SIZE);
  u64 v = *bad;

  // Reached only if the out-of-bounds access wrongly succeeded --
  // veda_demo_trap_handler halts (PASS or FAIL) directly and never
  // returns here on the real, expected path.
  (void)v;
  return 99;
}
