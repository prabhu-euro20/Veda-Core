// Toolchain Milestone 7 negative control: generation-counter exhaustion.
// Built with -DVEDA_RT_MAX_OBJECTS=1 (see run_veda_rt_tests.sh) so this
// single slot's real, exact 256-Destroy-call retirement (independently
// confirmed this session from veda_types.sail + veda_ocl_insts.sail and
// cross-checked against sail_tests/vc_gen_retire_neg.S's own real
// 256-iteration test) empties the entire pool -- making "malloc now
// refuses" directly observable with no other still-fresh slot to race
// ahead to.
//
// Two independent checks, not one:
//   1. The library's own high-level API (veda_malloc) must refuse further
//      allocation once its software bookkeeping says the one slot is
//      retired -- without ever letting a real ODT-Populate-Fast execute
//      against that retired slot (which would hard-fault).
//   2. A direct, independent hardware probe -- bypassing the library
//      entirely and calling the raw asm primitive on the same, now-known
//      -retired Object_ID -- proves the software bookkeeping genuinely
//      matches real hardware state (a real Illegal_Instruction hard trap,
//      mcause=2), not merely "conveniently never asked."
#include "veda_rt.h"

extern uint64_t veda_odt_populate_fast_asm(uint64_t object_id, uint64_t base);
extern void veda_rt_trap_catcher_install(void);
extern volatile int g_trap_fired;
extern volatile uint64_t g_trap_mcause;

int main(void) {
  veda_rt_init(VEDA_RT_SLOT_SIZE, VEDA_PERM_LOAD | VEDA_PERM_STORE);

  veda_obj_t obj = veda_malloc();
  if (obj == VEDA_OBJ_INVALID) return 1;

  // Sanity round-trip before starting the exhaustion loop.
  if (!veda_ocs_d(obj, 0, 0xABCDull)) return 2;
  uint64_t v = 0;
  if (!veda_ocl_d(obj, 0, &v) || v != 0xABCDull) return 3;
  veda_free(obj); // Destroy call #1

  // 255 more full malloc/free cycles on the same (only) slot -- 256 real
  // Destroy calls total. Every one of these must succeed normally right
  // up to and including the 255th here (the slot must not retire early).
  for (int i = 0; i < 255; i++) {
    veda_obj_t o = veda_malloc();
    if (o == VEDA_OBJ_INVALID) return 4;
    veda_free(o); // Destroy calls #2..#256
  }

  // Check 1: the library itself must now refuse any further allocation.
  veda_obj_t should_fail = veda_malloc();
  if (should_fail != VEDA_OBJ_INVALID) return 5;

  // Check 2: direct hardware probe. obj's numeric value (VEDA_RT_FIRST_OBJECT_ID
  // + slot 0) is still known even though the library itself now refuses
  // to hand it out -- call the raw primitive directly, bypassing every
  // software guard, against the real, now-retired Object_ID.
  veda_rt_trap_catcher_install();
  (void)veda_odt_populate_fast_asm(VEDA_RT_FIRST_OBJECT_ID, 0x80000000u);

  if (!g_trap_fired) return 6; // the doomed populate wrongly succeeded
  if (g_trap_mcause != 2) return 7; // wrong cause (expected standard Illegal Instruction)

  return 0;
}
