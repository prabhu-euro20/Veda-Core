// Toolchain Milestone 16 (research demo, not a shipped milestone number):
// empirically tests whether Veda-Core's EXISTING compiler pass (unmodified
// from Milestone 9) already handles the real Linux `container_of()`
// pattern -- BACKWARD reconstruction of an enclosing struct's base address
// via pointer subtraction from an EMBEDDED field's own address -- which is
// architecturally different from veda_demo_linked_list.c's FORWARD
// pointer-chasing (`cur->next`, dereferencing an already-tracked field to
// obtain another already-tracked pointer).
//
// Real Linux idiom this mirrors: `struct list_head` (here, `struct
// link_node`) embedded BY VALUE inside a larger struct (here, `struct
// container`), with list-walking code that only ever sees a `struct
// link_node *` and must recover the enclosing `struct container *` via
// `container_of(ptr, type, member)` = `(type*)((char*)ptr -
// offsetof(type, member))`.
//
// Why this might work, unmodified, on the FIRST attempt (a real hypothesis
// being tested here, not assumed true): VedaShadowPropagation.cpp's own
// GEP-handling rule (propagateInFunction, "GEP never changes which object
// a pointer refers to -- same shadow value") does not special-case the
// GEP's index sign or magnitude -- it propagates the SAME Object_ID shadow
// through ANY GetElementPtrInst whose pointer operand is already tracked,
// positive or negative index alike. Clang's own frontend lowers `(char*)p
// - N` (pointer minus a compile-time-constant integer) to exactly a
// GetElementPtrInst with a negative i64 index -- the SAME instruction kind
// the pass already generically handles, not a separate ptrtoint/sub/
// inttoptr chain. And critically, Veda-Core's Object-Bind/ODT model has NO
// subobject-bounds narrowing anywhere (neither in this pass nor in
// hardware) -- a GEP only ever changes the OFFSET used in the eventual
// OCL.D/OCS.D call; the object's own registered capability bounds
// (Base/Length) stay fixed at the WHOLE original veda_malloc'd
// allocation's size for the object's entire life. This is the real
// architectural reason real CHERI's container_of problem (a genuine
// HARDWARE bounds violation, when CHERI's own opt-in subobject-bounds
// hardening is enabled) does not obviously apply here: there is no
// narrowed bound to walk backward past in the first place.
//
// This file exists to CONFIRM or REFUTE that hypothesis empirically, not
// to assert it -- see veda_demo_container_of.ll (emitted alongside this
// build) for the real IR lowering, and the real sail_riscv_sim PASS/FAIL
// for the real hardware-checked outcome.
#include "../runtime/veda_rt.h"

typedef unsigned long u64;
typedef unsigned int u32;

extern void *veda_malloc_raw(u64 size, u32 *out_oid);

// Mirrors Linux's real struct-embedding pattern: struct link_node is
// EMBEDDED (by value) inside struct container -- never separately
// malloc'd, never its own Object_ID. list-manipulation code that only
// holds a `struct link_node *` must reconstruct `struct container *` via
// container_of.
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

int main(void) {
  veda_rt_init(VEDA_RT_SLOT_SIZE, VEDA_PERM_LOAD | VEDA_PERM_STORE);

  u32 oid;
  struct container *c =
      (struct container *)veda_malloc_raw(sizeof(struct container), &oid);
  c->tag = 0xAAAA;
  c->link.next = 0;
  c->payload = 12345;

  // Forward navigation: obtain a pointer to the EMBEDDED field only --
  // exactly what real Linux list-walking code sees (a `struct list_head
  // *`, never the enclosing container directly).
  struct link_node *l = &c->link;

  // Backward reconstruction: the real container_of pattern. Pointer
  // SUBTRACTION of the field's own compile-time offsetof from the field
  // pointer, to recover the enclosing object's base address. This is the
  // pattern the prior Linux-port research flagged as the structural
  // blocker for a full Linux port under Veda-Core's "no pointer at any
  // level" model.
  struct container *back = container_of(l, struct container, link);

  // Read fields OTHER than the one container_of started from, through the
  // reconstructed pointer -- proves genuine backward reconstruction
  // (correct base + correct bounds), not merely "the subtraction produced
  // some in-range garbage that happened not to trap."
  u64 got_tag = back->tag;
  u64 got_payload = back->payload;

  if (got_tag != 0xAAAA) return 1;
  if (got_payload != 12345) return 2;
  return 0; // SUCCESS: container_of reconstruction was bounds-correct and
            // read back the real, originally-stored data.
}
