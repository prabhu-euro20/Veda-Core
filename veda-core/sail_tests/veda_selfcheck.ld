OUTPUT_ARCH( "riscv" )
ENTRY(_start)
SECTIONS
{
  . = 0x80000000;
  .text.init : { *(.text.init) }
  .text      : { *(.text) *(.text.*) }
  .data      : { *(.data) }
  . = ALIGN(8);
  .tohost    : { *(.tohost) }
  . = ALIGN(0x1000);
  _end = .;
}
