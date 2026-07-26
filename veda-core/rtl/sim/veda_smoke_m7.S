.section .text
.global _start
_start:
    # Veda-Core RTL Milestone 7: OCL.C/OCS.C -- a real capability
    # round-trips through memory with its Tag preserved (positive),
    # and a plain OCS.D overwriting the same bytes correctly clears the
    # tag store's own record, so a subsequent OCL.C reads back untagged
    # (negative). Mirrors sail_tests/vc_ocl_ocs_c.S field-for-field, so
    # both real, independent implementations of this ISA are verified
    # against the same real scenario.
    li   x1, 1
    .word 0x0000d00b    # veda.bind c0, x1   (Object_ID=1: Base=0x80010000 Length=0x40 Perms=0x100C)
    li   x1, 2
    .word 0x0000d08b     # veda.bind c1, x1  (Object_ID=2: Base=0x80010100 Length=0x40 Perms=0x000C)

    li   x2, 0
    .word 0x0220408b      # ocs.c c0, x2, c1  -- store the real, tagged c1 at c0.Base+0
    .word 0x0020410b       # ocl.c c0, x2, c2  -- load it back into c2

    .word 0x0601055b        # cgettag  x10, c2  -- expect 1
    .word 0x000105db         # cgetbase x11, c2  -- expect 0x80010100
    .word 0x0201065b          # cgetlen  x12, c2  -- expect 0x40
    .word 0x040106db           # cgetperm x13, c2  -- expect 0x000C

    # Negative: plain OCS.D (ordinary GPR value) overwrites the same
    # 16-byte-aligned location's low 8 bytes -- never touches tag_mem[]
    # (only OCS.C does). A subsequent OCL.C must read the tag back as 0.
    li   x5, 0x4141414141414141
    .word 0x0220328b             # ocs.d c0, x2, x5
    .word 0x0020418b              # ocl.c c0, x2, c3  -- load again into c3
    .word 0x0601875b               # cgettag x14, c3   -- expect 0
1:
    j 1b
