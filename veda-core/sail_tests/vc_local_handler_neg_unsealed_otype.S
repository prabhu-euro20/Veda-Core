.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Real bug found by adversarial review of the RTL mirror of
    # LOCAL_FAULT_RECOVERY_DESIGN.md (not caught by this milestone's own
    # original 4-test suite -- all four mint fresh, distinct real otypes
    # via CSeal/OCInvoke and never exercise this state): VEDA_SET_LOCAL_
    # HANDLER's original "live compartment" check only tested PCC
    # boundedness (veda_pcc_length != VEDA_PCC_UNBOUNDED), never otype
    # identity. But a compartment can have genuinely bounded PCC while
    # veda_pcc_otype STILL holds the shared UNSEALED_OTYPE (0xFFFF)
    # sentinel -- this is the ORDINARY state immediately after any
    # OCRETURN (which always sets otype=UNSEALED_OTYPE, since a return
    # target has no per-destination identity -- see VEDA_OCRETURN's own
    # comment) or after any trap+mret round trip that never goes through
    # OCInvoke again (mret has no otype-restore arm, by design). Before
    # the fix, osethandler succeeded in this window and registered a
    # handler-table entry keyed under the SHARED 0xFFFF slot -- any other
    # unrelated compartment resumed into that same ordinary window (e.g.
    # this project's own shipped veda_sched_asm.S scheduler threads,
    # entered exclusively via OCReturn) would collide on that same key on
    # its own next fault and get redirected into a DIFFERENT
    # compartment's chosen handler address. This test reproduces the
    # simplest real instance of that window directly: OCRETURN through a
    # sentry into a BOUNDED region, called from the initial, never
    # -compartmentalized _start context (PCC starts unbounded, otype
    # starts at its own default UNSEALED_OTYPE) -- no OCInvoke anywhere in
    # this file at all. osethandler must now hard-trap
    # (VEDA_CAUSE_NO_LIVE_COMPARTMENT), proving the shared-identity
    # registration window is closed.
    la   t0, trap_handler
    csrw mtvec, t0

    li   x22, 0                    # fail-reason code

    # -- Object_ID=650 (CODE-shaped): Base=target_region, Length=0x40,
    #    Perms=Permit_Execute|Permit_Invoke=0x0402 -- the identical
    #    established descriptor shape vc_ocreturn_basic.S's own comp_entry
    #    object uses. Doubles as both the sentry SOURCE (sealed below) and
    #    the later in-bounds osethandler operand (bound fresh to a second
    #    register, c8, since CSealEntry consumes/reseals c9 in place but
    #    capability registers are otherwise independent). --
    la   t0, target_region
    slli t0, t0, 32
    li   t1, 0x00400402
    or   t0, t0, t1
    li   x1, 650
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 650
    .insn i 0x0b, 0x5, x8, x1, 0   # veda.bind c8, x1  -- kept unsealed, for osethandler's own operand
    .insn i 0x0b, 0x5, x9, x1, 0   # veda.bind c9, x1  -- sealed into a sentry below

    .insn r 0x5b, 0x1, 0x15, x9, x9, x0  # csealentry c9, c9  -- MINT sentry, bounds [target_region, +0x40)

    # -- OCRETURN directly from _start -- no OCInvoke anywhere in this
    #    file. PCC narrows to target_region's own bounds; otype is
    #    explicitly (re)set to UNSEALED_OTYPE by OCRETURN itself. --
    .insn r 0x5b, 0x1, 0x16, x0, x9, x0  # ocreturn c9
    j    fail_unexpected_no_trap          # must NOT be reached

.balign 4
target_region:
    # -- reached ONLY via the OCRETURN above. c8 is still bound (Base=
    #    target_region, Length=0x40, Permit_Execute) and its own target
    #    address (target_region+0) lies genuinely WITHIN the just-narrowed
    #    live bounds -- this is a completely ordinary, in-bounds
    #    osethandler attempt, exercising ONLY the otype-identity gap, not
    #    any bounds/confused-deputy check (that check is already covered
    #    by vc_local_handler_neg_bounds_guard.S). Must hard-trap. --
    .insn r 0x5b, 0x1, 0x17, x0, x8, x0  # osethandler c8 -- must trap, no live otype identity
    j    fail_unexpected_no_trap          # must NOT be reached

.balign 4
trap_handler:
    csrr t4, 0x343                        # mtval
    andi t5, t4, 0x1f
    li   t6, 0x0a                         # VEDA_CAUSE_NO_LIVE_COMPARTMENT
    bne  t5, t6, fail_cause_mismatch
    srli t5, t4, 5
    li   t6, 8                            # c8, the osethandler operand
    bne  t5, t6, fail_cause_mismatch
    csrr t4, 0x7c1                        # veda_pcc_length -- ordinary fallback, genuinely unbounded
    li   t5, 0xFFFFF
    bne  t4, t5, fail_not_unbounded
    csrr t4, 0x7c0                        # veda_pcc_base
    bne  t4, x0, fail_not_unbounded
    RVMODEL_HALT_PASS

fail_cause_mismatch:
    li   x22, 0xDEAD
    j    real_fail
fail_not_unbounded:
    li   x22, 0xBAD4
    j    real_fail
fail_unexpected_no_trap:
    li   x22, 0xBAD1
    j    real_fail

real_fail:
    RVMODEL_HALT_FAIL
