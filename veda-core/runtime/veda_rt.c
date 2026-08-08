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
extern uint64_t veda_ocl_stack_d_scratch_asm(uint64_t region_offset,
                                             uint64_t access_offset,
                                             uint64_t size);
extern void veda_ocs_stack_d_scratch_asm(uint64_t region_offset,
                                         uint64_t access_offset,
                                         uint64_t size, uint64_t value);
// Toolchain Milestone 13: global/static protection.
extern void veda_mint_global_cap_rodata_asm(uint64_t region_offset,
                                            uint64_t size,
                                            uint64_t table_slot_offset);
extern void veda_mint_global_cap_data_asm(uint64_t region_offset,
                                          uint64_t size,
                                          uint64_t table_slot_offset);
extern uint64_t veda_ocl_global_d_scratch_asm(uint64_t table_slot_offset,
                                              uint64_t access_offset,
                                              uint64_t size);
extern void veda_ocs_global_d_scratch_asm(uint64_t table_slot_offset,
                                          uint64_t access_offset,
                                          uint64_t size, uint64_t value);

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

// Toolchain Milestone 15: the in-memory capability table itself -- now
// emitted directly by VedaShadowPropagation.cpp's own Phase B1, exactly
// sized to the real program's own global count (Rows.size() * 16 bytes),
// the fix TOOLCHAIN_MILESTONE_13_DESIGN.md's own "concrete next design
// step" already named ("exactly as many slots as the tuple table has
// entries, sized by the compiler pass itself"). This WEAK definition is
// only the fallback default for a program that references the symbol
// (an M13/M15-style hand-written entry point's own `la`) without the
// pass having found any qualifying global -- real, strong-linkage
// emission from the pass always wins when present, the identical
// real C/ELF weak-symbol mechanism __veda_global_table_meta/_count
// already rely on below. One slot (16 bytes), matching those two
// symbols' own minimal, harmless defaults.
__attribute__((weak)) uint8_t g_veda_global_cap_table[16];
// Companion byte-size constant for the same weak-fallback scenario --
// the hand-written entry point's own ODT-Populate Length field reads
// this directly (veda_global_protect_entry.S), mirroring
// __veda_global_table_count's own role for veda_rt_init_globals's loop
// bound above.
__attribute__((weak)) const uint64_t __veda_global_cap_table_bytes = 16;

// Toolchain Milestone 12: no software bind-failure path exists here --
// c15 is already established by the compartment's own entry point (never
// this runtime); an invalid access hard-traps inside the asm helper's
// own OCA/CSetBounds/OCL.D-or-OCS.D sequence, matching this runtime's
// established "let hardware enforce it" rule for the equivalent
// heap-object case above.
// Real, empirically-found requirement (Toolchain Milestone 12): these two
// functions are always reached from INSIDE a live veda_compartment
// function's own call graph, so they must themselves be
// __attribute__((veda_compartment)) too -- M19's purecap enforcement is
// global (tied to the veda_mode CSR, not to which function is currently
// executing), so an ordinary (non-attributed) function's own plain-`sd`
// `ra` spill (needed here because each function calls further into its
// own `*_scratch_asm` helper, so `ra` cannot be tail-call-elided) hard
// traps with VEDA_CAUSE_PURECAP_VIOLATION exactly like any other raw
// store would. Attributing these routes that same spill through OCS.D
// against the already-bound C15 instead -- the identical, already-proven
// safe nested-compartment pattern Toolchain Milestone 11's own nested
// call test (veda_compartment_nested_demo.c) already validated.
uint64_t veda_ocl_stack_d(uint64_t region_offset, uint64_t access_offset,
                          uint64_t size) __attribute__((veda_compartment));
uint64_t veda_ocl_stack_d(uint64_t region_offset, uint64_t access_offset,
                          uint64_t size) {
  return veda_ocl_stack_d_scratch_asm(region_offset, access_offset, size);
}

bool veda_ocs_stack_d(uint64_t region_offset, uint64_t access_offset,
                      uint64_t size, uint64_t value) __attribute__((veda_compartment));
bool veda_ocs_stack_d(uint64_t region_offset, uint64_t access_offset,
                      uint64_t size, uint64_t value) {
  veda_ocs_stack_d_scratch_asm(region_offset, access_offset, size, value);
  return true;
}

