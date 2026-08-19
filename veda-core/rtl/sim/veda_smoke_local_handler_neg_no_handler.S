.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # RTL mirror of sail_tests/vc_local_handler_neg_no_handler.S
    # (LOCAL_FAULT_RECOVERY_DESIGN.md / LOCAL_FAULT_RECOVERY_RESULTS.md):
    # a compartment that NEVER calls osethandler at all. A real
    # out-of-bounds fetch must fall straight through to the completely
    # unchanged, pre-existing global fallback (mtvec's own trap_handler,
    # cause=0x01/cap_idx=16 -- the PCC-violation special case, and PCC
    # reset to base=0/length=UNBOUNDED, exactly as before this session's
    # new mechanism ever existed) -- zero regression from adding
    # VEDA_LOCAL_HANDLER.
    #
    # Object_IDs 594 (CODE)/595 (DATA)/596 (TYPE authority) -- grep-
    # audited fresh (590-593 used by veda_smoke_local_handler_pos.S,
    # this session's own immediately-preceding test; 594+ is a clean,
    # unused block).
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    li   x20, 0                    # sentinel: 1 once trap_handler is genuinely reached (the expected path)
    li   x23, 0                    # sentinel: 1 once veda_pcc_base readback confirms reset to 0
    li   x24, 0                    # sentinel: 1 once veda_pcc_length readback confirms reset to UNBOUNDED
    li   x21, 0                    # final success sentinel
    li   x22, 0                    # fail-reason code, 0 = no failure recorded yet

    # -- Object_ID=594 (CODE): Base=compartment_start, Length=0x0004
    #    (one instruction -- the plain, minimal OOB trigger this file's
    #    own trap_quarantine tests already established), Permit_Execute|
    #    Permit_Invoke=0x0402. --
    la   t0, compartment_start
    slli t0, t0, 32
    li   t1, 0x00040402
    or   t0, t0, t1
    li   x1, 594
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- CODE

    # -- Object_ID=595 (DATA): Permit_Invoke only. --
    li   x1, 595
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- DATA

    # -- Object_ID=596: type authority, Permit_Seal|Permit_Unseal. --
    li   x1, 596
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- TYPE

    li   x1, 594
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1 -- CODE
    li   x1, 595
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1 -- DATA
    li   x1, 596
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1 -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2  -- sealed CODE
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2  -- sealed DATA

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4  -- narrows PCC to [compartment_start, +0x4)
poison_entry:
    j poison_entry                        # must NOT be reached

.balign 4
compartment_start:
    nop                              # the ONE instruction Length=0x0004 permits -- no osethandler call at all
    j fail_unexpected_no_trap        # must NOT be reached -- this address is already out of bounds

fail_unexpected_no_trap:
    li   x22, 0xBAD1
    j    done

.balign 4
trap_handler:
    li   x20, 1                     # reached the ordinary global fallback, as expected
    csrr t4, 0x343                  # mtval -- decode cap_idx/cause per this file's own established convention
    andi t5, t4, 0x1f                # cause (low 5 bits)
    li   t6, 0x01                    # VEDA_CAUSE_BOUNDS_VIOLATION -- the ordinary PCC-violation cause
    bne  t5, t6, cause_mismatch
    srli t5, t4, 5
    li   t6, 16                      # cap_idx=16 -- the PCC sentinel, exactly as $veda_trap_taken's own
                                      # special-cased mtval construction already established
    bne  t5, t6, capidx_mismatch

    csrr t1, 0x7c0                  # veda_pcc_base -- must be reset to 0 (completely unchanged fallback)
    bne  t1, x0, base_mismatch
    li   x23, 1
    li   t2, 0xFFFFF
    csrr t3, 0x7c1                  # veda_pcc_length -- must be reset to VEDA_PCC_UNBOUNDED
    bne  t2, t3, length_mismatch
    li   x24, 1

    li   x21, 0x600D                 # success sentinel
    j    done

cause_mismatch:
    li   x22, 0xBAD5
    j    done
capidx_mismatch:
    li   x22, 0xBAD6
    j    done
base_mismatch:
    li   x22, 0xBAD3
    j    done
length_mismatch:
    li   x22, 0xBAD4
    j    done

done:
1:
    j 1b
