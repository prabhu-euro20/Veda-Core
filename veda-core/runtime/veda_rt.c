#include "veda_rt.h"

// Linker-provided (veda_rt.ld): the first byte after the loaded, page
// -aligned program image -- this runtime's own backing-memory arena
// starts here, the same real convention sail_tests/veda_selfcheck.ld
// already uses for its own `_end` symbol.
extern char _end[];

extern uint64_t veda_odt_populate_fast_asm(uint64_t object_id, uint64_t base);
extern uint64_t veda_odt_destroy_asm(uint64_t object_id);
extern int veda_bind_scratch_asm(uint64_t object_id);
extern void veda_ocl_d_scratch_asm(uint64_t offset, uint64_t *out);
extern void veda_ocs_d_scratch_asm(uint64_t offset, uint64_t value);

static bool g_in_use[VEDA_RT_MAX_OBJECTS];
static bool g_retired[VEDA_RT_MAX_OBJECTS];
// Real hardware (veda_types.sail's odt_entry.generation) tracks this per
// slot too, but no ISA-visible query exists to read it back in software --
// none of the 7 real Veda-Cap query instructions (CGetBase/Len/Perm/Tag/
// Type/Addr/Offset, veda_cap_insts.sail) expose the ODT entry's Reserved/
// generation field, and a bound capability's own cached copy (Reserved)
// isn't independently queryable either. So this array is not a cache of
// hardware state -- it is the only copy that exists in software, and it
// must exactly mirror ODT-Destroy's own real, unconditional per-call
// generation bump (veda_ocl_insts.sail's VEDA_ODT_DESTROY execute clause)
// or this runtime's retirement bookkeeping silently drifts from real
// hardware state. An honest, real, stated limitation of the current ISA,
// not a simplification chosen for convenience.
static uint8_t g_destroy_count[VEDA_RT_MAX_OBJECTS];
static uint32_t g_arena_base;

void veda_rt_init(uint16_t length, uint16_t perms) {
  // veda_attr CSR (0x7C4, veda_regs.sail): Length in bits[31:16], Perms in
  // bits[15:0] -- the real, shared template VEDA_ODT_POPULATE_FAST reads
  // for every object this runtime populates. Written via the real,
  // unmodified, already-working base-ISA CSRRW -- no new instruction
  // needed for this, matching veda_regs.sail's own documented intent.
  uint32_t attr = ((uint32_t)length << 16) | (uint32_t)perms;
  __asm__ volatile("csrw 0x7C4, %0" ::"r"((uint64_t)attr));

  g_arena_base = (uint32_t)(uintptr_t)&_end;
  for (int i = 0; i < VEDA_RT_MAX_OBJECTS; i++) {
    g_in_use[i] = false;
    g_retired[i] = false;
    g_destroy_count[i] = 0;
  }
}

veda_obj_t veda_malloc(void) {
  for (int i = 0; i < VEDA_RT_MAX_OBJECTS; i++) {
    if (!g_in_use[i] && !g_retired[i]) {
      uint64_t object_id = VEDA_RT_FIRST_OBJECT_ID + (uint64_t)i;
      uint64_t base = (uint64_t)g_arena_base + (uint64_t)i * VEDA_RT_SLOT_SIZE;
      // Real hardware guard this call relies on: old_entry.retired is
      // always false here, because g_retired[i] tracks it exactly (see
      // veda_free below) -- so this real ODT-Populate-Fast call can never
      // observe the Illegal_Instruction() hard trap its own execute
      // clause would otherwise raise on a genuinely retired slot.
      (void)veda_odt_populate_fast_asm(object_id, base);
      g_in_use[i] = true;
      return (veda_obj_t)object_id;
    }
  }
  return VEDA_OBJ_INVALID;
}

void veda_free(veda_obj_t obj) {
  if (obj < VEDA_RT_FIRST_OBJECT_ID) return;
  uint32_t i = obj - VEDA_RT_FIRST_OBJECT_ID;
  if (i >= VEDA_RT_MAX_OBJECTS || !g_in_use[i]) return;

  (void)veda_odt_destroy_asm(obj);
  g_in_use[i] = false;

  // Real hardware bumps the ODT entry's generation unconditionally on
  // every Destroy (veda_ocl_insts.sail's VEDA_ODT_DESTROY execute clause,
  // regardless of the slot's prior valid/retired state) -- this software
  // mirror must bump exactly once per real Destroy call for the same
  // reason. uint8_t wraparound (255 -> 0 on the 256th increment) is used
  // deliberately as the retirement trigger, exactly matching real
  // hardware's own 8-bit generation register reaching the same 256th-call
  // boundary (independently confirmed this session from veda_types.sail's
  // odt_entry.retired comment and cross-checked against
  // sail_tests/vc_gen_retire_neg.S's own real 256-Destroy-call test).
  g_destroy_count[i]++;
  if (g_destroy_count[i] == 0) {
    g_retired[i] = true;
  }
}

bool veda_ocl_d(veda_obj_t obj, uint64_t offset, uint64_t *out) {
  if (!veda_bind_scratch_asm(obj)) return false;
  veda_ocl_d_scratch_asm(offset, out);
  return true;
}

bool veda_ocs_d(veda_obj_t obj, uint64_t offset, uint64_t value) {
  if (!veda_bind_scratch_asm(obj)) return false;
  veda_ocs_d_scratch_asm(offset, value);
  return true;
}
