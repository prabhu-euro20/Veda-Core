.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Milestone 7: OCL.C/OCS.C -- a real capability round-trips through
    # memory with its Tag preserved (positive), and a plain OCS.D
    # overwriting the same bytes correctly strips the tag store's own
    # record, so a subsequent OCL.C reads back untagged (negative) --
    # the core security property this milestone exists to prove: a
    # capability loaded from memory is only as trustworthy as what a real
    # OCS.C genuinely stored there, not just "the load succeeded."
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1   (Object_ID=1: Base=0x80010000 Length=0x40 Perms=0x100C)
    li   x1, 3
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  (Object_ID=3: Base=0x80010200 Length=0x10 Perms=0x0300)

    li   x2, 0
    .insn r 0x0b, 0x4, 0x01, x1, x0, x2  # ocs.c c0, x2, c1  -- store the real, tagged c1 at c0.Base+0
    .insn r 0x0b, 0x4, 0x00, x2, x0, x2  # ocl.c c0, x2, c2  -- load it back into c2

    .insn r 0x5b, 0x0, 0x03, x10, x2, x0  # cgettag  x10, c2  -- expect 1
    .insn r 0x5b, 0x0, 0x04, x11, x2, x0  # cgettype x11, c2  -- expect 0xFFFF
    .insn r 0x5b, 0x0, 0x00, x12, x2, x0  # cgetbase x12, c2  -- expect 0x80010200
    .insn r 0x5b, 0x0, 0x01, x13, x2, x0  # cgetlen  x13, c2  -- expect 0x10
    .insn r 0x5b, 0x0, 0x02, x14, x2, x0  # cgetperm x14, c2  -- expect 0x0300

    li   x20, 1
    bne  x10, x20, fail
    li   x20, 0xFFFF
    bne  x11, x20, fail
    li   x20, 0x80010200
    bne  x12, x20, fail
    li   x20, 0x10
    bne  x13, x20, fail
    li   x20, 0x0300
    bne  x14, x20, fail

    # Negative: a plain OCS.D (ordinary GPR value, not a capability) now
    # overwrites the same 16-byte-aligned location's low 8 bytes. This
    # never touches the tag store (default_meta = false) -- a subsequent
    # OCL.C must read the tag back as false, even though 8 of the 16 raw
    # data bytes are now genuinely different from what OCS.C wrote.
    li   x5, 0x4141414141414141
    .insn r 0x0b, 0x3, 0x01, x5, x0, x2  # ocs.d c0, x2, x5
    .insn r 0x0b, 0x4, 0x00, x3, x0, x2  # ocl.c c0, x2, c3  -- load again into c3
    .insn r 0x5b, 0x0, 0x03, x15, x3, x0  # cgettag x15, c3  -- expect 0 (tag store correctly cleared)

    li   x20, 0
    bne  x15, x20, fail

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
