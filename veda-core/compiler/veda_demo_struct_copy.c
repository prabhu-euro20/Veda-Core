// Research probe (kernel-relevant gap audit, following on from
// TOOLCHAIN_MILESTONE_20_REMAINING_FIXES_RESULTS.md): does a plain C
// struct-assignment (`a = b;`) propagate a pointer FIELD's own shadow, or
// does it lower to an opaque @llvm.memcpy the pass cannot see through?
// Real Linux idiom this mirrors: `*new_task = *old_task;`-style struct
// copies, common throughout the kernel (process/fs/net object init).
#include "../runtime/veda_rt.h"

typedef unsigned long u64;
typedef unsigned int u32;

extern void *veda_malloc_raw(u64 size, u32 *out_oid);

struct holder {
  struct node *ptr_field;
  u64 tag;
};

struct node {
  u64 value;
};

int main(void) {
  veda_rt_init(VEDA_RT_SLOT_SIZE, VEDA_PERM_LOAD | VEDA_PERM_STORE);

  u32 oid_a, oid_b;
  struct node *n = (struct node *)veda_malloc_raw(sizeof(struct node), &oid_a);
  n->value = 77;

  struct holder *src =
      (struct holder *)veda_malloc_raw(sizeof(struct holder), &oid_b);
  src->ptr_field = n;
  src->tag = 0xAAAA;

  // Plain C struct assignment -- NOT memcpy(), the more common real-world
  // shape (kernel code far more often writes `*a = *b;` or `a = b;` than
  // an explicit memcpy() call for a small, fixed-size struct).
  struct holder dst;
  dst = *src;

  // If the shadow survived the struct-copy, this dereferences the SAME
  // real tracked object through the COPIED pointer field -- a genuine
  // capability-checked read. If it did not survive, this is either a raw,
  // unprotected access (silently reads correct bits, since memcpy copies
  // real bytes) or a trap (if the copied bits don't even look like a
  // sensible fake-offset-token to whatever fallback path fires).
  u64 got = dst.ptr_field->value;

  if (dst.tag != 0xAAAA) return 1;
  if (got != 77) return 2;
  return 0;
}
