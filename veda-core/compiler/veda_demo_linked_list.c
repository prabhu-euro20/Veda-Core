// Toolchain Milestone 9 positive demo: a real 3-node linked list built via
// veda_malloc_raw, traversed via ordinary C pointer syntax (`node->next`,
// `node->value`) -- every field access on a tracked node is transparently
// rewritten by VedaShadowPropagation.cpp into real veda_rt_ocl_d/
// veda_rt_ocs_d calls (OCL.D/OCS.D under the hood) by the compiler pass,
// with zero explicit Object_ID handling in this source file at all. This
// is the real point of the whole SoftBound-style retrofit: ordinary,
// unmodified-looking C pointer code, made memory-safe by the compiler +
// hardware, not by the programmer manually tracking object handles.
#include "../runtime/veda_rt.h"

typedef unsigned long u64;
typedef unsigned int u32;

extern void *veda_malloc_raw(u64 size, u32 *out_oid);

struct node {
  struct node *next;
  u64 value;
};

int main(void) {
  veda_rt_init(VEDA_RT_SLOT_SIZE, VEDA_PERM_LOAD | VEDA_PERM_STORE);

  u64 values[3] = {10, 20, 30};
  struct node *head = 0;

  for (int i = 2; i >= 0; i--) {
    u32 oid;
    struct node *n = (struct node *)veda_malloc_raw(sizeof(struct node), &oid);
    n->value = values[i];
    n->next = head;
    head = n;
  }

  u64 sum = 0;
  int count = 0;
  struct node *cur = head;
  while (cur != 0) {
    sum += cur->value;
    count++;
    cur = cur->next;
  }

  if (count != 3) return 1;
  if (sum != 60) return 2;
  return 0;
}