// Toolchain Milestone 13: global/static protection -- real, checked
// departure from CHERI's own literal linker-emitted __cap_relocs
// mechanism (this project's real linker/clang have no cap-reloc feature,
// confirmed directly -- see TOOLCHAIN_MILESTONE_13_DESIGN.md Section 3):
// VedaShadowPropagation.cpp's own Phase B1 emits a compiler-generated
// tuple table (`__veda_global_table_meta`/`_count`) naming every
// compartment-touched global's own region/offset/size. This struct's
// own layout must match Phase B1's own emitted `<{i64,i64,i64}>` packed
// LLVM struct type exactly, field-for-field -- a real, hand-maintained
// cross-file ABI, the same risk category as this file's own kVedaNullBase
// -class constants elsewhere in this project.
struct __attribute__((packed)) veda_global_table_entry {
  uint64_t region_selector; // 0 = .rodata, 1 = .data+.bss
  uint64_t region_offset;   // byte offset from the region's own start
  uint64_t size;            // this global's own real byte size
};
// Real regression found and fixed via a real full-suite regression run
// (not assumed): Phase B1 only EMITS these two symbols for a translation
// unit that actually contains at least one qualifying global
// (VedaShadowPropagation.cpp's own propagateGlobals, `if
// (TableEntries.empty()) return;`) -- any OTHER program linking this
// SAME veda_rt.c (Milestone 9's own heap-object demos with zero globals,
// or runtime/run_veda_rt_tests.sh's own standalone suite, which never
// invokes the pass plugin AT ALL) has NO file anywhere in its own link
// line that defines them, and veda_rt_init_globals's own body below
// references them unconditionally -- a real "undefined reference" link
// failure, confirmed directly. Fixed with WEAK fallback DEFINITIONS
// (not mere extern declarations) directly here: real C/ELF weak-symbol
// semantics mean Phase B1's own STRONG (ExternalLinkage) emission, when
// it exists anywhere in a given program's link line, correctly overrides
// this default; when it does not, this harmless, empty (count=0) default
// is used instead, and veda_rt_init_globals's own loop below simply
// performs zero iterations.
__attribute__((weak)) const struct veda_global_table_entry
    __veda_global_table_meta[1] = {{0, 0, 0}};
__attribute__((weak)) const uint64_t __veda_global_table_count = 0;

// Real, empirically-derived requirement (Toolchain Milestone 13): unlike
// veda_ocl_stack_d/veda_ocs_stack_d above (always reached from inside a
// live compartment), this bootstrap routine runs ONCE, BEFORE the first
// OCInvoke in the program -- in "wide open" PCC mode, with M19's purecap
// enforcement not yet active (it is gated on veda_mode.veda_purecap OR
// live OCInvoke-narrowing, VEDA_CORE_SPEC.md Section 3; neither holds
// here). No __attribute__((veda_compartment)) needed or wanted: this
// function's own ordinary prologue (a real, plain `sd`-based `ra` spill
// if the compiler needs one) is genuinely safe here, unlike every OTHER
// runtime helper in this file.
void veda_rt_init_globals(void) {
  for (uint64_t i = 0; i < __veda_global_table_count; i++) {
    const struct veda_global_table_entry *e = &__veda_global_table_meta[i];
    uint64_t table_slot_offset = i * 16; // kVedaCapTableSlotBytes, mirrored
    if (e->region_selector == 0)
      veda_mint_global_cap_rodata_asm(e->region_offset, e->size,
                                      table_slot_offset);
    else
      veda_mint_global_cap_data_asm(e->region_offset, e->size,
                                    table_slot_offset);
  }
}

// Per-access load/store -- always reached from inside a live compartment
// (Phase B1 only ever emits a call to these from a veda_compartment
// -attributed function's own body), so both need the attribute, the
// identical real reason veda_ocl_stack_d/veda_ocs_stack_d above do.
uint64_t veda_ocl_global_d(uint64_t table_slot_offset, uint64_t access_offset,
                           uint64_t size) __attribute__((veda_compartment));
uint64_t veda_ocl_global_d(uint64_t table_slot_offset, uint64_t access_offset,
                           uint64_t size) {
  return veda_ocl_global_d_scratch_asm(table_slot_offset, access_offset, size);
}

void veda_ocs_global_d(uint64_t table_slot_offset, uint64_t access_offset,
                       uint64_t size, uint64_t value) __attribute__((veda_compartment));
void veda_ocs_global_d(uint64_t table_slot_offset, uint64_t access_offset,
                       uint64_t size, uint64_t value) {
  veda_ocs_global_d_scratch_asm(table_slot_offset, access_offset, size, value);
}
