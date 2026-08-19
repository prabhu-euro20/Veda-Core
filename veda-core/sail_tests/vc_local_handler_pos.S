.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # LOCAL_FAULT_RECOVERY_DESIGN.md: the core positive property --
    # register a compartment-local fault handler (VEDA_SET_LOCAL_HANDLER),
    # drive a real fault, and confirm the hardware redirects DIRECTLY into
    # the registered handler with PCC narrowed to the SAME bounds the
    # faulting compartment already had (not unbounded, not mtvec), never
    # touching this test's own mtvec-pointed trap_handler at all -- the
    # redirect is a genuine alternative to the ordinary global-fallback
    # path, not merely inferred from a passing exit code. `handler_entry`
    # is reached ONLY via that redirect: nothing in this program's own
    # sequential flow ever falls into it (a deliberate out-of-bounds jump
    # is what triggers the real fault).
    la   t0, trap_handler
    csrw mtvec, t0

    li   x21, 0                    # 1 once handler_entry genuinely ran
    li   x22, 0                    # fail-reason code, 0 = no failure recorded yet
    li   x23, 0                    # 1 once base/length readback confirmed correct

    # -- Object_ID=600 (CODE): Base=comp_entry, Length=0x60, Permit_Execute
    #    |Permit_Invoke=0x0402. --
    la   t0, comp_entry
    slli t0, t0, 32
    li   t1, 0x00600402
    or   t0, t0, t1
    li   x1, 600
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    # -- Object_ID=601 (DATA): Permit_Invoke only. --
    li   x1, 601
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- Object_ID=602 (TYPE authority): Permit_Seal|Permit_Unseal. --
    li   x1, 602
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    li   x1, 600
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- CODE
    li   x1, 601
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- DATA
    li   x1, 602
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- TYPE authority

    # -- sentry SOURCE (Object_ID=610): Base=return_landing,
    #    Length=UNBOUNDED, Perms=Execute only -- minted BEFORE entry,
    #    matching vc_ocreturn_basic.S's own established "prepared before
    #    entry" pattern. Capability registers survive OCInvoke (only PCC
    #    narrows). --
    la   t0, return_landing
    mv   x18, t0                    # save expected Base for the post-return check
    li   t1, 0xFFFFF0002
    csrw 0x7c4, t1
    li   x1, 610
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2  # veda.odt.populate.fast x5, x1, x2

    li   x1, 610
    .insn i 0x0b, 0x5, x8, x1, 0          # veda.bind c8, x1
    .insn r 0x5b, 0x1, 0x15, x9, x8, x0   # csealentry c9, c8  -- MINT sentry

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2 -- sealed CODE
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2 -- sealed DATA
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4  -- narrows PCC to comp_entry
    j    fail_unexpected_no_entry         # must NOT be reached

comp_entry:
    # -- register handler_entry (within OUR OWN current bounds) as our
    #    own local fault-recovery entry point. Derive the handler-pointer
    #    into a fresh register, c10, via OCA from c0 (our own CODE
    #    capability -- still bound, capability registers survive
    #    OCInvoke, still carries Permit_Execute=0x0402) -- c9 (the minted
    #    sentry) is left untouched for the eventual OCRETURN. --
    la   t3, handler_entry
    la   t4, comp_entry
    sub  x5, t3, t4
    .insn r 0x5b, 0x1, 0x0a, x10, x0, x5  # oca c10, c0, x5  -- c10 -> handler_entry
    .insn r 0x5b, 0x1, 0x17, x0, x10, x0  # osethandler c10

    # -- deliberate fault: jump to an address far outside [comp_entry,
    #    comp_entry+0x60) -- the fetch of THIS instruction is the real
    #    PCC bounds violation that must trigger the redirect. --
    la   t3, unreachable_marker
    jr   t3
    j    fail_unexpected_no_entry         # unreachable guard

.balign 4
handler_entry:
    # -- reached ONLY via the hardware redirect. Confirm PCC was narrowed
    #    to the SAME bounds the compartment already had (not unbounded,
    #    not anything else) before doing anything else. --
    csrr t4, 0x7c0                        # veda_pcc_base
    la   t5, comp_entry
    bne  t4, t5, fail_bounds_mismatch
    csrr t4, 0x7c1                        # veda_pcc_length
    li   t5, 0x60
    bne  t4, t5, fail_bounds_mismatch
    li   x23, 1
    li   x21, 0x600D
    .insn r 0x5b, 0x1, 0x16, x0, x9, x0   # ocreturn c9 -- clean exit via the sentry
    j    fail_unexpected_no_entry          # must NOT be reached

fail_bounds_mismatch:
    li   x22, 0xBAD2
    j    real_fail
fail_unexpected_no_entry:
    li   x22, 0xBAD1
    j    real_fail

.balign 4
unreachable_marker:
    nop                                    # never legitimately fetched
    j    fail_unexpected_no_entry

.balign 4
trap_handler:
    # -- must NEVER be reached in this test's own expected path (the
    #    redirect replaces mtvec entirely for this fault). Reaching here
    #    at all is itself a real failure. --
    li   x22, 0xDEAD
    j    real_fail

return_landing:
    # -- load-bearing assertion: OCRETURN genuinely crossed back out of
    #    the compartment after the handler ran. --
    csrr t3, 0x7c1                        # veda_pcc_length
    li   t4, 0xFFFFF
    bne  t3, t4, fail_bounds_mismatch
    csrr t3, 0x7c0                        # veda_pcc_base
    bne  t3, x18, fail_bounds_mismatch

    li   t2, 0x600D
    bne  x21, t2, real_fail
    li   t2, 1
    bne  x23, t2, real_fail
    li   t2, 0
    bne  x22, t2, real_fail
    RVMODEL_HALT_PASS
real_fail:
    RVMODEL_HALT_FAIL
