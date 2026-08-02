.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 5: closes a real, honest test-coverage
    # gap left open since Milestone 2 -- NMC_ADD.W and 8 of Veda-
    # Atomic's 9 ops (only AMOXOR was independently tested in M2) share
    # the identical, already-built ALU-mux/decode/write-back RTL
    # (confirmed by re-reading veda_core.tlv before writing this test:
    # the mux already lists all 9 ops, NMC_ADD.W's own decode/gating/
    # write-back already exist) -- this milestone is pure verification
    # of already-existing hardware, not new RTL. The signed MIN/MAX
    # comparator ($veda_atomic_lt_signed) in particular has never been
    # exercised by any real test until now.
    #
    # A first draft of this test wrongly assumed NMC_ADD/Veda-Atomic
    # take a GPR-supplied offset the way OCL/OCS do -- they don't
    # (re-confirmed against veda_core.tlv: $veda_cap_real_addr =
    # rs1cap.Base + rs1cap.Offset, the capability's own persistent
    # cursor, exactly like OCA/NMC_ADD's whole "compute-at-memory"
    # design point). That first draft failed its own simulation run --
    # a real, honest test-design bug caught by actually running it, not
    # an RTL bug (see MILESTONE_5_RESULTS.md). Fixed here by using OCA
    # to walk c1's own Offset cursor between ops, matching the real
    # intended usage pattern (position via OCA, then dispatch a
    # compute-at-memory op right there).
    # ─────────────────────────────────────────────────────────────
    # RTL Milestone 9 addendum: this file's own final NMC_ADD.W (the
    # deliberate no-Permit_NMC_Compute negative check) is a "use"-family
    # violation -- since Milestone 9 this now genuinely traps instead of
    # only suppressing the write. Install a generic "skip and resume"
    # handler up front (see veda_smoke_m4.S's own identical addendum for
    # the full reasoning) so this file's original x28-survives-untouched
    # assertion keeps meaning exactly what it always meant.
    la   t0, generic_trap_handler
    csrw mtvec, t0

    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1   (Object_ID=1: Base=0x80010000 Perms=0x100C, HAS NMC_Compute)
    li   x1, 2
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1   (Object_ID=2: Base=0x80010100 Perms=0x000C, Load+Store ONLY -- no NMC_Compute)

    # ── NMC_ADD.W, via c0 (has NMC_Compute; c0.Offset stays at its
    #    bind-time default of 0 throughout, which is also the GPR
    #    offset used for OCS.D/OCL.D below, so both addressing modes
    #    agree here) ────────────────────────────────────────────
    # Exercises two genuinely untested behaviors at once: (1) the old
    # value's sign-extension into a 64-bit rd when bit31 is set
    # ({{32{cap_old_w[31]}}, cap_old_w}); (2) that the write-back only
    # touches the low 4 bytes of the 8-byte memory word, leaving the
    # upper 4 bytes untouched.
    li   x2, 0
    li   x3, 0xCAFEBABE80000000
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2  # ocs.d c0, x2, x3   -- full doubleword = 0xCAFEBABE_80000000
    li   x3, 0x20
    .insn r 0x0b, 0x2, 0x02, x10, x0, x3  # nmc_add.w x10, c0, x3  -- expect x10 = sign_extend32(0x80000000) = 0xFFFFFFFF80000000
    .insn r 0x0b, 0x3, 0x00, x11, x0, x2  # ocl.d c0, x2, x11      -- expect x11 = 0xCAFEBABE80000020 (upper 4 bytes untouched, low 4 bytes = 0x80000000+0x20)

    # ── Veda-Atomic, via c1 (Load+Store only, deliberately NO
    #    NMC_Compute -- also reconfirms Atomic's own real permission
    #    gate is Load+Store, not NMC_Compute, by construction, not
    #    just by assertion). c1.Offset starts at 0 (bind default) and
    #    is walked forward by OCA in fixed +8 steps to match each
    #    OCS.D/OCL.D pair's own GPR-supplied offset. ────────────────
    li   x9, 8                # constant OCA step (reused for every reposition below)

    # SWAP @0x00 -- c1.Offset already 0, no OCA needed yet
    li   x2, 0
    li   x3, 0x1111
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2  # ocs.d c1, x2, x3
    li   x3, 0x2222
    .insn r 0x2b, 0x3, 0x04, x12, x1, x3  # veda.atomic.swap x12, c1, x3  -- expect x12(old) = 0x1111
    .insn r 0x0b, 0x3, 0x00, x20, x1, x2  # ocl.d c1, x2, x20            -- expect x20(new) = 0x2222

    # ADD @0x08
    .insn r 0x5b, 0x1, 0x0a, x1, x1, x9  # oca c1, c1, x9  (Offset: 0 -> 8)
    li   x2, 8
    li   x3, 5
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2  # ocs.d c1, x2, x3
    li   x3, 0xA
    .insn r 0x2b, 0x3, 0x00, x13, x1, x3  # veda.atomic.add x13, c1, x3   -- expect x13(old) = 5
    .insn r 0x0b, 0x3, 0x00, x21, x1, x2  # ocl.d c1, x2, x21            -- expect x21(new) = 0xF

    # AND @0x10
    .insn r 0x5b, 0x1, 0x0a, x1, x1, x9  # oca c1, c1, x9  (Offset: 8 -> 16)
    li   x2, 16
    li   x3, 0xFF
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2  # ocs.d c1, x2, x3
    li   x3, 0x0F
    .insn r 0x2b, 0x3, 0x30, x14, x1, x3  # veda.atomic.and x14, c1, x3   -- expect x14(old) = 0xFF
    .insn r 0x0b, 0x3, 0x00, x22, x1, x2  # ocl.d c1, x2, x22            -- expect x22(new) = 0x0F

    # OR @0x18
    .insn r 0x5b, 0x1, 0x0a, x1, x1, x9  # oca c1, c1, x9  (Offset: 16 -> 24)
    li   x2, 24
    li   x3, 0xF0
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2  # ocs.d c1, x2, x3
    li   x3, 0x0F
    .insn r 0x2b, 0x3, 0x20, x15, x1, x3  # veda.atomic.or  x15, c1, x3   -- expect x15(old) = 0xF0
    .insn r 0x0b, 0x3, 0x00, x23, x1, x2  # ocl.d c1, x2, x23            -- expect x23(new) = 0xFF

    # MIN (signed) @0x20 -- old=-1, rs2=1: signed(-1 < 1) -> keeps old
    .insn r 0x5b, 0x1, 0x0a, x1, x1, x9  # oca c1, c1, x9  (Offset: 24 -> 32)
    li   x2, 32
    li   x3, -1
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2  # ocs.d c1, x2, x3
    li   x3, 1
    .insn r 0x2b, 0x3, 0x40, x16, x1, x3  # veda.atomic.min x16, c1, x3   -- expect x16(old) = 0xFFFFFFFFFFFFFFFF
    .insn r 0x0b, 0x3, 0x00, x24, x1, x2  # ocl.d c1, x2, x24            -- expect x24(new) = 0xFFFFFFFFFFFFFFFF (old kept)

    # MAX (signed) @0x28 -- old=-1, rs2=1: signed(-1 < 1) -> takes rs2
    .insn r 0x5b, 0x1, 0x0a, x1, x1, x9  # oca c1, c1, x9  (Offset: 32 -> 40)
    li   x2, 40
    li   x3, -1
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2  # ocs.d c1, x2, x3
    li   x3, 1
    .insn r 0x2b, 0x3, 0x50, x17, x1, x3  # veda.atomic.max x17, c1, x3   -- expect x17(old) = 0xFFFFFFFFFFFFFFFF
    .insn r 0x0b, 0x3, 0x00, x25, x1, x2  # ocl.d c1, x2, x25            -- expect x25(new) = 1

    # MINU (unsigned) @0x30 -- old=0xFFFF...FFFF, rs2=1: unsigned(huge > 1) -> takes rs2
    .insn r 0x5b, 0x1, 0x0a, x1, x1, x9  # oca c1, c1, x9  (Offset: 40 -> 48)
    li   x2, 48
    li   x3, -1
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2  # ocs.d c1, x2, x3
    li   x3, 1
    .insn r 0x2b, 0x3, 0x60, x18, x1, x3  # veda.atomic.minu x18, c1, x3  -- expect x18(old) = 0xFFFFFFFFFFFFFFFF
    .insn r 0x0b, 0x3, 0x00, x26, x1, x2  # ocl.d c1, x2, x26            -- expect x26(new) = 1

    # MAXU (unsigned) @0x38 -- old=0xFFFF...FFFF, rs2=1: unsigned(huge > 1) -> keeps old
    .insn r 0x5b, 0x1, 0x0a, x1, x1, x9  # oca c1, c1, x9  (Offset: 48 -> 56)
    li   x2, 56
    li   x3, -1
    .insn r 0x0b, 0x3, 0x01, x3, x1, x2  # ocs.d c1, x2, x3
    li   x3, 1
    .insn r 0x2b, 0x3, 0x70, x19, x1, x3  # veda.atomic.maxu x19, c1, x3  -- expect x19(old) = 0xFFFFFFFFFFFFFFFF
    .insn r 0x0b, 0x3, 0x00, x27, x1, x2  # ocl.d c1, x2, x27            -- expect x27(new) = 0xFFFFFFFFFFFFFFFF (old kept)

    # ── Negative check: NMC_ADD.W's OWN gating path, not previously
    #    exercised (M2's own negative test only covered NMC_ADD.D's
    #    permission violation -- $veda_nmc_add_w_violation is a
    #    separate signal, never independently confirmed until now).
    #    c1 = Object_ID=2, no Permit_NMC_Compute. c1.Offset is now 56,
    #    still within Length=0x40's own 4-byte-access bound (56+4<=64),
    #    so the violation below is purely the permission check, not
    #    conflated with a bounds violation. ──────────────────────────
    li   x28, 0x5555
    li   x3, 0x99
    .insn r 0x0b, 0x2, 0x02, x28, x1, x3  # nmc_add.w x28, c1, x3   -- must be blocked; x28 must stay 0x5555
1:
    j 1b

generic_trap_handler:
    csrr t6, mepc
    addi t6, t6, 4
    csrw mepc, t6
    mret
