.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Length/Offset widening RTL mirror: CSetBounds's own full-width
    # window check ($veda_csetbounds_window_ok in veda_core.tlv). This
    # RTL-only real finding (pre-existing since RTL Milestone 3, not
    # introduced by the 2026-08-19 widening, but audited and fixed
    # while re-deriving that line for the widening) has no dedicated
    # Sail-side test to mirror -- Sail's own window_ok always compared
    # the FULL, untruncated rs2 value, so this bug never existed
    # there. This is a standalone RTL regression test proving the fix
    # directly: an rs2 value whose low 20 bits alias a small,
    # comfortably-in-window value against a modest Length (0x0200),
    # but whose full 64-bit value is obviously enormous, must
    # soft-fail (Tag cleared) under the FIXED logic (which compares
    # cs1.Offset against the full 64-bit rs2_data), and would wrongly
    # succeed (Tag=1) under the mutated/pre-fix logic (which compared
    # against the already-truncated 20-bit new_length instead).
    #
    # Object_ID=505 (fresh block).
    # ─────────────────────────────────────────────────────────────
    li   x1, 505
    li   x2, 0x800100000200000C   # Base=0x80010000, Length=0x0200, Perms=0x000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2

    li   x1, 505
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1

    # rs2 = 0x0010000000000100: low 20 bits = 0x00100 (256, comfortably
    # in-window against Length=0x0200/512), but the full 64-bit value
    # is enormous -- far outside c0's own [0, 0x0200) window.
    li   x2, 0x10000000000100
    .insn r 0x5b, 0x1, 0x08, x3, x0, x2   # csetbounds c3, c0, x2

    .insn r 0x5b, 0x0, 0x03, x10, x3, x0  # cgettag x10, c3  -- expect 0 (soft-fail under the FIXED width check)

    # ─────────────────────────────────────────────────────────────
    # Adversarial-review Finding #5: the soft-fail path above was the
    # only path this file exercised -- CSetBounds's own SUCCESS path
    # at a genuinely widened new_length (bits[19:16] nonzero) was
    # untested. This second, independent object proves CSetBounds can
    # successfully narrow a capability to a new_length whose upper 4
    # bits are set, and that the widened value threads all the way
    # through to CGetLen's own readback.
    #
    # Object_ID=510 (fresh block).
    # ─────────────────────────────────────────────────────────────
    li   t1, 0x50000000C   # veda_attr: Length=0x50000 (20-bit), Perms=0x000C
    csrw 0x7c4, t1
    li   x1, 510
    li   x2, 0x80020000
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2   # veda.odt.populate.fast x5, x1, x2

    li   x1, 510
    .insn i 0x0b, 0x5, x4, x1, 0   # veda.bind c4, x1

    # Narrow c4 to new_length=0x30000 (bits[19:16]=0x3, genuinely
    # widened), comfortably <= c4's own current Length (0x50000).
    li   x2, 0x30000
    .insn r 0x5b, 0x1, 0x08, x5, x4, x2   # csetbounds c5, c4, x2

    .insn r 0x5b, 0x0, 0x03, x11, x5, x0  # cgettag x11, c5  -- expect 1 (success)
    .insn r 0x5b, 0x0, 0x01, x12, x5, x0  # cgetlen x12, c5  -- expect 0x30000 (widened new_length threads through)

1:
    j 1b
