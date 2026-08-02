.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core Milestone 19 (Veda-Purecap Enforcement) -- the literal
    # reproduction of the real vulnerability this milestone closes:
    # VEDA_CGETBASE legitimately extracts a capability's raw Base address
    # into an ordinary GPR (a real, spec-required query instruction), and
    # prior to this milestone nothing stopped that GPR value from then
    # being used as an ordinary LOAD base with zero capability check --
    # the same property real CHERI's own "hybrid mode" has. Bind
    # Object_ID=1 (pre-seeded by ext_reset -- Perms=0x100C, Load+Store+
    # NMC_Compute, Base=0x80010000, Length=0x40), extract its raw Base via
    # CGetBase, set veda_purecap (CSR 0x7c5 bit 0), then attempt an
    # ordinary `ld` through that raw address -- must now genuinely
    # hard-trap.
    la   t0, trap_handler
    csrw mtvec, t0

    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0         # veda.bind c0, x1  -- Object_ID=1

    .insn r 0x5b, 0x0, 0x00, x5, x0, x0  # cgetbase x5, c0  -- x5 = raw Base (0x80010000)

    li   x6, 1
    csrw 0x7c5, x6                       # veda_mode.veda_purecap := 1

    ld   x7, 0(x5)                       # ordinary LOAD through the raw address -- must trap
    RVMODEL_HALT_FAIL    # falling through here means the expected trap never fired

.balign 4
trap_handler:
    # Real, honest consequence of this milestone's own enforcement,
    # discovered via actual testing (a trap loop), not assumed: while
    # veda_purecap is still set, RVMODEL_HALT_PASS/FAIL's own ordinary
    # `sw` to the tohost MMIO region would itself be blocked by the very
    # same hook this test is proving -- clear it first, architecturally
    # correct (the test harness's own signaling channel is not the thing
    # under test here), not a workaround around the enforcement itself.
    li   t5, 0
    csrw 0x7c5, t5

    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, check_fail
    csrr t3, mtval
    li   t4, 0x227        # (cap_idx=17<<5)|cause=0x07 = 0x220|0x07 = 0x227
    bne  t3, t4, check_fail
    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL
