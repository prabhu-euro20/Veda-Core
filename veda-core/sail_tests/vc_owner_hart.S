.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core formal model: owner-hart ODT enforcement -- Milestone 12
    # (VEDA_CORE_SPEC.md §4.1, closing the spec's own long-named gap: "an
    # owner-hart field in the ODT entry, checked at Bind/Rebind time").
    #
    # This project's own Sail test config genuinely cannot produce two
    # real, concurrently-executing harts (this single-process C emulator
    # runs exactly one `mhartid`, config-fixed at 0 -- veda_test_sail.json
    # has no multi-hart support, distinct from the earlier-documented
    # S/U-mode limitation in MILESTONE_11_RESULTS.md). This positive test
    # therefore proves the two paths genuinely reachable from a single
    # real hart: (a) claiming a genuinely-unowned object, and (b) a
    # self-owned idempotent re-claim via Rebind -- both real,
    # non-injected executions. The wrong-owner hard-trap path (only
    # reachable here via direct ODT-state injection, since no second real
    # hart exists to own anything) is covered separately in
    # vc_owner_hart_neg.S; wrong-owner Rebind's own soft-fail (never a
    # trap, matching Rebind's manipulate-vs-use convention) is proven
    # right here using the same injected fixture, for completeness.

    # -- Step 1: Object_ID=1 (reset-seeded, VEDA_OWNER_UNOWNED) -- a
    #    plain Bind must succeed AND claim it for this hart (mhartid=0). --
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    .insn r 0x5b, 0x0, 0x03, x10, x0, x0  # cgettag  x10, c0   -- expect 1
    .insn r 0x5b, 0x0, 0x00, x11, x0, x0  # cgetbase x11, c0   -- expect 0x80010000

    # -- Step 2: Rebind the SAME object -- now owned by hart 0, this
    #    hart's own real mhartid, so owner_ok must take the "self-owns"
    #    branch (not the "unowned" branch, already proven in Step 1) --
    #    a real, distinct code path (owner_hart == mhartid, not
    #    owner_hart == VEDA_OWNER_UNOWNED). --
    .insn i 0x0b, 0x5, x0, x1, 2  # veda.rebind c0, x1
    .insn r 0x5b, 0x0, 0x03, x12, x0, x0  # cgettag  x12, c0   -- expect 1 (still bound, re-claim succeeded)
    .insn r 0x5b, 0x0, 0x00, x13, x0, x0  # cgetbase x13, c0   -- expect 0x80010000 (unchanged, same object)

    # -- Step 3: Object_ID=5 -- a fixture injected directly into the ODT
    #    by veda_test_seed_odt() (veda_regs.sail), pre-claimed by a
    #    hypothetical "other hart" (owner_hart=0x63/99), standing in for
    #    a real second hart this single-process simulator cannot produce.
    #    Bind-NoTrap on a wrong-owner object must soft-fail (Tag cleared,
    #    no trap) -- matching every other Bind-NoTrap failure reason. --
    li   x5, 5
    .insn i 0x0b, 0x5, x1, x5, 1  # veda.bind.notrap c1, x5
    .insn r 0x5b, 0x0, 0x03, x14, x1, x0  # cgettag  x14, c1   -- expect 0 (soft-fail, wrong owner)

    # -- Step 4: Rebind against the SAME wrong-owner object (Object_ID=5)
    #    -- Rebind never traps for ANY reason (Section 1's manipulate-vs-
    #    use split), so a wrong-owner Rebind must ALSO soft-fail, not
    #    hard-trap. Use a freshly-bound register (c2, Object_ID=1) as the
    #    Rebind target so the "already sealed" short-circuit definitely
    #    doesn't fire first -- isolates the owner-check path specifically. --
    li   x1, 1
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1        -- c2: Object_ID=1, Tag=1, Base=0x80010000
    .insn r 0x5b, 0x0, 0x03, x15, x2, x0  # cgettag  x15, c2   -- expect 1
    .insn r 0x5b, 0x0, 0x00, x16, x2, x0  # cgetbase x16, c2   -- expect 0x80010000
    li   x5, 5
    .insn i 0x0b, 0x5, x2, x5, 2  # veda.rebind c2, x5      -- Object_ID=5, wrong owner
    .insn r 0x5b, 0x0, 0x03, x17, x2, x0  # cgettag  x17, c2   -- expect 0 (soft-fail, Tag cleared)
    .insn r 0x5b, 0x0, 0x00, x18, x2, x0  # cgetbase x18, c2   -- expect 0x80010000 (UNCHANGED -- still c2's OLD Base, never overwritten by Object_ID=5's 0x80010400)

    li   t0, 1
    bne  x10, t0, fail
    li   t0, 0x80010000
    bne  x11, t0, fail
    li   t0, 1
    bne  x12, t0, fail
    li   t0, 0x80010000
    bne  x13, t0, fail
    li   t0, 0
    bne  x14, t0, fail
    li   t0, 1
    bne  x15, t0, fail
    li   t0, 0x80010000
    bne  x16, t0, fail
    li   t0, 0
    bne  x17, t0, fail
    li   t0, 0x80010000
    bne  x18, t0, fail

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
