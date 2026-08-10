.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # First real experiment with U-mode enabled (veda_test_sail.json's own
    # "U": {"supported": true} flip -- previously false, the only config
    # change this test required; confirmed via a fresh full self-check run
    # that flipping it alone changes nothing, since no pre-existing test
    # ever transitions privilege). This test empirically checks the
    # source-audit finding that Veda-Core's own core capability mechanism
    # (Object-Bind/CRF, OCInvoke) carries zero privilege-level gating,
    # while the administrative ODT-Populate/Destroy path correctly stays
    # M-mode/ODA-gated even from inside a live U-mode compartment.
    la   t0, trap_handler
    csrw mtvec, t0

    # --- M-mode setup: populate + bind + seal, exactly the established
    #     pattern from vc_pcc_generic_trap_reset.S/vc_ocinvoke.S ---
    la   t0, u_compartment_entry
    slli t0, t0, 32
    li   t1, 0x00400402          # Length=0x0040
    or   t0, t0, t1
    li   x1, 60
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate CODE

    li   x1, 61
    li   x2, 0x800107000040040C  # Base=0x80010700 Length=0x0040 Perms=0x040C (bit2 LOAD | bit3 STORE | bit10 INVOKE)
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate DATA

    li   x1, 62
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate type authority

    li   x1, 60
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  (code)
    li   x1, 61
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  (data)
    li   x1, 62
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  (type authority)

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    li   x20, 0xFEED              # phase markers, untouched sentinel
    li   x21, 0xFEED
    li   x22, 0xFEED
    li   x23, 0xFEED

    # --- Drop privilege: M-mode -> U-mode via mret ---
    # mstatus.MPP occupies bits [12:11]; clearing both bits (mask 0x1800)
    # sets MPP = 0b00 (User), the standard, well-established RISC-V
    # privileged-spec encoding (Table in the mstatus section).
    la   t0, u_entry
    csrw mepc, t0
    li   t0, 0x1800
    csrc mstatus, t0              # MPP := User
    mret

.balign 4
u_entry:
    # ---- now genuinely running at U-mode ----

    # Phase 1: plain OCL.D/OCS.D through the already-bound c1 (data
    # capability), PCC still unbounded (OCInvoke hasn't run yet). Tests
    # whether ordinary capability-gated data access needs any privilege
    # at all -- source audit found zero privilege checks in
    # veda_check_access. Real encoding confirmed against
    # vc_ocl_ocs_selfcheck.S: .insn r opcode, funct3, funct7, rd, rs1(vcap), rs2(offset) --
    # funct3=0x3 selects the .D (64-bit) width, funct7 0x01=OCS/0x00=OCL,
    # rs1's register-number slot encodes the capability index (c1 here),
    # not a GPR read.
    li   x7, 0x1234                # value to store
    li   x6, 0                     # offset
    .insn r 0x0b, 0x3, 0x01, x7, x1, x6  # ocs.d c1, x6, x7  (store x7 -> c1[x6])
    li   x8, 0                     # clear so a no-op load can't accidentally pass
    .insn r 0x0b, 0x3, 0x00, x8, x1, x6  # ocl.d c1, x6, x8  (load c1[x6] -> x8)
    li   t3, 0x1234
    bne  x8, t3, fail
    li   x20, 0x600D               # phase 1 passed: U-mode OCL.D/OCS.D worked

    # Phase 2: OCInvoke from U-mode -- narrows PCC to the sealed code
    # region. Source audit found zero privilege check in OCInvoke's own
    # execute clause either.
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4

.balign 4
u_compartment_entry:
    # ---- narrowed PCC, still U-mode, inside the compartment ----
    li   x21, 0x600D               # phase 2 passed: OCInvoke worked from U-mode

    # Phase 3: administrative ODT-Populate MUST still fail here -- U-mode,
    # no ODA delegation set up. Expect Illegal_Instruction (mcause=2).
    # h_phase3 below sets x22 and mret's straight back to the next
    # instruction (mepc+=4 skips exactly this trapping .insn, which is
    # never actually retired).
    li   x1, 70
    li   x2, 0x8001090000400200
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate -- should trap

    # Phase 4: ecall from U-mode, still inside the OCInvoke-narrowed
    # compartment. h_phase4 below does the real check.
    ecall

    # -- genuinely unreachable: h_phase4 jumps straight to done --
    j    fail

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 2                     # Illegal_Instruction -- Phase 3's ODT-Populate
    beq  t3, t4, h_phase3

    li   t4, 8                     # E_U_EnvCall -- Phase 4's ecall
    beq  t3, t4, h_phase4

    j    fail                      # unexpected trap cause

h_phase3:
    li   x22, 0x600D               # phase 3 confirmed: ODT-Populate correctly blocked from U-mode

    csrr t3, mepc
    addi t3, t3, 4                 # skip the trapping .insn (4 bytes, uncompressed)
    csrw mepc, t3
    # mstatus.MPP was set to User (0) by hardware on trap entry -- mret
    # returns to U-mode automatically, no explicit MPP write needed.
    mret

h_phase4:
    # Reached via the ecall triggered after Phase 3 resumes (see below).
    # Confirm handle_trap_extension's universal PCC reset (Milestone 21)
    # fired correctly for a trap DELEGATED FROM U-mode, not just from
    # M-mode as every prior test exercised.
    csrr t3, 0x7c1                 # veda_pcc_length -- expect VEDA_PCC_UNBOUNDED
    li   t4, 0xFFFF
    bne  t3, t4, fail

    li   x23, 0x600D               # phase 4 confirmed: U-mode ecall + universal PCC reset both correct
    j    done

fail:
    li   x20, 0xDEAD

done:
    li   t2, 0x600D
    bne  x20, t2, real_fail
    bne  x21, t2, real_fail
    bne  x22, t2, real_fail
    bne  x23, t2, real_fail

    RVMODEL_HALT_PASS
real_fail:
    RVMODEL_HALT_FAIL
