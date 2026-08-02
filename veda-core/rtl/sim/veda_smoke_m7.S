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
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1   (Object_ID=1: Base=0x80010000 Length=0x40 Perms=0x100C)
    li   x1, 2
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  (Object_ID=2: Base=0x80010100 Length=0x40 Perms=0x000C)

    li   x2, 0
    .insn r 0x0b, 0x4, 0x01, x1, x0, x2  # ocs.c c0, x2, c1  -- store the real, tagged c1 at c0.Base+0
    .insn r 0x0b, 0x4, 0x00, x2, x0, x2  # ocl.c c0, x2, c2  -- load it back into c2

    .insn r 0x5b, 0x0, 0x03, x10, x2, x0  # cgettag  x10, c2  -- expect 1
    .insn r 0x5b, 0x0, 0x00, x11, x2, x0  # cgetbase x11, c2  -- expect 0x80010100
    .insn r 0x5b, 0x0, 0x01, x12, x2, x0  # cgetlen  x12, c2  -- expect 0x40
    .insn r 0x5b, 0x0, 0x02, x13, x2, x0  # cgetperm x13, c2  -- expect 0x000C

    # Negative: plain OCS.D (ordinary GPR value) overwrites the same
    # 16-byte-aligned location's low 8 bytes -- never touches tag_mem[]
    # (only OCS.C does). A subsequent OCL.C must read the tag back as 0.
    li   x5, 0x4141414141414141
    .insn r 0x0b, 0x3, 0x01, x5, x0, x2  # ocs.d c0, x2, x5
    .insn r 0x0b, 0x4, 0x00, x3, x0, x2  # ocl.c c0, x2, c3  -- load again into c3
    .insn r 0x5b, 0x0, 0x03, x14, x3, x0  # cgettag x14, c3   -- expect 0
1:
    j 1b
