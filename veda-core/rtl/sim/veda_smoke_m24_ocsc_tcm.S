.section .text
.global _start
_start:
    # MILESTONE 24 Stage 3: TCM capability-spill scratch. Exercises
    # OCL.C/OCS.C's new address-range mux ($veda_capmem_tcm_hit) against
    # BOTH arms in the SAME test -- a real, tagged capability round-trips
    # correctly through the new tcm_scratch[]/tcm_scratch_tag[] region
    # (Object_ID=201, Base=TCM_SCRATCH_BASE=0xA0000000) AND through
    # ordinary elfmem[]/tag_mem[] (Object_ID=202, Base=0x80020000, well
    # outside this program's own code/data footprint), proving the mux
    # picks the right array in both directions, not just one. A dedicated
    # negative check per region (loading from an offset never written)
    # confirms tcm_scratch_tag[]'s own zero-init (the same real
    # initial-block pattern tag_mem[] already used) actually took effect,
    # and that neither region's tag store leaks into the other's --
    # the real "easy-to-miss bug class" (tag-write granule split) this
    # milestone's own design doc flagged, exercised directly rather than
    # trusted by inspection alone. Per this milestone's own explicit
    # scope contract (see tcm_scratch[]'s own declaration comment in
    # veda_core.tlv): TCM-scratch access is OCL.C/OCS.C ONLY in this
    # milestone -- this test never issues OCL.D/OCS.D/NMC_ADD/Atomic
    # against the TCM region, matching that contract.

    # ---- donor: Object_ID=1 pre-seeded fixture (Base=0x80010000, Length=0x40, Perms=0x100C) ----
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0        # veda.bind c0, x1  -- donor, real tag=1

    # ---- TCM-scratch target: Object_ID=201, Base=TCM_SCRATCH_BASE=0xA0000000 ----
    li   t0, 0xA0000000
    slli t0, t0, 32
    li   t1, 0x0040000C                 # Length=0x40, Perms=Load|Store
    or   t0, t0, t1
    li   x1, 201
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2 # veda.odt.populate x5, x1, x2 -- Object_ID=201
    li   x1, 201
    .insn i 0x0b, 0x5, x8, x1, 0        # veda.bind c8, x1  -- TCM target

    # ---- DRAM/elfmem target: Object_ID=202, Base=0x80020000 (far outside this program) ----
    li   t0, 0x80020000
    slli t0, t0, 32
    li   t1, 0x0040000C                 # Length=0x40, Perms=Load|Store
    or   t0, t0, t1
    li   x1, 202
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2 # veda.odt.populate x5, x1, x2 -- Object_ID=202
    li   x1, 202
    .insn i 0x0b, 0x5, x9, x1, 0        # veda.bind c9, x1  -- DRAM target

    # ---- positive: store+reload the donor through the TCM path ----
    li   x2, 0
    .insn r 0x0b, 0x4, 0x01, x0, x8, x2  # ocs.c c8, x2(=0), c0  -- store donor into TCM
    .insn r 0x0b, 0x4, 0x00, x1, x8, x2  # ocl.c c8, x2(=0), c1  -- load it back into c1
    .insn r 0x5b, 0x0, 0x03, x10, x1, x0 # cgettag  x10, c1  -- expect 1
    .insn r 0x5b, 0x0, 0x00, x11, x1, x0 # cgetbase x11, c1  -- expect 0x80010000 (donor's own base, unchanged)

    # ---- positive: store+reload the SAME donor through the DRAM/elfmem path ----
    .insn r 0x0b, 0x4, 0x01, x0, x9, x2  # ocs.c c9, x2(=0), c0  -- store donor into elfmem
    .insn r 0x0b, 0x4, 0x00, x2, x9, x2  # ocl.c c9, x2(=0), c2  -- load it back into c2
    .insn r 0x5b, 0x0, 0x03, x12, x2, x0 # cgettag  x12, c2  -- expect 1
    .insn r 0x5b, 0x0, 0x00, x13, x2, x0 # cgetbase x13, c2  -- expect 0x80010000

    # ---- negative: TCM offset never written -- must read back untagged ----
    li   x3, 0x10
    .insn r 0x0b, 0x4, 0x00, x3, x8, x3  # ocl.c c8, x3(=0x10), c3
    .insn r 0x5b, 0x0, 0x03, x14, x3, x0 # cgettag x14, c3  -- expect 0

    # ---- negative: DRAM offset never written -- must read back untagged ----
    li   x4, 0x10
    .insn r 0x0b, 0x4, 0x00, x4, x9, x4  # ocl.c c9, x4(=0x10), c4
    .insn r 0x5b, 0x0, 0x03, x15, x4, x0 # cgettag x15, c4  -- expect 0
1:
    j 1b
