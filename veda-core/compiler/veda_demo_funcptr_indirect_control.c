// Mutation-test CONTROL for veda_demo_funcptr_indirect.c: byte-for-byte
// identical except g_reader is removed and read_value is called DIRECTLY
// by name. If the crash in the indirect-call sibling is really caused by
// the dangling function-pointer User (not some unrelated bug in this
// probe's own source), this control must compile and run cleanly through
// the exact same single-stage pipeline, since a direct call IS a CallInst
// user and IS correctly rewritten and IS in F->users() before erase.
#include "../runtime/veda_rt.h"

typedef unsigned long u64;
typedef unsigned int u32;

extern void *veda_malloc_raw(u64 size, u32 *out_oid);

struct node {
  u64 value;
};

unsigned long read_value(struct node *n) { return n->value; }

int main(void) {
  veda_rt_init(VEDA_RT_SLOT_SIZE, VEDA_PERM_LOAD | VEDA_PERM_STORE);

  u32 oid;
  struct node *n = (struct node *)veda_malloc_raw(sizeof(struct node), &oid);
  n->value = 42;

  // Direct call by name -- IS a CallInst user, IS correctly rewritten.
  u64 result = read_value(n);

  if (result != 42) return 1;
  return 0;
}
