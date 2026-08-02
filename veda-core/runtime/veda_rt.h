// Veda-Core minimal software runtime library (Toolchain Milestone 7).
//
// A malloc/free-equivalent wrapper around real ODT-Populate(-Fast)/Bind/
// ODT-Destroy (Toolchain Milestones 5a/5b-M6 gave these real LLVM mnemonic
// support; this library is the first real software to use them instead of
// hand-encoded hex). Deliberately a SINGLE-SLAB-SIZE pool allocator, not a
// general variable-size malloc -- VEDA_ODT_POPULATE_FAST's own real design
// (veda_regs.sail's `veda_attr` CSR) shares one Length/Perms template
// across every object populated through it, so a fixed slot size is the
// natural, honest minimal design, not an arbitrary simplification. Object
// IDs and backing-memory slots are 1:1 (slot i always backs Object_ID
// VEDA_RT_FIRST_OBJECT_ID+i) -- a real, stated scope limit: once a slot's
// generation counter is exhausted (veda_types.sail's `retired` field,
// independently confirmed this session to trigger after exactly 256 real
// Destroy calls, cross-checked against sail_tests/vc_gen_retire_neg.S's
// own 256-iteration test), that slot's backing memory is permanently
// unusable too, not just its Object_ID -- a production allocator would
// decouple the two; out of scope for this minimal milestone.
//
// Object_ID is an opaque 23-bit software handle (VEDA_CORE_SPEC.md's own
// "software holds an opaque Object_ID, never a raw address" model) -- it
// is NOT a capability and cannot be dereferenced directly. Every real
// access goes through veda_ocl_d/veda_ocs_d, which bind the runtime's
// single fixed scratch capability register (c1 -- see veda_rt_asm.S) fresh
// on every call. No dynamic capability-register allocation exists before
// Toolchain Milestone 8/9's compiler pass; this is hand-written,
// hand-scheduled runtime code, matching this milestone's own real scope.
//
// Bounds/permission/tag/generation checking is NOT redundantly duplicated
// in software here -- that is exactly the hardware capability model's own
// job (veda_check_access, veda_ocl_insts.sail), offloaded via the object's
// real Length/Perms fields. An out-of-bounds veda_ocl_d/veda_ocs_d call is
// expected to (and does) hard-trap; this library does not shield callers
// from that, since doing so would defeat the entire point of the hardware
// model.

#ifndef VEDA_RT_H
#define VEDA_RT_H

#include <stdint.h>
#include <stdbool.h>

// Compile-time pool size, overridable via -DVEDA_RT_MAX_OBJECTS=N (the
// generation-exhaustion negative test deliberately builds with N=1 so a
// single slot's retirement empties the whole pool, making "malloc now
// refuses" directly observable without a multi-slot allocator racing
// ahead to a still-fresh slot).
#ifndef VEDA_RT_MAX_OBJECTS
#define VEDA_RT_MAX_OBJECTS 8
#endif

// Object_ID range this runtime instance owns exclusively -- chosen clear
// of sail_tests/veda_regs.sail's own veda_test_seed_odt() IDs (1-5, seeded
// on every ext_reset) and of the existing self-check suite's own
// hand-picked IDs (e.g. vc_gen_retire*.S's 50/51), so this library never
// observes another test's pre-existing ODT state.
#define VEDA_RT_FIRST_OBJECT_ID 1000u

#define VEDA_RT_SLOT_SIZE 64u

typedef uint32_t veda_obj_t;
#define VEDA_OBJ_INVALID ((veda_obj_t)0xFFFFFFFFu)

// Perms bit positions, veda_types.sail's own real, fixed assignment
// (Section 2 of VEDA_CORE_SPEC.md).
#define VEDA_PERM_LOAD  (1u << 2)
#define VEDA_PERM_STORE (1u << 3)

// Sets veda_attr (Length/Perms shared by every populate.fast call this
// runtime instance issues) and resets all allocator bookkeeping. Must be
// called exactly once before any veda_malloc/veda_free call.
void veda_rt_init(uint16_t length, uint16_t perms);

// Returns a fresh Object_ID bound to VEDA_RT_SLOT_SIZE bytes of real
// backing memory, or VEDA_OBJ_INVALID if every slot is either currently
// live or permanently retired.
veda_obj_t veda_malloc(void);

// Destroys the object (real ODT-Destroy) and returns its slot to the free
// pool -- unless this is the 256th real Destroy call on that slot, in
// which case the slot is retired instead and never handed out again.
// Freeing an object not currently live (double-free, or an ID this
// runtime instance never owned) is a no-op, not undefined behavior.
void veda_free(veda_obj_t obj);

// Reads/writes 8 bytes at `offset` within `obj`'s real backing object.
// Returns false without touching memory if binding `obj` failed (it was
// never populated, or has since been freed) -- this is the ONLY software
// -side error path; bounds/permission violations are real hardware traps,
// not a returned false.
bool veda_ocl_d(veda_obj_t obj, uint64_t offset, uint64_t *out);
bool veda_ocs_d(veda_obj_t obj, uint64_t offset, uint64_t value);

#endif // VEDA_RT_H
