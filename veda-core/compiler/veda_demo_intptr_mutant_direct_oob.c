// Mutation test: identical to veda_demo_intptr_roundtrip.c's sub-case 4,
// EXCEPT the unsigned-long round-trip is removed -- the OOB access derefs
// `n` (the original tracked pointer) directly. If the earlier "no trap"
// result was really caused by shadow loss at the ptrtoint/inttoptr edge
// (not some unrelated bug in the test file), removing the round-trip here
// must restore the real hard trap.
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

  veda_demo_install_trap_handler();

  // No round-trip -- deref n directly, same OOB offset.
  u64 *bad = (u64 *)((char *)n + VEDA_RT_SLOT_SIZE);
  u64 v = *bad;
  (void)v;
  return 99;
}
