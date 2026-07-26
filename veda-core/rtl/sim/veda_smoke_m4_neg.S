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
    .word 0x0000007b                 # veda.droppriv   -- $priv: 1 -> 0, one-way

    li   x1, 5                       # Object_ID = 5 (never seeded at reset)
    li   x2, 0x800103000040100C      # attempted descriptor -- must never actually land
    .word 0x0620828b                 # veda.odt.populate x5, x1, x2  -- must be suppressed (!$priv)

    .word 0x0000d00b                 # veda.bind c0, x1   -- expect c0.Tag=0 (Object_ID=5's ODT entry was never populated)
    .word 0x0600035b                 # cgettag x6, c0     -- expect x6 == 0
1:
    j 1b
