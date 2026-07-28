.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 17: OCJALR -- closes the real, honest
    # gap STACK_FRAME_CALL_RETURN_ANALYSIS.md found by testing rather
    # than assuming. A return-address convention built entirely from
    # already-existing instructions (OCA+CSeal at the call site,
    # already proven working) left the return side as a hand-rolled
    # CUnseal+CGetAddr+JALR sequence with no hardware gate: a never-
    # sealed or corrupted-to-unsealed capability's own Base/Offset
    # fields were still readable and jumpable regardless. OCJALR merges
    # unseal-verification and jump into one atomic instruction, so the
    # check cannot be forgotten by construction -- the same real
    # property real CHERI's own CJALR provides (CHERI ISA spec p.213).
    #
    # Object_ID=70 (the jump target): Permit_Execute(bit1) = 0x0002,
    # Base = the real runtime address of landing_pad (via `la`).
    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x01000002        # Length=0x0100, Perms=0x0002 (Permit_Execute)
    or   t0, t0, t1
    li   x1, 70
    mv   x2, t0
    .word 0x0620828b           # veda.odt.populate x5, x1, x2

    # Object_ID=71: type-authority object, Permit_Seal|Permit_Unseal.
    li   x1, 71
    li   x2, 0x8001100000400300
    .word 0x0620828b           # veda.odt.populate x5, x1, x2

    li   x1, 70
    .word 0x0000d00b           # veda.bind c0, x1   -- target, unsealed
    li   x1, 71
    .word 0x0000d08b           # veda.bind c1, x1   -- type authority

    .word 0x2010115b           # cseal c2, c0, c1   -- sealed return-capability, otype=c1.Offset=0

    # -- The real, atomic verify-and-jump. --
    .word 0x2811105b           # ocjalr c2, c1

    # If OCJALR somehow fell through instead of jumping or trapping,
    # execution would reach here -- a real, distinct failure signature.
    li   x23, 0xBAD
    j    1f

landing_pad:
    # -- proves the jump landed at the EXACT resolved target. --
    li   x23, 0x600D
1:
    j 1b
