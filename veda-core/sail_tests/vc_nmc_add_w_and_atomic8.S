.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Closes the real, honest test-coverage gap already found and closed
    # on the RTL side (rtl/MILESTONE_5_RESULTS.md): NMC_ADD.W and 8 of
    # Veda-Atomic's 9 ops (only AMOXOR.D was independently tested in this
    # project's own Sail work, MILESTONE_V-B_RESULTS.md's own "Not yet
    # built" list) share already-built decode/execute logic that was
    # never independently exercised in Sail either.
    #
    # A first draft of this test's own negative check (NMC_ADD.W missing
    # Permit_NMC_Compute) treated the violation as a soft-fail, mirroring
    # RTL's own convention -- and hung in a real trap loop, because
    # unlike RTL, Sail's own NMC_ADD genuinely hard-traps on this
    # violation (mcause=0x18, mtval=0x1F -- already real, verified
    # behavior, MILESTONE_V-B_RESULTS.md). Fixed by installing a real
    # trap handler (the same reusable pattern vc_nmc_add_neg.S already
    # established) and moving the negative check to the end, so all the
    # positive results are already computed and sitting in registers
    # before the one instruction that's expected to trap runs.
    li   x1, 1
    .word 0x0000d00b    # veda.bind c0, x1  (Object_ID=1: Perms=0x100C, HAS Permit_NMC_Compute)
    li   x1, 2
    .word 0x0000d08b     # veda.bind c1, x1  (Object_ID=2: Perms=0x000C, Load+Store ONLY -- no Permit_NMC_Compute)

    # -- NMC_ADD.W via c0: sign-extension of the old 32-bit value into a
    #    64-bit rd, and that the write-back only touches the low 4 bytes,
    #    leaving the upper 4 bytes untouched --
    li   x2, 0
    li   x3, 0xCAFEBABE80000000
    .word 0x0220318b      # ocs.d c0, x2, x3
    li   x3, 0x20
    .word 0x0430250b       # nmc_add.w x10, c0, x3  -- expect x10 = sign_extend32(0x80000000) = 0xFFFFFFFF80000000
    .word 0x0020358b        # ocl.d c0, x2, x11      -- expect x11 = 0xCAFEBABE80000020

    # -- 8 remaining Veda-Atomic ops via c1 (Load+Store only, deliberately
    #    NO Permit_NMC_Compute) -- c1.Offset walked forward in +8 steps
    #    via OCA. Results land in x12-x19 (old value) and x20-x27 (new
    #    memory value, via a fresh ocl.d) --
    li   x9, 8

    # SWAP @0
    li   x2, 0
    li   x3, 0x1111
    .word 0x0220b18b      # ocs.d c1, x2, x3
    li   x3, 0x2222
    .word 0x0830b62b       # veda.amoswap.d x12, c1, x3
    .word 0x0020ba0b        # ocl.d c1, x2, x20

    # ADD @8
    .word 0x149090db      # oca c1, c1, x9
    li   x2, 8
    li   x3, 5
    .word 0x0220b18b      # ocs.d c1, x2, x3
    li   x3, 0xA
    .word 0x0030b6ab       # veda.amoadd.d x13, c1, x3
    .word 0x0020ba8b        # ocl.d c1, x2, x21

    # AND @16
    .word 0x149090db      # oca c1, c1, x9
    li   x2, 16
    li   x3, 0xFF
    .word 0x0220b18b      # ocs.d c1, x2, x3
    li   x3, 0x0F
    .word 0x6030b72b       # veda.amoand.d x14, c1, x3
    .word 0x0020bb0b        # ocl.d c1, x2, x22

    # OR @24
    .word 0x149090db      # oca c1, c1, x9
    li   x2, 24
    li   x3, 0xF0
    .word 0x0220b18b      # ocs.d c1, x2, x3
    li   x3, 0x0F
    .word 0x4030b7ab       # veda.amoor.d x15, c1, x3
    .word 0x0020bb8b        # ocl.d c1, x2, x23

    # MIN (signed) @32 -- old=-1, rs2=1: signed(-1<1) -> keeps old
    .word 0x149090db      # oca c1, c1, x9
    li   x2, 32
    li   x3, -1
    .word 0x0220b18b      # ocs.d c1, x2, x3
    li   x3, 1
    .word 0x8030b82b       # veda.amomin.d x16, c1, x3
    .word 0x0020bc0b        # ocl.d c1, x2, x24

    # MAX (signed) @40 -- old=-1, rs2=1: signed(-1<1) -> takes rs2
    .word 0x149090db      # oca c1, c1, x9
    li   x2, 40
    li   x3, -1
    .word 0x0220b18b      # ocs.d c1, x2, x3
    li   x3, 1
    .word 0xa030b8ab       # veda.amomax.d x17, c1, x3
    .word 0x0020bc8b        # ocl.d c1, x2, x25

    # MINU (unsigned) @48 -- old=0xFFFF...FFFF, rs2=1: unsigned(huge>1) -> takes rs2
    .word 0x149090db      # oca c1, c1, x9
    li   x2, 48
    li   x3, -1
    .word 0x0220b18b      # ocs.d c1, x2, x3
    li   x3, 1
    .word 0xc030b92b       # veda.amominu.d x18, c1, x3
    .word 0x0020bd0b        # ocl.d c1, x2, x26

    # MAXU (unsigned) @56 -- old=0xFFFF...FFFF, rs2=1: unsigned(huge>1) -> keeps old
    .word 0x149090db      # oca c1, c1, x9
    li   x2, 56
    li   x3, -1
    .word 0x0220b18b      # ocs.d c1, x2, x3
    li   x3, 1
    .word 0xe030b9ab       # veda.amomaxu.d x19, c1, x3
    .word 0x0020bd8b        # ocl.d c1, x2, x27

    # -- All positive results are now computed and safely in registers.
    #    Install the trap handler, then trigger the one real negative
    #    check: NMC_ADD.W via c1 (no Permit_NMC_Compute) -- this
    #    genuinely hard-traps in Sail, unlike RTL's own soft-fail
    #    convention -- do not fall through expecting normal execution.
    la   t0, trap_handler
    csrw mtvec, t0
    li   x3, 0x99
    .word 0x0430ae0b       # nmc_add.w x28, c1, x3  -- must trap, cause 0x1f, cap_idx=1 (c1)
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    # veda_xtval(cap_idx, cause) = zero_extend(cap_idx5 @ cause) --
    # confirmed directly from source (veda_bind_insts.sail), not assumed:
    # cap_idx=1 (c1, the capability this negative check used) at bits
    # [9:5], cause=0x1F (Permit_NMC_Compute violation) at bits [4:0] =
    # (1<<5)|0x1F = 0x3F, not the cap_idx=0 value (0x1F alone) this
    # test's own first draft assumed by copying vc_nmc_add_neg.S's own
    # expected value without checking that test's own capability index
    # (c0, not c1) actually matched this one's.
    li   t4, 0x3F
    bne  t3, t4, fail

    li   t4, 0xFFFFFFFF80000000
    bne  x10, t4, fail
    li   t4, 0xCAFEBABE80000020
    bne  x11, t4, fail

    li   t4, 0x1111
    bne  x12, t4, fail
    li   t4, 0x2222
    bne  x20, t4, fail

    li   t4, 0x5
    bne  x13, t4, fail
    li   t4, 0xF
    bne  x21, t4, fail

    li   t4, 0xFF
    bne  x14, t4, fail
    li   t4, 0xF
    bne  x22, t4, fail

    li   t4, 0xF0
    bne  x15, t4, fail
    li   t4, 0xFF
    bne  x23, t4, fail

    li   t4, -1
    bne  x16, t4, fail
    bne  x24, t4, fail

    li   t4, -1
    bne  x17, t4, fail
    li   t4, 1
    bne  x25, t4, fail

    li   t4, -1
    bne  x18, t4, fail
    li   t4, 1
    bne  x26, t4, fail

    li   t4, -1
    bne  x19, t4, fail
    bne  x27, t4, fail

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
