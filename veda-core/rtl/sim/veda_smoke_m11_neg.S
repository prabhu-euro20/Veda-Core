.section .text
.global _start
_start:
    # Veda-Core RTL Milestone 11 negative test: `veda.droppriv` first
    # (ordinary privilege gone), then attempt ODT-Populate with the ODA
    # left at its real reset value (Tag=0, never delegated) -- the write
    # must be suppressed exactly like Milestone 4's own negative test,
    # now via the OR'd authorization check
    # (!$priv && !$veda_oda_authorized) rather than !$priv alone.
    .insn r 0x7b, 0x0, 0x00, x0, x0, x0  # veda.droppriv  -- $priv: 1 -> 0, one-way

    li   x1, 6                # Object_ID = 6 (never seeded at reset)
    li   x2, 0x800103000040100C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- must be suppressed (!$priv && !oda_authorized)

    # Milestone 13 update: this file installs no trap handler at all
    # (mtvec stays at its reset value, 0) -- plain Bind against a
    # never-populated Object_ID now genuinely hard-traps on its own
    # (cause 0x05), which would jump to address 0 here, undefined for
    # this test. This test's own real subject is ODT-Populate's OR'd
    # privilege/ODA gate, not Bind's own trap delivery -- Bind-NoTrap
    # (the correct "soft-fail" instruction since Milestone 8) is used
    # instead, preserving the test's original intent exactly.
    .insn i 0x0b, 0x5, x0, x1, 1  # veda.bind.notrap c0, x1
    .insn r 0x5b, 0x0, 0x03, x6, x0, x0  # cgettag x6, c0     -- expect 0 (Object_ID=6's ODT entry was never populated)
1:
    j 1b
