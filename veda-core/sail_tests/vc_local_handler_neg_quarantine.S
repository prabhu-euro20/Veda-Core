.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # LOCAL_FAULT_RECOVERY_DESIGN.md: the real composition guarantee with
    # VEDA_TRAP_QUARANTINE -- a local handler that itself keeps faulting
    # must NOT be able to redirect forever (which would itself become a
    # new repeated-trap DoS vector, defeating the mechanism this same
    # project built earlier this session). handler_entry here
    # unconditionally faults again every time it runs. Empirically
    # confirmed exact mechanics (not assumed): veda_pcc_save_and_reset()
    # increments the trap-tracker count FIRST, then checks quarantine --
    # so the SAME trap that brings the count to the threshold (3) is
    # itself refused a redirect. This means exactly 2 successful
    # redirects into handler_entry happen (count 0->1, then 1->2, both
    # checked as "not yet quarantined"), and the 3rd real fault
    # (count 2->3, checked as "quarantined") falls straight through to
    # the ordinary global mtvec path -- not 3 redirects then a 4th
    # fallback, which was this design's own original, less precise
    # expectation before this test was built and traced.
    la   t0, trap_handler
    csrw mtvec, t0

    li   x24, 0                    # counts how many times handler_entry's own body ran
    li   x22, 0                    # fail-reason code

    # -- Object_ID=620 (CODE): Base=comp_entry, Length=0x60. --
    la   t0, comp_entry
    slli t0, t0, 32
    li   t1, 0x00600402
    or   t0, t0, t1
    li   x1, 620
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- Object_ID=621 (DATA): Permit_Invoke only. --
    li   x1, 621
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- Object_ID=622 (TYPE authority). --
    li   x1, 622
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    li   x1, 620
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x1, 621
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1
    li   x1, 622
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4
    j    fail_unexpected_no_entry

comp_entry:
    la   t3, handler_entry
    la   t4, comp_entry
    sub  x5, t3, t4
    .insn r 0x5b, 0x1, 0x0a, x10, x0, x5  # oca c10, c0, x5 -- c10 -> handler_entry
    .insn r 0x5b, 0x1, 0x17, x0, x10, x0  # osethandler c10

    la   t3, escape1
    jr   t3                                # fault #1 -- count 0->1, redirects
    j    fail_unexpected_no_entry

.balign 4
handler_entry:
    # -- unconditionally faults again, every single time it runs. --
    addi x24, x24, 1
    la   t3, escape2
    jr   t3
    j    fail_unexpected_no_entry

.balign 4
trap_handler:
    # -- reached ONLY once the compartment's otype is quarantined (the
    #    3rd real fault). Confirm exactly 2 successful redirects happened
    #    before this, confirm this is the ordinary global fallback (cause
    #    still the plain bounds violation, PCC now genuinely unbounded --
    #    not another redirect). --
    csrr t4, 0x343
    andi t5, t4, 0x1f
    li   t6, 0x01
    bne  t5, t6, fail_cause_mismatch
    srli t5, t4, 5
    li   t6, 16
    bne  t5, t6, fail_cause_mismatch
    li   t6, 2
    bne  x24, t6, fail_wrong_redirect_count
    csrr t4, 0x7c1                        # veda_pcc_length
    li   t6, 0xFFFFF
    bne  t4, t6, fail_not_unbounded
    RVMODEL_HALT_PASS

fail_cause_mismatch:
    li   x22, 0xDEAD
    j    real_fail
fail_wrong_redirect_count:
    li   x22, 0xBAD3
    j    real_fail
fail_not_unbounded:
    li   x22, 0xBAD4
    j    real_fail
fail_unexpected_no_entry:
    li   x22, 0xBAD1
    j    real_fail

.balign 4
escape1:
    nop
    j    fail_unexpected_no_entry
.balign 4
escape2:
    nop
    j    fail_unexpected_no_entry

real_fail:
    RVMODEL_HALT_FAIL
