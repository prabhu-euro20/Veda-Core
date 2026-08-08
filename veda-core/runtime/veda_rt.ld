/* Veda-Core runtime test linker script. Same real 0x80000000 load address
   and .tohost placement as sail_tests/veda_selfcheck.ld (read in full
   before writing this), extended with real .bss zeroing symbols (crt0.S)
   and a dedicated stack region -- neither existing script needed either,
   since no prior test program made real function calls or used mutable
   global state. */
OUTPUT_ARCH( "riscv" )
ENTRY(_start)
SECTIONS
{
  . = 0x80000000;
  .text.init : { *(.text.init) }
  .text      : { *(.text) *(.text.*) }
  __rodata_start = .;
  .rodata    : { *(.rodata) *(.rodata.*) }
  __rodata_end = .;
  __data_start = .;
  .data      : { *(.data) *(.data.*) }
  . = ALIGN(8);
  .tohost    : { *(.tohost) }
  . = ALIGN(8);
  __bss_start = .;
  .bss       : { *(.bss) *(.bss.*) *(COMMON) }
  __bss_end = .;
  /* Toolchain Milestone 13: __data_start/__bss_end together bound ONE
     contiguous "data+bss" capability region for compartment-protected
     globals -- .tohost sits between .data and .bss in this script's own
     real layout, so this span honestly over-covers it by construction.
     Harmless: an Object_ID's own bounds accounting has no effect on
     ordinary (non-capability) accesses, e.g. RVMODEL_HALT_PASS/FAIL's own
     plain `sw` to tohost, which this same over-coverage would otherwise
     seem to implicate. */
  . = ALIGN(0x1000);
  _end = .;

  /* 64 KiB reserved for this runtime's own backing-memory arena (at most
     VEDA_RT_MAX_OBJECTS * VEDA_RT_SLOT_SIZE bytes, a few hundred bytes in
     practice) plus the C call stack -- generous headroom, not a tight
     budget, for a deliberately minimal test program. */
  . = _end + 0x10000;
  _stack_top = .;

  /* MILESTONE 24 Stage 3: TCM capability-spill scratch -- a genuinely
     separate physical region (veda_core.tlv's own tcm_scratch[] array,
     TCM_SCRATCH_BASE=0xA0000000, TCM_SCRATCH_SIZE=4KiB), never overlapping
     the .bss/backing-arena/stack region above (which lives at
     0x80000000+_end+0x10000, far below 0xA0000000). Anything placed in
     .tcm_scratch gets OCS.C/OCL.C's own TCM-tier fast path for free --
     no stall, matching Part C/Mechanism A of TCM_FAST_PATH_DESIGN.md.
     __tcm_scratch_start/_end mirror this file's own __bss_start/_end
     convention exactly, for any future C/asm code that wants to bound-check
     against the region rather than trusting individual symbol placement. */
  . = 0xA0000000;
  __tcm_scratch_start = .;
  .tcm_scratch : { *(.tcm_scratch) }
  __tcm_scratch_end = .;
}
