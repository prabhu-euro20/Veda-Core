// Research probe: does writing a tracked pointer through one union
// member and reading it back through a DIFFERENT (same-offset) union
// member preserve the shadow? Real Linux idiom this mirrors: tagged
// pointers / type-punned overlays (packet header unions, `wait_queue_entry`
// -style overlays).
#include "../runtime/veda_rt.h"

typedef unsigned long u64;
typedef unsigned int u32;

extern void *veda_malloc_raw(u64 size, u32 *out_oid);

struct node {
  u64 value;
};

union tagged {
  struct node *ptr;
  u64 bits;
};

int main(void) {
  veda_rt_init(VEDA_RT_SLOT_SIZE, VEDA_PERM_LOAD | VEDA_PERM_STORE);

  u32 oid;
  struct node *n = (struct node *)veda_malloc_raw(sizeof(struct node), &oid);
  n->value = 55;

  union tagged u;
  u.ptr = n; // write through the POINTER member

  // Sub-case A: read back through the SAME member (ptr) -- must work,
  // this is not really type-punning at all.
  struct node *back_same = u.ptr;
  u64 got_same = back_same->value;

  // Sub-case B: read back through the OTHER (integer) member, then cast
  // to a pointer -- genuine type-punning, no arithmetic in between (the
  // direct-round-trip case Toolchain Milestone 20's own uintptr_t fix
  // covers, IF the union's memory-level behavior matches a plain
  // ptrtoint/inttoptr round-trip).
  u64 raw_bits = u.bits;
  struct node *back_punned = (struct node *)raw_bits;
  u64 got_punned = back_punned->value;

  if (got_same != 55) return 1;
  if (got_punned != 55) return 2;
  return 0;
}
