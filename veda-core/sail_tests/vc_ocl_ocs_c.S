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
    .word 0x0000d00b    # veda.bind c0, x1   (Object_ID=1: Base=0x80010000 Length=0x40 Perms=0x100C)
    li   x1, 3
    .word 0x0000d08b     # veda.bind c1, x1  (Object_ID=3: Base=0x80010200 Length=0x10 Perms=0x0300)

    li   x2, 0
    .word 0x0220408b      # ocs.c c0, x2, c1  -- store the real, tagged c1 at c0.Base+0
    .word 0x0020410b       # ocl.c c0, x2, c2  -- load it back into c2

    .word 0x0601055b        # cgettag  x10, c2  -- expect 1
    .word 0x080105db         # cgettype x11, c2  -- expect 0xFFFF
    .word 0x0001065b          # cgetbase x12, c2  -- expect 0x80010200
    .word 0x020106db           # cgetlen  x13, c2  -- expect 0x10
    .word 0x0401075b             # cgetperm x14, c2  -- expect 0x0300

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
    .word 0x0220328b               # ocs.d c0, x2, x5
    .word 0x0020418b                # ocl.c c0, x2, c3  -- load again into c3
    .word 0x060187db                 # cgettag x15, c3  -- expect 0 (tag store correctly cleared)

    li   x20, 0
    bne  x15, x20, fail

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
