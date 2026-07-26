.section .text
.global _start
_start:
    # Veda-Core RTL Milestone 11 negative test: `veda.droppriv` first
    # (ordinary privilege gone), then attempt ODT-Populate with the ODA
    # left at its real reset value (Tag=0, never delegated) -- the write
    # must be suppressed exactly like Milestone 4's own negative test,
    # now via the OR'd authorization check
    # (!$priv && !$veda_oda_authorized) rather than !$priv alone.
    .word 0x0000007b          # veda.droppriv  -- $priv: 1 -> 0, one-way

    li   x1, 6                # Object_ID = 6 (never seeded at reset)
    li   x2, 0x800103000040100C
    .word 0x0620828b        # veda.odt.populate x5, x1, x2  -- must be suppressed (!$priv && !oda_authorized)

    .word 0x0000d00b         # veda.bind c0, x1
    .word 0x0600035b          # cgettag x6, c0     -- expect 0 (Object_ID=6's ODT entry was never populated)
1:
    j 1b
