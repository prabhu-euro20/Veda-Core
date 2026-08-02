.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 8: Rebind's three real failure/no-op
    # paths, each proving a distinct, deliberate design decision
    # (veda_bind_insts.sail's own VEDA_REBIND match arm):
    #   1) Rebind on an already-SEALED destination register soft-fails
    #      (Tag cleared) WITHOUT touching any other field -- Section
    #      1's manipulate-vs-use split ("Rebind... a 'manipulate', not
    #      a 'use'... soft-fails... joining OCA/CSetBounds").
    #   2) Rebind against an Object_ID with no ODT entry soft-fails the
    #      same way -- Tag cleared, every other field left exactly as
    #      it was (Sail's execute clause never calls wC() on either
    #      failure path, only wCTag(false)).
    #   3) Rebind's reserved mode (imm[1:0]=11) is a complete no-op --
    #      the real, previously-undetected gap this milestone closed
    #      (RTL Milestone 8's own decode comment): before this
    #      milestone, ANY non-zero mode silently executed as plain
    #      Bind, so this specifically regression-tests that a reserved-
    #      mode encoding no longer corrupts an already-valid capability
    #      register at all.
    # ─────────────────────────────────────────────────────────────

    # -- Fixture: a real type-authority object (Object_ID=30,
    #    Permit_Seal|Permit_Unseal = bits 8+9 = 0x0300), minted via
    #    ODT-Populate exactly like MILESTONE_6_RESULTS.md's own fixture
    #    (neither RTL-seeded reset object, Object_ID=1/2, carries those
    #    bits) -- this test's own program, own reset, so it can't reuse
    #    Milestone 6's ODT state and must mint its own.
    li   x1, 30
    li   x2, 0x8001070000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 30
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1        -- c2: the type-authority capability

    li   x1, 1
    .insn i 0x0b, 0x5, x3, x1, 0  # veda.bind c3, x1        -- c3: Object_ID=1 (reset-seeded), the "data" capability to be sealed

    .insn r 0x5b, 0x1, 0x10, x4, x3, x2  # cseal c4, c3, c2        -- c4 = seal(c3, authority=c2): Tag=1, otype=c2.Offset=0, Base=0x80010000 (copied from c3)

    # -- Negative 1: Rebind a SEALED capability register (c4) --
    #    Object_ID doesn't even matter here (x1 already =1, reused),
    #    since the sealed check short-circuits before the ODT lookup
    #    result is ever consulted.
    .insn i 0x0b, 0x5, x4, x1, 2  # veda.rebind c4, x1
    .insn r 0x5b, 0x0, 0x03, x30, x4, x0  # cgettag  x30, c4        -- expect 0  (Tag cleared)
    .insn r 0x5b, 0x0, 0x04, x31, x4, x0  # cgettype x31, c4        -- expect 0  (otype UNCHANGED -- still shows the seal, proves wC() was never called)
    .insn r 0x5b, 0x0, 0x00, x22, x4, x0  # cgetbase x22, c4        -- expect 0x80010000 (Base UNCHANGED, not reset/corrupted)

    # -- Negative 2: Rebind against a never-populated Object_ID (99) --
    #    a genuine ODT miss, distinct failure path from sealed-rd above.
    li   x1, 1
    .insn i 0x0b, 0x5, x5, x1, 0  # veda.bind c5, x1        -- c5: a fresh, valid capability (Object_ID=1, Tag=1, Base=0x80010000)
    li   x1, 99
    .insn i 0x0b, 0x5, x5, x1, 2  # veda.rebind c5, x1      -- Object_ID=99 was never populated -- ODT miss
    .insn r 0x5b, 0x0, 0x03, x23, x5, x0  # cgettag  x23, c5        -- expect 0  (Tag cleared)
    .insn r 0x5b, 0x0, 0x00, x24, x5, x0  # cgetbase x24, c5        -- expect 0x80010000 (Base UNCHANGED, not reset to 0/garbage)

    # -- Negative 3: reserved mode (imm[1:0]=11) is a true no-op, not a
    #    silent Bind -- regression test for the real gap this milestone
    #    closed (mode field was decoded but never checked before now).
    li   x1, 1
    .insn i 0x0b, 0x5, x6, x1, 0  # veda.bind c6, x1        -- c6: Object_ID=1, Tag=1, Base=0x80010000
    li   x1, 2               # a DIFFERENT Object_ID (2, Base=0x80010100) -- if the old bug were
                              # still present, mode=11 would wrongly re-bind c6 to THIS object
    .insn i 0x0b, 0x5, x6, x1, 3  # veda.bind (mode=11, reserved) c6, x1  -- must be a complete no-op
    .insn r 0x5b, 0x0, 0x03, x25, x6, x0  # cgettag  x25, c6        -- expect 1  (unchanged -- still the ORIGINAL bind's Tag)
    .insn r 0x5b, 0x0, 0x00, x26, x6, x0  # cgetbase x26, c6        -- expect 0x80010000 (unchanged -- NOT Object_ID=2's 0x80010100)

1:
    j 1b
