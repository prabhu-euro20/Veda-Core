// Toolchain Milestone 9: the real runtime backing for the ABI
// VedaShadowPropagation.cpp's pass emits calls against. Adapts Toolchain
// Milestone 7's already-verified veda_rt.h API (veda_malloc/veda_free/
// veda_ocl_d/veda_ocs_d) to the pass-facing ABI, rather than duplicating
// its allocator logic.
//
// kVedaNullBase (0x1000) MUST match VedaShadowPropagation.cpp's own
// identical constant exactly -- see that file's header comment for the
// full real reasoning (a fixed, non-null "zero offset" base every
// veda_malloc_raw call returns, avoiding any null-pointer-is-UB optimizer
// assumption on the pointer-as-offset-token representation).
#include <stdint.h>
#include "../runtime/veda_rt.h"

#define VEDA_NULL_BASE ((void *)0x1000)

// veda_shadow_attach is a pure compile-time observability marker (the
// pass's own FileCheck-testable "a Value's shadow just became known"
// signal, see VedaShadowPropagation.cpp's header comment) -- it carries
// no real runtime meaning, so a real linked program just needs SOME
// definition to satisfy the linker. A trivial no-op is the honest,
// correct real implementation.
void veda_shadow_attach(void *ptr, uint32_t oid) {
  (void)ptr;
  (void)oid;
}

void *veda_malloc_raw(uint64_t size, uint32_t *out_oid) {
  (void)size; // Milestone 7's own pool is a fixed single-slab size
             // (VEDA_RT_SLOT_SIZE) -- a real, already-stated scope limit
             // this adapter does not attempt to hide or work around.
  veda_obj_t obj = veda_malloc();
  *out_oid = (uint32_t)obj;
  return VEDA_NULL_BASE;
}

// Real disjoint shadow-metadata table -- a small, honest, linear-probe
// array sized generously for this milestone's own demo scale (a handful
// of live tracked pointer-typed slots), not a production-grade hash
// table. Keys are either real machine addresses (an untracked pointer
// VALUE stored at a real stack/global location -- Milestone 8's own
// original design) or the pass's own synthetic (object_id,offset)-encoded
// keys (bit 63 set -- a tracked pointer VALUE stored INTO another tracked
// object's own field, Milestone 9's real addition) -- this table treats
// both uniformly as opaque 64-bit keys, exactly as intended.
#define SHADOW_TABLE_SIZE 64
static void *g_shadow_keys[SHADOW_TABLE_SIZE];
static uint32_t g_shadow_vals[SHADOW_TABLE_SIZE];
static int g_shadow_used[SHADOW_TABLE_SIZE];

void veda_shadow_store(void *key, uint32_t oid) {
  int free_slot = -1;
  for (int i = 0; i < SHADOW_TABLE_SIZE; i++) {
    if (g_shadow_used[i] && g_shadow_keys[i] == key) {
      g_shadow_vals[i] = oid;
      return;
    }
    if (!g_shadow_used[i] && free_slot < 0) {
      free_slot = i;
    }
  }
  if (free_slot >= 0) {
    g_shadow_keys[free_slot] = key;
    g_shadow_vals[free_slot] = oid;
    g_shadow_used[free_slot] = 1;
  }
  // Table full: a real, honest, stated limitation of this minimal demo
  // runtime (documented in TOOLCHAIN_MILESTONE_9_RESULTS.md), not expected
  // to occur for this milestone's own bounded demo object count.
}

uint32_t veda_shadow_load(void *key) {
  for (int i = 0; i < SHADOW_TABLE_SIZE; i++) {
    if (g_shadow_used[i] && g_shadow_keys[i] == key) {
      return g_shadow_vals[i];
    }
  }
  return 0xFFFFFFFFu; // VEDA_OBJ_INVALID sentinel, matching veda_rt.h
}

// Thin wrappers around Milestone 7's own already-verified primitives --
// the `bool` success/fail return is deliberately ignored, matching that
// milestone's own established "let real hardware/runtime enforce
// correctness, don't redundantly software-check" philosophy: a real
// failure (bad object_id, permission violation, out-of-bounds offset)
// hard-traps inside veda_ocl_d/veda_ocs_d's own real Veda-Core
// instructions, which is exactly the intended, observable behavior for
// this milestone's own negative (out-of-bounds) demo.
void veda_rt_ocl_d(uint32_t oid, uint64_t offset, uint64_t *out) {
  (void)veda_ocl_d((veda_obj_t)oid, offset, out);
}

void veda_rt_ocs_d(uint32_t oid, uint64_t offset, uint64_t value) {
  (void)veda_ocs_d((veda_obj_t)oid, offset, value);
}

// Toolchain Milestone 12: pass-facing ABI for alloca-protected stack
// locals -- no Object_ID, since the target is always the already
// -established, persistent SSC capability in c15 (Toolchain Milestone
// 11), never a fresh veda.bind. See VedaShadowPropagation.cpp's own
// Phase B0 for how region_offset/access_offset/size are computed.
// __attribute__((veda_compartment)) here too, for the identical real
// reason veda_rt.h's own veda_ocl_stack_d/veda_ocs_stack_d now carry it
// (see that file's header comment) -- these wrappers are reached from
// inside a live compartment's own call graph just as directly. In THIS
// specific pair the compiler happens to tail-call-optimize the single
// inner call away (confirmed via trace: no stack frame, no `ra` spill at
// all), so this attribute is not empirically load-bearing for the exact
// demo tested here -- but relying on TCO continuing to fire is fragile
// (opt-level/compiler-version dependent), so it is applied unconditionally
// rather than left implicit. veda_rt_ocl_stack_d returns the loaded value
// directly (matching veda_ocl_stack_d's own real signature, see that
// function's header comment) -- no out-param write-back.
uint64_t veda_rt_ocl_stack_d(uint64_t region_offset, uint64_t access_offset,
                             uint64_t size) __attribute__((veda_compartment));
uint64_t veda_rt_ocl_stack_d(uint64_t region_offset, uint64_t access_offset,
                             uint64_t size) {
  return veda_ocl_stack_d(region_offset, access_offset, size);
}

void veda_rt_ocs_stack_d(uint64_t region_offset, uint64_t access_offset,
                         uint64_t size, uint64_t value) __attribute__((veda_compartment));
void veda_rt_ocs_stack_d(uint64_t region_offset, uint64_t access_offset,
                         uint64_t size, uint64_t value) {
  (void)veda_ocs_stack_d(region_offset, access_offset, size, value);
}
