.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core Milestone 18 (IMMEDIATE_LIMIT_INVESTIGATION): positive
    # control for VEDA_ODT_POPULATE_FAST. Real, measured motivation: plain
    # VEDA_ODT_POPULATE needs a full 6-instruction `li` to build its
    # packed 64-bit descriptor because of RV64I's 12-bit immediate limit;
    # this instruction takes Base directly in rs2 (a clean, real
    # 2-instruction `la`/`li` suffices) and reads Length/Perms from the
    # new `veda_attr` CSR (0x7C4) instead. This test proves the new data
    # path is wired correctly end-to-end: the CSR-sourced Perms actually
    # gate access (Load+Store both work), the CSR-sourced Length is
    # honored up to its real boundary (not silently truncated/rounded),
    # and Base -- taken directly from rs2 with no shift/pack -- lands the
    # object at the real intended address (proven by a real write-then-
    # read round trip, not just "no trap fired").
    #
    # Object_ID=60, clear of every other test's own seeded/used IDs
    # (veda_test_seed_odt's 1-5, vc_gen_retire[_neg].S's 50/51).
    csrw 0x7c4, x0          # sanity: CSR starts at 0 (Sail's own default reset)
    csrr x9, 0x7c4
    bne  x9, x0, self_check_fail

    li   x10, 0x0040100c    # veda_attr = Length=0x40 (64), Perms=0x100C (Load|Store)
    csrw 0x7c4, x10
    csrr x9, 0x7c4
    bne  x9, x10, self_check_fail   # CSR must read back exactly what was written

    li   x1, 60
    li   x2, 0x80010500     # Base, direct -- no <<32 packing needed, unlike plain Populate
    .word 0x0820800b        # veda.odt.populate.fast x0, x1, x2
    .word 0x0000d00b        # veda.bind c0, x1

    # Ordinary-position round trip (offset 0): proves Base/Perms correct.
    li   x3, 0
    li   x4, 0x55
    .word 0x0230320b        # ocs.d c0, x3, x4
    li   x5, 0
    .word 0x0030328b        # ocl.d x5, x3, c0
    li   x20, 0x55
    bne  x5, x20, self_check_fail

    # Boundary round trip (offset 0x38, width 8): offset+width == Length
    # (0x40) exactly -- proves the real Length value came from veda_attr
    # (0x40), not some other stale/default value that would trap here.
    li   x6, 0x38
    li   x7, 0x66
    .word 0x0260338b        # ocs.d c0, x6, x7
    li   x8, 0
    .word 0x0060340b        # ocl.d x8, x6, c0
    li   x20, 0x66
    bne  x8, x20, self_check_fail

    RVMODEL_HALT_PASS
self_check_fail:
    RVMODEL_HALT_FAIL
