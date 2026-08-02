.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 8: Rebind -- the concrete mechanism that
    # makes this project's own headline design claim literally provable
    # in RTL, not just Sail: "the MSA can silently relocate an object
    # (Base changes) while software's own relative position (Offset)
    # and identity (Object_ID) never move" (VEDA_CORE_SPEC.md Section
    # 1/Section 4).
    #
    # Proof structure, all against ONE capability register (c1) and ONE
    # object (Object_ID=20), so every step is directly comparable:
    #   1) Populate Object_ID=20 at Base=0x80010500, bind c1, walk its
    #      Offset to 8 via OCA, and prove a real AMO write/read round-
    #      trips through that OLD physical address (0x80010508).
    #   2) Re-populate the SAME Object_ID=20 at a NEW Base=0x80010600
    #      (simulating the MSA silently relocating the object) -- this
    #      also bumps the ODT slot's generation counter.
    #   3) Prove c1 is now correctly rejected as STALE (its cached
    #      generation no longer matches) -- the real security property
    #      that exists precisely so a relocation can't be silently
    #      exploited by an unrefreshed capability.
    #   4) Rebind c1 -- prove its Offset is STILL 8 (untouched,
    #      preserved across the relocation) and its Base is now the
    #      NEW address, via CGetOffset/CGetBase queries.
    #   5) Prove the relocation is functionally real, not just
    #      metadata: a fresh AMO write/read via c1's still-8 Offset now
    #      round-trips through the NEW physical address (0x80010608),
    #      not the old one -- software never recomputed anything.
    # ─────────────────────────────────────────────────────────────
    # RTL Milestone 9 addendum: Step 3's own deliberate stale-generation
    # AMO is a "use"-family violation -- since Milestone 9 this now
    # genuinely traps instead of only suppressing the write. Install a
    # generic "skip and resume" handler up front (see veda_smoke_m4.S's
    # own identical addendum for the full reasoning) so this file's
    # original x11-survives-untouched assertion, and the rest of the
    # Rebind proof that follows it, keep working exactly as before.
    la   t0, generic_trap_handler
    csrw mtvec, t0

    # -- Step 1: Object_ID=20 -> Base=0x80010500, Length=0x40,
    #    Perms=0x000C (Load+Store only, matches Veda-Atomic's own
    #    requirement of both bits).
    li   x1, 20
    li   x2, 0x800105000040000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 20
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1        -- c1: Base=0x80010500, Offset=0, Tag=1

    li   x9, 8
    .insn r 0x5b, 0x1, 0x0a, x1, x1, x9  # oca c1, c1, x9          -- c1.Offset: 0 -> 8

    # AMO's own "old value" read is real memory content -- elfmem is
    # NOT zero-initialized outside the ELF-loaded region (only the
    # code bytes $readmemh actually supplies are defined; every other
    # byte is genuinely undefined in this Icarus simulation, exactly
    # like real uninitialized DRAM). Seed a deterministic 0 via a
    # plain OCS.D first (the same real reason every prior milestone's
    # own AMO tests always store before reading -- MILESTONE_5_RESULTS.md's
    # own vc_nmc_add_w_and_atomic8.S test does the identical seed-then-AMO
    # pattern for the same reason), so the AMO's old-value result is
    # verifiable rather than simulator-undefined.
    li   x2, 8
    .insn r 0x0b, 0x3, 0x01, x0, x1, x2  # ocs.d c1, x2, x0        -- seed memory @ (0x80010500+8) = 0
    li   x3, 5
    .insn r 0x2b, 0x3, 0x00, x10, x1, x3  # veda.amoadd.d x10, c1, x3   -- old value(0) @ (0x80010500+8) into x10, writes 0+5=5
    .insn r 0x0b, 0x3, 0x00, x20, x1, x2  # ocl.d c1, x2, x20       -- independent read-back @ same address -- expect x20=5

    # -- Step 2: silently relocate Object_ID=20 -> Base=0x80010600
    #    (same Length/Perms) -- bumps the ODT slot's own generation,
    #    exactly like a real MSA-driven object move would.
    li   x1, 20
    li   x2, 0x800106000040000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    # -- Step 3: c1 is now stale (cached generation != ODT's new
    #    generation) -- a real AMO through c1 must be rejected, leaving
    #    BOTH the memory write and the GPR write suppressed. x11 is
    #    pre-loaded with a sentinel so a silent pass-through would be
    #    caught (mirrors MILESTONE_6_RESULTS.md's own sentinel idiom).
    li   x11, 0xDEAD
    li   x3, 9
    .insn r 0x2b, 0x3, 0x00, x11, x1, x3  # veda.amoadd.d x11, c1, x3   -- must soft-fail (gen_stale): x11 stays 0xDEAD

    # -- Step 4: Rebind c1 against the SAME Object_ID=20 (x1 already
    #    holds 20 from Step 2) -- refreshes Base/generation from the
    #    ODT, but Offset must NOT move.
    .insn i 0x0b, 0x5, x1, x1, 2  # veda.rebind c1, x1

    .insn r 0x5b, 0x0, 0x06, x12, x1, x0  # cgetoffset x12, c1      -- expect 8  (PRESERVED, the entire point of Rebind)
    .insn r 0x5b, 0x0, 0x00, x13, x1, x0  # cgetbase   x13, c1      -- expect 0x80010600 (the NEW, relocated Base)
    .insn r 0x5b, 0x0, 0x03, x16, x1, x0  # cgettag    x16, c1      -- expect 1  (real success: ODT valid, c1 wasn't sealed)

    # -- Step 5: functional proof -- a fresh AMO through c1's own
    #    still-8 Offset must now land at the NEW physical address
    #    (0x80010600+8 = 0x80010608), a byte elfmem never touched
    #    before (distinct from Step 1's 0x80010508, which already
    #    holds 5) -- seed it deterministically first, same real reason
    #    as Step 1's own seed above (elfmem is simulator-undefined
    #    outside the ELF-loaded region, not zero by default).
    li   x2, 8
    .insn r 0x0b, 0x3, 0x01, x0, x1, x2  # ocs.d c1, x2, x0        -- seed memory @ (0x80010600+8) = 0
    li   x3, 5
    .insn r 0x2b, 0x3, 0x00, x14, x1, x3  # veda.amoadd.d x14, c1, x3   -- expect x14=0 (the just-seeded old value at the NEW address)
    .insn r 0x0b, 0x3, 0x00, x21, x1, x2  # ocl.d c1, x2, x21       -- expect x21=5 (write really landed at the NEW address)

1:
    j 1b

generic_trap_handler:
    csrr t6, mepc
    addi t6, t6, 4
    csrw mepc, t6
    mret
