.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 18 positive test: VEDA_ODT_POPULATE_FAST
    # + veda_attr CSR (0x7C4). Real, measured motivation
    # (IMMEDIATE_LIMIT_INVESTIGATION): plain ODT-Populate needs a full
    # 6-instruction `li` per object to build its packed 64-bit
    # descriptor, because of RV64I's 12-bit immediate limit. This
    # instruction takes Base directly in rs2 (no shift/pack) and reads
    # Length/Perms from veda_attr instead -- proven here end-to-end:
    # a CSR write/read-back sanity check, a real write-then-read round
    # trip through the freshly minted object (proves Base+Perms landed
    # correctly), and a boundary access at offset+width == Length
    # (proves the real Length came from veda_attr, not left at its old
    # ODT contents or truncated).
    # ─────────────────────────────────────────────────────────────
    li   x20, 0x0040100c             # veda_attr = Length=0x40 (64), Perms=0x100C (Load|Store)
    csrw 0x7c4, x20
    csrr x21, 0x7c4                  # read back -- expect exact match

    li   x1, 6                       # Object_ID = 6 (never seeded at reset -- a real fresh mint)
    li   x2, 0x80010600              # Base, direct -- no <<32 packing needed, unlike plain Populate
    .insn r 0x0b, 0x0, 0x04, x0, x1, x2  # veda.odt.populate.fast x0, x1, x2

    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1   -- expect c0.Tag=1, Base=0x80010600

    li   x3, 0                       # ordinary-position offset
    li   x4, 0x1234567890ABCDEF
    .insn r 0x0b, 0x3, 0x01, x4, x0, x3  # ocs.d c0, x3, x4
    .insn r 0x0b, 0x3, 0x00, x6, x0, x3  # ocl.d c0, x3, x6   -- expect x6 == x4

    li   x7, 0x38                    # boundary offset: 0x38 + 8 == 0x40 == Length -- must succeed
    li   x8, 0x66
    .insn r 0x0b, 0x3, 0x01, x8, x0, x7  # ocs.d c0, x7, x8
    .insn r 0x0b, 0x3, 0x00, x9, x0, x7  # ocl.d c0, x7, x9   -- expect x9 == 0x66
1:
    j 1b
