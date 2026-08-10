// Toolchain-pass scope-limit probe (NOT a shipped demo): rewriteSignatures
// (~VedaShadowPropagation.cpp:403-474) rewrites ONLY direct CallInst users
// of a tracked-pointer-taking function (its own users() loop filters to
// `CI->getCalledFunction() == F`) and then unconditionally calls
// F->eraseFromParent() on the OLD Function object. This source probes
// what happens when a function-pointer VALUE use of that same old
// Function (a real LLVM User, just not a CallInst) exists anywhere in the
// module -- read_value's address is taken into a global function-pointer
// variable, and called ONLY through that pointer, never by name, so
// read_value has zero direct CallInst users at all.
#include "../runtime/veda_rt.h"

typedef unsigned long u64;
typedef unsigned int u32;

extern void *veda_malloc_raw(u64 size, u32 *out_oid);

struct node {
  u64 value;
};

// Real pointer-parameter function -- Phase A's own Targets-collection
// loop (any_of over F.args() for isPointerTy()) picks this up.
unsigned long read_value(struct node *n) { return n->value; }

// Function-pointer VALUE use of read_value: a real LLVM User of the old
// Function (a GlobalVariable initializer operand), but NOT a CallInst, so
// rewriteSignatures's own Calls-collection loop never sees it.
unsigned long (*g_reader)(struct node *) = read_value;

int main(void) {
  veda_rt_init(VEDA_RT_SLOT_SIZE, VEDA_PERM_LOAD | VEDA_PERM_STORE);

  u32 oid;
  struct node *n = (struct node *)veda_malloc_raw(sizeof(struct node), &oid);
  n->value = 42;

  // Called ONLY through the function pointer, never by name -- zero
  // direct CallInst users of read_value exist in this module.
  u64 result = g_reader(n);

  if (result != 42) return 1;
  return 0;
}
