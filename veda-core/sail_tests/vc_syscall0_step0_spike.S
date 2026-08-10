.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Milestone "Syscall-0" Step 0 (workflow-designed pre-flight spike,
    # TOOLCHAIN_MILESTONE_20_KERNEL_GAPS_RESULTS.md's own follow-on clean
    # -room-OS kickoff): does a genuinely SYSCALL-SHAPED ecall trap (a7
    # read + representative memory-touching "kernel work" inside the
    # handler via OCS.D/OCL.D) still correctly compose with M21-restore's
    # PCC auto-restore-on-mret, the same real property
    # vc_pcc_auto_restore_on_mret.S's own Phase 1 already proved for a
    # TRIVIAL (handler touches nothing) ecall? That earlier test's own
    # handler deliberately does zero work between ecall and mret -- this
    # spike is the cheap, front-loaded check (a real, adversarially
    # -reviewed risk this milestone's own design workflow flagged, not
    # assumed safe by analogy) that adding real handler-side work doesn't
    # silently break the same invariant before the real Syscall-0 kernel
    # (full GPR context save/restore, real dispatch) is built on top.
    #
    # Object_IDs 240-242, a fresh block (grep-audited against every
    # existing sail_tests/*.S `li x1, <N>` literal before picking --
    # highest prior use found was 230).
    la   t0, handler
    csrw mtvec, t0

    la   t0, compartment_u
    slli t0, t0, 32
    li   t1, 0x00540402            # Length=0x0054 (84B) -- must cover compartment_u's own
                                   # entry code (24B) PLUS resume:'s canary/CSR-readback
                                   # checks (which run INSIDE the still-narrow, restored
                                   # PCC bounds -- confirmed by objdump: the `la t4,
                                   # compartment_u` at offset 60-64 straddled a Length=0x40
                                   # boundary and faulted there instead of at the intended
                                   # `nop; j fail` escape point). Permit_Execute|Permit_Invoke.
    or   t0, t0, t1
    li   x1, 240
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate CODE (Object_ID 240)

    li   x1, 241
    li   x2, 0x800107000040040C    # Perms=0x040C = Load|Store|Invoke -- the handler
                                   # needs real OCS.D/OCL.D through this, unlike
                                   # vc_pcc_auto_restore_on_mret.S's own Invoke-only DATA cap.
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate DATA (Object_ID 241)

    li   x1, 242
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate type authority (Object_ID 242)

    li   x1, 240
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1 -- CODE
    li   x1, 241
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1 -- DATA (stays bound in the CRF across
                                 # OCInvoke and the trap -- neither one resets the CRF, only
                                 # PCC, matching the already-audited "OCInvoke/bind have zero
                                 # privilege/reset side effects on the CRF" property).
    li   x1, 242
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1 -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4 -- narrows PCC to compartment_u

compartment_u:
    # -- plant a canary in a callee-saved GPR, matching this project's
    #    own established convention for proving GPR state survives a
    #    trap round trip. --
    li   s1, 0xCAFEF00D

    # -- syscall-shaped ecall: a7 = a fake syscall number, matching the
    #    REAL RISC-V Linux syscall calling convention (a7=number) the
    #    actual Syscall-0 milestone will rely on. This spike does not
    #    need a real dispatch table -- only enough shape (a7 readable,
    #    real kernel-side memory work happens) to genuinely exercise the
    #    composition being tested, not a toy no-op ecall. --
    li   a7, 999
    ecall
resume:
    # -- reached only via mret's own automatic restore; nobody here
    #    explicitly wrote veda_pcc_base/_length back. --
    li   t3, 0xCAFEF00D
    bne  s1, t3, fail               # canary must have survived the full round trip

    csrr t3, 0x7c1                  # veda_pcc_length -- expect the ORIGINAL 0x0054, not unbounded
    li   t4, 0x0054
    bne  t3, t4, fail
    csrr t3, 0x7c0                  # veda_pcc_base -- expect compartment_u's own address
    la   t4, compartment_u
    bne  t3, t4, fail
    li   x24, 0x600D                # Step 0: restore + canary + real handler-side work, all correct

    # -- real enforcement, not just CSR readback (identical methodology
    #    vc_pcc_auto_restore_on_mret.S's own Phase 1 already established):
    #    the very next fetch genuinely exceeds compartment_u's real
    #    0x40-byte window. --
    nop
    j    fail                       # unreachable if the boundary correctly fired above

done:
    li   t2, 0x600D
    bne  x24, t2, real_fail
    li   t2, 0x900D
    bne  x22, t2, real_fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
real_fail:
    RVMODEL_HALT_FAIL

.balign 4
handler:
    csrr t3, mcause
    li   t4, 2                     # Illegal_Instruction -- the boundary-escape fetch fault
    beq  t3, t4, h_escape
    li   t4, 11                    # E_M_EnvCall -- the real syscall-shaped trap
    beq  t3, t4, h_ecall
    li   t4, 0x18                  # extension-exception -- also a real, valid boundary-fault shape
    beq  t3, t4, h_escape
    j    fail                      # unexpected trap cause

h_ecall:
    # -- representative "kernel work": read a7 (syscall number), then do
    #    a real OCS.D/OCL.D round-trip through the already-bound DATA
    #    capability (c1), proving real memory-touching kernel-side work
    #    inside the handler does not disturb the PCC-restore invariant.
    #    Deliberately does NOT touch mepcc -- that is the whole point,
    #    matching Phase 1's own established "auto-restore must do the
    #    work with zero handler code" proof. --
    mv   t5, a7                     # t5 := syscall number (999) -- proves a7 is genuinely readable

    li   t6, 0x1234
    .insn r 0x0b, 0x3, 0x01, t6, x1, x0  # ocs.d c1, x0(offset=0), t6(value)
    .insn r 0x0b, 0x3, 0x00, a1, x1, x0  # ocl.d c1, x0(offset=0), a1(dest)
    li   t4, 0x1234
    bne  a1, t4, fail                # kernel-side memory op must genuinely round-trip too

    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret

h_escape:
    # -- the fetch past compartment_u's real 0x40-byte boundary trapped
    #    here, confirming the restored bounds were genuinely enforced,
    #    not merely CSR-readable. --
    li   t3, 0xFFFF
    csrw 0x7c3, t3                  # explicit full unbind of the now-abandoned compartment's shadow
    li   x22, 0x900D                # final sentinel
    la   t3, done
    csrw mepc, t3
    mret
