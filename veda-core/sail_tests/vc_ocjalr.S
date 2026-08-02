.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core formal model: OCJALR -- closes the real, honest gap
    # STACK_FRAME_CALL_RETURN_ANALYSIS.md found by testing rather than
    # assuming. A return-address convention built entirely from
    # already-existing instructions (OCA+CSeal at the call site, already
    # proven working) left the *return* side as a software-discipline
    # -dependent CUnseal+CGetAddr+JALR sequence -- the explicit CGetTag
    # check that made it safe could be silently omitted with no hardware
    # gate. OCJALR merges unseal-verification and jump into one atomic
    # instruction, so the check cannot be forgotten by construction --
    # the same real property real CHERI's own CJALR provides for its
    # sentry-capability jumps (CHERI ISA spec p.213).
    #
    # Object_ID=70 (the jump target, standing in for a real return site):
    # Permit_Execute(bit1) = 0x0002, Base = the real runtime address of
    # landing_pad (computed via la, not a compile-time constant).
    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x01000002        # Length=0x0100, Perms=0x0002 (Permit_Execute)
    or   t0, t0, t1
    li   x1, 70
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    # Object_ID=71: type-authority object, Permit_Seal|Permit_Unseal
    # (bits 8+9) = 0x0300 -- the same real fixture pattern already
    # proven in the CSeal/CUnseal and OCInvoke tests above.
    li   x1, 71
    li   x2, 0x8001100000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 70
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1   -- target, unsealed, Offset=0 (resolves to landing_pad exactly)
    li   x1, 71
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1   -- type authority

    # -- Seal the target under the authority, exactly matching the real
    #    call-site convention STACK_FRAME_CALL_RETURN_ANALYSIS.md already
    #    verified working (OCA+CSeal), simplified here to a direct CSeal
    #    since Offset=0 already resolves to the real target address. --
    .insn r 0x5b, 0x1, 0x10, x2, x0, x1  # cseal c2, c0, c1   -- sealed return-capability, otype=c1.Offset=0
    .insn r 0x5b, 0x0, 0x03, x10, x2, x0  # cgettag  x10, c2   -- expect 1
    .insn r 0x5b, 0x0, 0x04, x11, x2, x0  # cgettype x11, c2   -- expect 0 (sealed, not 0xFFFF)

    # -- The real, atomic verify-and-jump: checks Tag(c2), Tag(c1),
    #    Seal(c2) must hold, Seal(c1) must NOT hold, Permit_Unseal(c1),
    #    matching otype, Permit_Execute(c2) -- all in one instruction, no
    #    software-visible intermediate state an attacker (or a forgetful
    #    caller) could skip past. If any check fails, this hard-traps
    #    instead (no handler installed in this positive test -- a real
    #    trap here would correctly fail the test via sail_riscv_sim's own
    #    real unhandled-trap behavior, not silently continue). --
    .insn r 0x5b, 0x1, 0x14, x0, x2, x1  # ocjalr c2, c1

    # If OCJALR somehow fell through instead of jumping or trapping,
    # execution would reach here -- a real, distinct failure signature.
    j    fail

landing_pad:
    # -- proves the jump landed at the EXACT resolved target. --
    li   t2, 0x600D
    RVMODEL_HALT_PASS

fail:
    RVMODEL_HALT_FAIL
