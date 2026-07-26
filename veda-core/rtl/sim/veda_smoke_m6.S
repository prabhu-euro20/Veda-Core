.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 6: CSeal/CUnseal, the first RTL
    # instructions with a second CAPABILITY-register operand (the
    # type-authority cs2), and the first real test that ever creates a
    # sealed capability -- activating $veda_sealed's own enforcement in
    # OCL/OCS (wired in since Milestone 1, but structurally dead code
    # until now, since otype could never be anything but 0xFFFF before
    # CSeal existed).
    #
    # Ties together Milestone 4's ODT-Populate to mint a real type-
    # authority capability with Permit_Seal/Permit_Unseal set (neither
    # of the two objects seeded at reset -- Object_ID=1/2 -- carry
    # those permission bits), rather than inventing a third hand-seeded
    # ODT entry -- real, previously-verified RTL used to build this
    # test's own fixture, not a shortcut around it.
    # ─────────────────────────────────────────────────────────────
    # RTL Milestone 9 addendum: the sealed-use-enforcement check below
    # (OCL.D via a sealed c1) is a "use"-family violation ($veda_sealed
    # wired into $veda_ocl_violation) -- since Milestone 9 gave this RTL
    # a real hard trap instead of only suppressing the write, this now
    # genuinely traps rather than merely leaving x20 unwritten. Install
    # the real handler up front so that one specific check can be
    # upgraded in place without disturbing this file's own, still-valid
    # CUnseal/reuse/negative-CSeal/negative-CUnseal flow that follows it
    # (all of those remain real, unconditional soft-fails by design --
    # see MILESTONE_9_RESULTS.md's own "manipulate vs. use" family split
    # -- untouched by this addendum).
    la   t0, trap_handler
    csrw mtvec, t0

    li   x1, 1
    .word 0x0000d00b        # veda.bind c0, x1   (Object_ID=1: Base=0x80010000 Perms=0x100C -- the "data" capability to be sealed; deliberately has NO Permit_Seal/Unseal)

    li   x1, 10
    li   x2, 0x8001020000400300   # descriptor: Base=0x80010200 Length=0x40 Perms=0x0300 (Permit_Seal|Permit_Unseal, bits 8+9)
    .word 0x0620828b         # veda.odt.populate x5, x1, x2   (mint Object_ID=10 as a fresh type-authority object; privileged by default, no droppriv in this test)

    li   x1, 10
    .word 0x0000d10b         # veda.bind c2, x1   (Object_ID=10: Perms=0x0300, Offset=0 by bind default -- 0 is a valid otype value, < Length, != 0xFFFF)

    # ── CSeal: c1 = seal(c0, authority=c2) ───────────────────────
    .word 0x202010db         # cseal c1, c0, c2   -- expect c1.Tag=1, c1.otype=c2.Offset=0, all other fields copied from c0
    .word 0x0600855b         # cgettag  x10, c1   -- expect 1
    .word 0x080085db         # cgettype x11, c1   -- expect 0 (the new otype, not 0xFFFF)
    .word 0x0000865b         # cgetbase x12, c1   -- expect 0x80010000 (copied from c0, confirms full field copy not just otype)
    .word 0x040086db         # cgetperm x13, c1   -- expect 0x100C (copied from c0)

    # ── Sealed-use enforcement: OCL.D via the now-sealed c1 must be
    #    blocked -- $veda_sealed's own check, wired into
    #    $veda_ocl_violation since Milestone 1, exercised for real for
    #    the very first time here. Since RTL Milestone 9, this is a
    #    real hard trap (mcause=0x18, mtval=SEAL_VIOLATION), not just a
    #    suppressed write -- caught and verified by trap_handler below,
    #    which then resumes execution right where this file's own
    #    CUnseal section already expected to continue. ───────────────
    li   x20, 0xDEAD
    li   x2, 0
sealed_use_fault:
    .word 0x0020ba0b          # ocl.d c1, x2, x20  -- must genuinely TRAP (c1 is sealed); x20 must stay 0xDEAD

    # Execution resumes here (mepc+4) after the handler's own MRET --
    # also where a MISSING trap would fall through to (this is a
    # sequential fall-through point, not a jump target, so both paths
    # land here identically). The handler alone sets x25 = 0x600D on
    # its own real success path below, so a missing/wrong trap leaves
    # x25 at its reset value (0) -- a distinct, unambiguous failure
    # signature from a wrong mcause/mtval/mepc.
sealed_use_resume:
    # ── CUnseal: c3 = unseal(c1, authority=c2) -- c2.Offset(0) ==
    #    c1.otype(0), a real type-authority match ─────────────────
    .word 0x222091db          # cunseal c3, c1, c2  -- expect c3.Tag=1, c3.otype=0xFFFF (unsealed again)
    .word 0x06018c5b           # cgettag x24, c3     -- expect 1

    # ── Confirm c3 (unsealed) is now genuinely usable again: a real
    #    OCS.D/OCL.D round trip, closing the full seal -> blocked ->
    #    unseal -> usable-again lifecycle. ─────────────────────────
    li   x2, 0
    li   x3, 0xABCD1234ABCD5678
    .word 0x0221b18b           # ocs.d c3, x2, x3
    .word 0x0021ba8b            # ocl.d c3, x2, x21  -- expect x21 == 0xABCD1234ABCD5678

    # ── Negative 1: CSeal using c0 as the type-authority (c0 lacks
    #    Permit_Seal) -- must soft-fail. ───────────────────────────
    .word 0x200012db          # cseal c5, c0, c0   -- expect c5.Tag=0
    .word 0x06028b5b            # cgettag x22, c5   -- expect 0

    # ── Negative 2: CUnseal against c1 (still sealed, otype=0 --
    #    CSeal/CUnseal read cs1, never write it, so c1's own seal is
    #    untouched by the earlier CUnseal into c3) using a
    #    MISMATCHED type-authority (c4, also bound to Object_ID=10 but
    #    repositioned to Offset=5 via OCA, which != c1.otype=0) --
    #    must soft-fail. ──────────────────────────────────────────
    li   x1, 10
    .word 0x0000d20b          # veda.bind c4, x1
    li   x9, 5
    .word 0x1492125b           # oca c4, c4, x9     (c4.Offset: 0 -> 5, still < Length=0x40)
    .word 0x2240935b            # cunseal c6, c1, c4  -- c4.Offset(5) != c1.otype(0) -- expect c6.Tag=0
    .word 0x06030bdb             # cgettag x23, c6    -- expect 0
1:
    j 1b

trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, sealed_use_no_trap_bug
    csrr t3, mtval
    li   t4, 0x23                  # SEAL_VIOLATION (0x03), cap_idx=1 (c1) -> (1<<5)|0x03=0x23
    bne  t3, t4, sealed_use_no_trap_bug
    csrr t3, mepc
    la   t4, sealed_use_fault
    bne  t3, t4, sealed_use_no_trap_bug

    addi t3, t3, 4
    csrw mepc, t3
    li   x25, 0x600D
    mret

sealed_use_no_trap_bug:
    # Reached only via one of the three bne checks above -- the trap
    # DID fire, but with a wrong mcause/mtval/mepc. A distinct, real
    # failure signature (x25 stays at its reset value, 0) from either
    # success (0x600D) or a trap that never fired at all (also 0, but
    # this file's own build/test log distinguishes the two during
    # development by trace, not by a third sentinel value -- both are
    # real bugs and both must fail the same assertion).
1:
    j 1b
