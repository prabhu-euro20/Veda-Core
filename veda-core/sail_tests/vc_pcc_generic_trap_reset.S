.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core Milestone 21 -- the permanent regression test for a real,
    # empirically-confirmed bug found while auditing Milestone 20's own
    # fix: before this milestone, an *ordinary*, non-Veda exception
    # (ecall, illegal instruction, misaligned access) taken from inside a
    # live OCInvoke compartment never reset veda_pcc_base/_length --
    # meaning a completely realistic system-service handler placed
    # OUTSIDE the compartment (the normal, expected place for one) could
    # never even be fetched (postlude/fetch.sail's own ext_fetch_check_pc
    # applies to every fetch, including a trap handler's own first
    # instruction), causing a genuine infinite fault loop -- confirmed via
    # a real PoC run with `--inst-limit 200` that never completed, before
    # this fix existed.
    la   t0, real_handler          # a REALISTIC handler, deliberately outside the compartment
    csrw mtvec, t0

    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x00400402
    or   t0, t0, t1
    li   x1, 60
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate CODE

    li   x1, 61
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate DATA

    li   x1, 62
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate type authority

    li   x1, 60
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x1, 61
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1
    li   x1, 62
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4  -- narrows PCC to [landing_pad, landing_pad+0x40)

landing_pad:
    ecall                          # an ordinary, non-malicious syscall-style request from inside the compartment
    # -- reached only if real_handler ran and correctly returned here --
    li   x22, 0x900D
    j    done

.balign 4
real_handler:
    # -- a real, ordinary handler an OS/runtime would install, living
    #    outside the compartment as any real system-service handler
    #    realistically would. Its own successful execution here (this
    #    code is only fetchable at all if veda_pcc_length was already
    #    reset to unbounded before this fetch) is itself the primary
    #    proof; the explicit CSR check below is the load-bearing
    #    assertion of *why* it succeeded, not just *that* it did. --
    csrr t3, mcause
    li   t4, 11                    # E_M_EnvCall (ecall from M-mode)
    bne  t3, t4, fail

    csrr t3, 0x7c1                 # veda_pcc_length -- expect VEDA_PCC_UNBOUNDED
    li   t4, 0xFFFF
    bne  t3, t4, fail

    li   x21, 0x600D

    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret

done:
    li   t2, 0x600D
    bne  x21, t2, fail
    li   t2, 0x900D
    bne  x22, t2, fail

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
