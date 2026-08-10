// Toolchain Milestone 13 scope-limit probe (research demo, not a shipped
// milestone number): empirically tests findGlobalRoot's own documented
// "Only single-level GEPs are handled" scope limit
// (VedaShadowPropagation.cpp, ~line 327-331) against a GLOBAL ARRAY OF
// STRUCTS, where recovering the array's identity from a field access
// requires walking back through TWO chained GEP instructions (array-index
// GEP, then field GEP) -- unlike the existing g_lower[4]/g_upper[4] demo
// (veda_global_protect_demo.c), a plain array of `unsigned long` with no
// struct fields, whose single GEP's pointer operand is @g_lower/@g_upper
// directly (a one-hop case findGlobalRoot resolves cleanly).
//
// Pre-pass IR confirmed (via a standalone -O0 probe, before writing this
// file) that Clang lowers `g_arr[i].value` as:
//   %arrayidx = getelementptr [4 x %struct.node], ptr @g_arr, i64 0, i64 %i
//   %value    = getelementptr %struct.node, ptr %arrayidx, i32 0, i32 1
// -- the field GEP's own pointer operand is %arrayidx (an Instruction, the
// FIRST GEP's own result), never @g_arr directly. findGlobalRoot, called on
// the field GEP, calls dyn_cast<GlobalVariable> on that Instruction operand
// and gets nullptr -- exactly the documented scope limit, not a hypothetical
// one.
//
// Runtime-variable index (matching veda_global_protect_demo.c's own
// established finding that this is the more representative real-world
// access shape -- a GetElementPtrInst, not a GEP ConstantExpr).
#ifndef VEDA_COMPARTMENT_ATTR
#define VEDA_COMPARTMENT_ATTR __attribute__((veda_compartment))
#endif

struct node {
  struct node *next;
  unsigned long value;
};

static struct node g_arr[4];

VEDA_COMPARTMENT_ATTR
unsigned long veda_struct_array_global_thread(void) {
  for (int i = 0; i < 4; i++) {
    g_arr[i].value = i;
  }
  g_arr[2].value = 0x2a;
  return g_arr[2].value;
}
