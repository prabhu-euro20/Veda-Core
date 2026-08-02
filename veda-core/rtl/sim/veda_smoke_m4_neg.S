.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 4 negative test: `veda.droppriv` first,
    # then attempt ODT-Populate against a never-before-seeded
    # Object_ID. The privilege gate must suppress the write entirely
    # -- confirmed indirectly through the ISA itself (the query-family
    # verification style already established in Milestone 3): a
    # subsequent Bind against that same Object_ID must come back with
    # Tag=0, since no real ODT entry was ever actually created.
    # ─────────────────────────────────────────────────────────────
    .insn r 0x7b, 0x0, 0x00, x0, x0, x0  # veda.droppriv   -- $priv: 1 -> 0, one-way

    li   x1, 5                       # Object_ID = 5 (never seeded at reset)
    li   x2, 0x800103000040100C      # attempted descriptor -- must never actually land
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- must be suppressed (!$priv)

    # Milestone 13 update: this file installs no trap handler at all
    # (mtvec stays at its reset value, 0) -- plain Bind against a
    # never-populated Object_ID now genuinely hard-traps on its own
    # (cause 0x05), which would jump to address 0 here, undefined for
    # this test. This test's own real subject is ODT-Populate's
    # privilege gate, not Bind's own trap delivery -- Bind-NoTrap
    # (the correct "soft-fail" instruction since Milestone 8) is used
    # instead, preserving the test's original intent exactly.
    .insn i 0x0b, 0x5, x0, x1, 1  # veda.bind.notrap c0, x1   -- expect c0.Tag=0 (Object_ID=5's ODT entry was never populated)
    .insn r 0x5b, 0x0, 0x03, x6, x0, x0  # cgettag x6, c0     -- expect x6 == 0
1:
    j 1b
