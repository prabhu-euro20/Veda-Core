.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core formal model: PCC compartment bounding negative test --
    # Milestone 14 (PCC_COMPARTMENT_DESIGN.md). Proves the real fetch-time
    # enforcement: an OCInvoke-entered compartment with Length=0x04 (one
    # instruction only) genuinely hard-traps the moment execution tries
    # to fetch the very next instruction -- cause=0x01 (Bounds/Length
    # Violation, reused, not a new code), cap_idx=16 (the PCC sentinel,
    # matching real CHERI's own PCC_IDX=0x10 exactly). Also proves the
    # full real cycle: veda_trap()'s own save-and-reset makes
    # veda_mepcc_base/_length (CSRs 0x7c2/0x7c3) hold the narrow bounds
    # that were active at fault time, and the trap handler's own explicit
    # restore (a real write to veda_pcc_base/_length, CSRs 0x7c0/0x7c1 --
    # this project's own established "software, not hardware, restores
    # across mret" convention, matching mepc's own explicit advancement
    # since Milestone 9) correctly re-widens execution back to unbounded
    # before resuming at a real, deliberately-chosen recovery point
    # OUTSIDE the abandoned compartment -- not an attempt to resume
    # inside it, a real, distinct design choice from an ordinary
    # skippable "use"-family violation (ordinary violations advance mepc
    # past one bad instruction; a compartment escape abandons the whole
    # compartment instead, the same real distinction real CHERI's own
    # PCC-bounds-violation handling makes).
    la   t0, trap_handler
    csrw mtvec, t0

    # -- Object_ID=60 (CODE): Permit_Execute|Permit_Invoke=0x0402,
    #    Base=compartment_start, Length=0x0004 -- deliberately just ONE
    #    instruction's worth. --
    la   t0, compartment_start
    slli t0, t0, 32
    li   t1, 0x00040402
    or   t0, t0, t1
    li   x1, 60
    mv   x2, t0
    .word 0x0620828b              # veda.odt.populate x5, x1, x2

    # -- Object_ID=61 (DATA): Permit_Invoke only=0x0400. --
    li   x1, 61
    li   x2, 0x8001070000400400
    .word 0x0620828b              # veda.odt.populate x5, x1, x2

    # -- Object_ID=62: type authority, Permit_Seal|Permit_Unseal=0x0300. --
    li   x1, 62
    li   x2, 0x8001080000400300
    .word 0x0620828b              # veda.odt.populate x5, x1, x2

    li   x1, 60
    .word 0x0000d00b              # veda.bind c0, x1  -- CODE
    li   x1, 61
    .word 0x0000d08b              # veda.bind c1, x1  -- DATA
    li   x1, 62
    .word 0x0000d10b              # veda.bind c2, x1  -- type authority

    .word 0x202011db              # cseal c3, c0, c2
    .word 0x2020925b              # cseal c4, c1, c2

    .word 0x2441905b              # ocinvoke c3, c4   -- narrows PCC to [compartment_start, compartment_start+4)

compartment_start:
    addi x0, x0, 0                # the ONLY instruction inside the compartment -- fetch is genuinely in-bounds here
fault_pc:
    addi x0, x0, 0                # this fetch is OUTSIDE the compartment (compartment_start+4) -- must hard-trap

    li   x22, 0xBAD                # must NOT be reached directly (only via the handler's own explicit recovery jump)
    j    done

trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0x201                 # (cap_idx=16<<5)|cause=0x01 = 0x200|0x01 = 0x201
    bne  t3, t4, fail

    csrr t3, mepc
    la   t4, fault_pc
    bne  t3, t4, fail

    # -- the real save-and-reset already fired (veda_trap() itself, before
    #    this handler even started) -- confirm veda_mepcc_* holds the
    #    narrow bounds that were live at fault time. --
    csrr t3, 0x7c2                 # veda_mepcc_base -- expect compartment_start's own address
    la   t4, compartment_start
    bne  t3, t4, fail
    csrr t3, 0x7c3                 # veda_mepcc_length -- expect 0x0004
    li   t4, 0x0004
    bne  t3, t4, fail

    li   x21, 0x600D               # sentinel: reached the handler with correct mcause/mtval/mepc/mepcc

    # -- explicit recovery: abandon the compartment, restore unbounded,
    #    resume at a real, safe address outside it (not mepc+4, which is
    #    still just as far outside the compartment as the fault itself
    #    was). --
    li   t3, 0xFFFF
    csrw 0x7c1, t3                 # veda_pcc_length := VEDA_PCC_UNBOUNDED
    csrw 0x7c0, x0                 # veda_pcc_base := 0 (irrelevant once length is unbounded)
    la   t3, recovery
    csrw mepc, t3
    mret

recovery:
    csrr x23, 0x7c1                # pcc_length AFTER the explicit restore -- expect 0xFFFF (proves the CSR write really landed)
    li   x22, 0x900D               # sentinel: correctly resumed at the real recovery point, not inside the compartment
    j    done

fail:
    li   x22, 0xDEAD

done:
    li   t2, 0x600D
    bne  x21, t2, real_fail
    li   t2, 0x900D
    bne  x22, t2, real_fail
    li   t2, 0xFFFF
    bne  x23, t2, real_fail

    RVMODEL_HALT_PASS
real_fail:
    RVMODEL_HALT_FAIL
