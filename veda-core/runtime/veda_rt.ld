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
  .rodata    : { *(.rodata) *(.rodata.*) }
  .data      : { *(.data) *(.data.*) }
  . = ALIGN(8);
  .tohost    : { *(.tohost) }
  . = ALIGN(8);
  __bss_start = .;
  .bss       : { *(.bss) *(.bss.*) *(COMMON) }
  __bss_end = .;
  . = ALIGN(0x1000);
  _end = .;

  /* 64 KiB reserved for this runtime's own backing-memory arena (at most
     VEDA_RT_MAX_OBJECTS * VEDA_RT_SLOT_SIZE bytes, a few hundred bytes in
     practice) plus the C call stack -- generous headroom, not a tight
     budget, for a deliberately minimal test program. */
  . = _end + 0x10000;
  _stack_top = .;
}
