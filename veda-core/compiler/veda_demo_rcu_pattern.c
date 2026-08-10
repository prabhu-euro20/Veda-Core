// Research probe: does Veda-Core's shadow tracking survive the REAL
// rcu_assign_pointer()/rcu_dereference() mechanics, minimally
// reproduced from the actual Linux kernel headers (read in full this
// session: /usr/src/linux-headers-*/include/linux/rcupdate.h,
// include/asm-generic/barrier.h) -- not guessed at.
//
// Real rcu_assign_pointer(p, v) (rcupdate.h) expands, for a non-constant
// v, to: `uintptr_t _r_a_p__v = (uintptr_t)(v); smp_store_release(&p,
// (typeof(p))_r_a_p__v);` -- a ptrtoint, then a real memory-barrier
// instruction (__smp_mb(), generic path), THEN an ordinary WRITE_ONCE
// store (a ptr-typed store, NOT an LLVM atomic store on the generic/
// RISC-V path -- confirmed by reading asm-generic/barrier.h's own
// __smp_store_release: "__smp_mb(); WRITE_ONCE(*p, v);", plain sequential
// C, no __atomic builtin).
//
// Real rcu_dereference(p) expands to rcu_dereference_check(p, 0), which
// bottoms out in __rcu_dereference_check: `typeof(*p) *local = (typeof(*p)
// *__force)READ_ONCE(p);` -- an ordinary volatile pointer LOAD, again not
// an LLVM atomic load.
//
// THIS demo mirrors that exact shape (minus Linux's own __rcu/sparse
// annotations, irrelevant to codegen) using this project's own
// already-verified fence primitive conventions -- a real `fence rw,rw`
// via inline asm (the RISC-V instruction __smp_mb() itself lowers to on
// this arch) sitting between the ptrtoint and the real pointer store,
// exactly where Linux's own macro places it.
#include "../runtime/veda_rt.h"

typedef unsigned long u64;
typedef unsigned int u32;

extern void *veda_malloc_raw(u64 size, u32 *out_oid);

struct node {
  u64 value;
};

static struct node *volatile g_rcu_ptr;

static inline void veda_rcu_assign_pointer(struct node *v) {
  u64 _r_a_p__v = (u64)(v); // uintptr_t cast, exactly matching the real macro
  __asm__ __volatile__("fence rw,rw" ::: "memory"); // __smp_mb()
  g_rcu_ptr = (struct node *)_r_a_p__v; // WRITE_ONCE(*p, v) -- ordinary store
}

static inline struct node *veda_rcu_dereference(void) {
  return g_rcu_ptr; // READ_ONCE(p) -- ordinary volatile load
}

int main(void) {
  veda_rt_init(VEDA_RT_SLOT_SIZE, VEDA_PERM_LOAD | VEDA_PERM_STORE);

  u32 oid;
  struct node *n = (struct node *)veda_malloc_raw(sizeof(struct node), &oid);
  n->value = 88;

  // Publish, mirroring rcu_assign_pointer(g_rcu_ptr, n) exactly.
  veda_rcu_assign_pointer(n);

  // Consume, mirroring rcu_dereference(g_rcu_ptr) exactly. On THIS
  // single hart, this is trivially "the same hart reading back its own
  // write" -- the real, honest scope limit of what this simulator can
  // empirically prove (see TOOLCHAIN_MILESTONE_20_KERNEL_GAPS_RESULTS.md
  // for the full analysis of what remains genuinely untestable: whether
  // this ALSO holds when a DIFFERENT hart performs the dereference).
  struct node *observed = veda_rcu_dereference();
  u64 got = observed->value;

  if (got != 88) return 1;
  return 0;
}
