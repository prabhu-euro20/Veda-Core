.section .text
.global _start
_start:
    li   x1, 1          # Object_ID = 1 (capability to attempt to seal)
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x1, 4           # Object_ID = 4 (seeded WITHOUT Permit_Seal, Perms=0)
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1
    li   x2, 5             # candidate otype value
    .insn r 0x5b, 0x1, 0x0a, x2, x2, x2  # oca c2, c2, x2   (structurally fine, c2 unsealed & in-bounds; OCA needs no Permit_Seal)
    .insn r 0x5b, 0x1, 0x10, x1, x0, x2  # cseal c1, c0, c2  -- c2 lacks Permit_Seal: must SOFT-FAIL (c1.Tag=0), not trap
    .insn r 0x5b, 0x0, 0x03, x10, x1, x0  # cgettag x10, c1  -- expect 0 (soft-fail confirmed, no trap occurred)
1:
    j 1b
