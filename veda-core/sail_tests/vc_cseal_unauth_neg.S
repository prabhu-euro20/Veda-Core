.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x1, 4           # Object_ID = 4 (seeded WITHOUT Permit_Seal)
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1
    li   x2, 5
    .insn r 0x5b, 0x1, 0x0a, x2, x2, x2  # oca c2, c2, x2   (structurally fine, no Permit_Seal needed for OCA)
    .insn r 0x5b, 0x1, 0x10, x1, x0, x2  # cseal c1, c0, c2  -- c2 lacks Permit_Seal: must SOFT-FAIL, not trap
    .insn r 0x5b, 0x0, 0x03, x10, x1, x0  # cgettag x10, c1  -- expect 0 (soft-fail confirmed, no trap occurred)
    bne  x10, x0, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
