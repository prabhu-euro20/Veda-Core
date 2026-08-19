.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # RTL mirror of sail_tests/vc_local_handler_neg_bounds_guard.S
    # (LOCAL_FAULT_RECOVERY_DESIGN.md / LOCAL_FAULT_RECOVERY_RESULTS.md):
    # confused-deputy negative test. Attempts to register a genuinely,
    # independently valid (freshly-tagged, Permit_Execute) capability
    # (c10, Object_ID=603) whose Base lies FAR outside the compartment's
    # own current bounds -- bound DIRECTLY at that out-of-bounds address
    # (NOT derived via OCA from the compartment's own in-bounds CODE
    # capability), per the ALREADY-KNOWN test-design pitfall the Sail
    # side found: an OCA-derived pointer with an out-of-range offset
    # trips OCA's own, unrelated, pre-existing out-of-range tag-clearing
    # protection FIRST, producing VEDA_CAUSE_TAG_VIOLATION (0x02) instead
    # of the intended VEDA_CAUSE_BOUNDS_VIOLATION (0x01) -- this design
    # isolates the test to exercise ONLY VEDA_SET_LOCAL_HANDLER's own new
    # confused-deputy check.
    #
    # Two phases, tracked by x24 (0=phase1, 1=phase2), exactly mirroring
    # the Sail side's own second test-design correction (a first attempt
    # that unconditionally retried osethandler on re-entry hit the
    # identical confused-deputy trap twice instead of proving the
    # rejection left nothing behind):
    #   Phase 1: attempt `osethandler c10` -- must hard-trap
    #     (VEDA_CAUSE_BOUNDS_VIOLATION=0x01, cap_idx=10 -- the register c10
    #     itself, the rs1 operand the trap reports by this file's own
    #     established default-fallback convention).
    #   Phase 2 (never touching osethandler again): an ORDINARY
    #     out-of-bounds fetch from the SAME re-invoked compartment must
    #     fall straight through to the plain global fallback
    #     (cause=0x01, cap_idx=16 -- the PCC sentinel), proving the
    #     rejected phase-1 attempt genuinely left nothing behind in
    #     local_handler_table (if it HAD written an entry, this second
    #     fault -- against the SAME otype -- would instead have been
    #     redirected).
    #
    # Object_IDs 600 (CODE)/601 (DATA)/602 (TYPE authority)/603 (the
    # separate, freshly-tagged, out-of-bounds target capability) --
    # grep-audited fresh (590-599 used by this session's own three
    # preceding local-handler tests; 600+ is a clean, unused block).
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    li   x24, 0                    # phase flag: 0=phase1 (attempt rejected registration), 1=phase2
    li   x20, 0                    # sentinel: 1 once phase-1's own rejection (cause=0x01/cap_idx=10) confirmed
    li   x23, 0                    # sentinel: 1 once phase-2's own ordinary fallback (cause=0x01/cap_idx=16) confirmed
    li   x21, 0                    # final success sentinel
    li   x22, 0                    # fail-reason code, 0 = no failure recorded yet

    # -- Object_ID=600 (CODE): Base=compartment_start, Length=0x0018,
    #    Permit_Execute|Permit_Invoke=0x0402. --
    la   t0, compartment_start
    slli t0, t0, 32
    li   t1, 0x00180402
    or   t0, t0, t1
    li   x1, 600
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- CODE

    # -- Object_ID=601 (DATA): Permit_Invoke only. --
    li   x1, 601
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- DATA

    # -- Object_ID=602: type authority, Permit_Seal|Permit_Unseal. --
    li   x1, 602
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- TYPE

    # -- Object_ID=603: a SEPARATE, independently valid capability whose
    #    Base is the `done` label's own address -- objdump-confirmed
    #    genuinely far outside [compartment_start, compartment_start+0x18)
    #    (trap_handler itself turned out NOT reliably far enough here --
    #    a real bug this file's own testing caught: this specific
    #    compartment/trap_handler layout placed trap_handler only 16
    #    bytes past compartment_start, still inside a 24-byte bound,
    #    silently making the confused-deputy check trivially pass instead
    #    of exercising the rejection this test exists to prove; `done` is
    #    hundreds of bytes further out, immune to this class of layout
    #    accident), Length=0x0004, Permit_Execute only=0x0002. Bound
    #    directly -- never derived via OCA -- exactly the pitfall-avoiding
    #    design above. --
    la   t0, done
    slli t0, t0, 32
    li   t1, 0x00040002
    or   t0, t0, t1
    li   x1, 603
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- out-of-bounds target

    li   x1, 600
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- CODE
    li   x1, 601
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- DATA
    li   x1, 602
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- type authority
    li   x1, 603
    .insn i 0x0b, 0x5, x10, x1, 0 # veda.bind c10, x1 -- the out-of-bounds target, bound DIRECTLY

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2  -- sealed CODE
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2  -- sealed DATA

reinvoke:
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4  -- narrows PCC to [compartment_start, +0x18)
poison_entry:
    j poison_entry                        # must NOT be reached

.balign 4
compartment_start:
    # c0/c10 (both unsealed, bound before OCInvoke) survive OCInvoke
    # untouched -- capability registers are not cleared, only PCC
    # narrows (the same real property this session's positive test
    # already relies on for c0).
    beqz x24, phase1
    jal  x0, done                          # phase 2: ordinary, unambiguous OOB fetch -- confirms the plain
                                            # global fallback, proving nothing was registered by phase 1

phase1:
    .insn r 0x5b, 0x1, 0x17, x0, x10, x0  # osethandler c10 -- MUST be rejected: c10's own Base+Offset
                                           # (trap_handler's address) lies outside the compartment's own
                                           # current [pcc_base, pcc_base+pcc_length)

poison_mid:
    j poison_mid                          # dead code

.balign 4
trap_handler:
    csrr t4, 0x343                        # mtval
    andi t5, t4, 0x1f                     # cause
    li   t6, 0x01                         # VEDA_CAUSE_BOUNDS_VIOLATION -- expected in BOTH phases
    bne  t5, t6, done
    srli t5, t4, 5                        # cap_idx

    bnez x24, check_phase2

    # -- phase 1: expect cap_idx == 10 (c10, the rejected registration's own rs1 operand). --
    li   t6, 10
    bne  t5, t6, done
    li   x20, 1
    li   x24, 1                           # advance to phase 2
    j    reinvoke

check_phase2:
    # -- phase 2: expect cap_idx == 16 (the PCC sentinel -- the ordinary
    #    global fallback, proving local_handler_table genuinely has
    #    nothing registered for this otype). --
    li   t6, 16
    bne  t5, t6, done
    li   x23, 1
    li   x21, 0x600D                      # success sentinel
    j    done

done:
1:
    j 1b
