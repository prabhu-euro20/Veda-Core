.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Minimal OS kernel Milestone B (MINIMAL_OS_KERNEL_DESIGN.md): CSealEntry
    # -- term-for-term adaptation of real CHERI's own CSealEntry (CHERI ISA
    # spec p.215): cd = cs1 sealed with the fixed VEDA_OTYPE_SENTRY constant
    # (0xFFFE), no authorizing capability operand at all, unlike CSeal above
    # (real CHERI's own text, p.101: "an ambient monotonic action, requiring
    # no additional permission than to have a capability bearing
    # Permit_Execute"). Proves: (a) the mint genuinely succeeds (Tag=1) from
    # an ordinary, unsealed, executable capability; (b) the resulting otype
    # reads back as exactly 0xFFFE, not merely "some sealed value".
    #
    # Object_ID=80: an arbitrary executable capability, Perms=Execute
    # (bit1)=0x0002.
    li   x1, 80
    li   x2, 0x8005000000400002
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 80
    .insn i 0x0b, 0x5, x5, x1, 0  # veda.bind c5, x1  -- unsealed source

    .insn r 0x5b, 0x1, 0x15, x6, x5, x0  # csealentry c6, c5  -- MINT sentry

    .insn r 0x5b, 0x0, 0x03, x10, x6, x0  # cgettag  x10, c6  -- expect 1
    .insn r 0x5b, 0x0, 0x04, x11, x6, x0  # cgettype x11, c6  -- expect 0xFFFE

    li   t2, 1
    bne  x10, t2, fail
    li   t2, 0xFFFE
    bne  x11, t2, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
