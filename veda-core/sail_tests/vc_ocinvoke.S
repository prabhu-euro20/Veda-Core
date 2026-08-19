.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core formal model: OCInvoke -- the CInvoke-equivalent
    # protection-domain-transition instruction (VEDA_CORE_SPEC.md
    # Section 6 item 7, now closed). Term-for-term adaptation of real
    # CHERI's CInvoke (CHERI ISA spec p.209): a sealed CODE capability
    # and a sealed DATA capability, with matching otype and both
    # carrying Permit_Invoke, atomically unseal-and-jump -- the code
    # capability's own resolved address becomes the new PC, the
    # unsealed data capability lands in c15 (Veda-Core's own IDC
    # convention, the last CRF entry, proportional to CHERI's own real
    # C31/IDC convention in its 32-entry file).
    #
    # Object_ID=30 (CODE): Permit_Execute(bit1)|Permit_Invoke(bit10) =
    # 0x0402, Base = the real runtime address of landing_pad (so that
    # Base+Offset(0, fresh bind default) resolves to exactly the target
    # this test jumps to and verifies -- computed at runtime via `la`,
    # not a compile-time constant, since the target is this same file's
    # own address). Length=0x0100 (256 bytes) -- Milestone 14 update:
    # a real, genuine consumer of this Length now exists
    # (PCC_COMPARTMENT_DESIGN.md's own fetch-time compartment bound,
    # narrowed to exactly this Base/Length on a successful OCInvoke) --
    # widened from the original 0x0040 (which landing_pad's own real
    # code, including RVMODEL_HALT_PASS's own macro expansion, came
    # close enough to that it's not worth relying on exactly, a real,
    # fragile boundary this milestone's own enforcement newly exposed).
    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x01000402
    or   t0, t0, t1
    li   x1, 30
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    # Object_ID=31 (DATA): Permit_Invoke(bit10) ONLY = 0x0400 --
    # deliberately NOT Permit_Execute, both to satisfy OCInvoke's own
    # "data capability must be non-executable" check and to prove it's
    # enforced (vc_ocinvoke_neg.S's own job, not this file's).
    li   x1, 31
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    # Object_ID=32: a type-authority object, Permit_Seal|Permit_Unseal
    # (bits 8+9) = 0x0300 -- the same real fixture pattern already
    # proven in MILESTONE_V-B_RESULTS.md's own CSeal/CUnseal tests.
    li   x1, 32
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 30
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1   -- CODE, unsealed, Offset=0 (target = landing_pad exactly)
    li   x1, 31
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1   -- DATA, unsealed
    li   x1, 32
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1   -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2   -- sealed CODE, otype=c2.Offset=0
    .insn r 0x5b, 0x0, 0x03, x10, x3, x0  # cgettag  x10, c3   -- expect 1
    .insn r 0x5b, 0x0, 0x04, x11, x3, x0  # cgettype x11, c3   -- expect 0 (sealed, not 0xFFFF)

    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2   -- sealed DATA, otype=c2.Offset=0 (MATCHES c3's own otype)
    .insn r 0x5b, 0x0, 0x03, x12, x4, x0  # cgettag  x12, c4   -- expect 1
    .insn r 0x5b, 0x0, 0x04, x13, x4, x0  # cgettype x13, c4   -- expect 0

    # -- The real invoke: atomically unseals c3/c4 and jumps to c3's
    #    own resolved target address (landing_pad), installing unsealed
    #    c4 into c15 (IDC). If any check fails, this hard-traps instead
    #    (no handler installed in this positive test -- a real trap here
    #    would correctly fail the test via sail_riscv_sim's own real
    #    unhandled-trap behavior, not silently continue).
    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4

    # If OCInvoke somehow fell through instead of jumping or trapping,
    # execution would reach here (landing_pad's own address minus 4) --
    # a real, distinct failure signature, not just relying on the trap
    # path alone.
    j    fail

landing_pad:
    # -- proves the jump landed at the EXACT resolved target (this is
    #    the only path that reaches RVMODEL_HALT_PASS). --
    .insn r 0x5b, 0x0, 0x03, x20, x15, x0  # cgettag  x20, c15  -- expect 1 (IDC populated)
    .insn r 0x5b, 0x0, 0x04, x21, x15, x0  # cgettype x21, c15  -- expect 0xFFFF (unsealed again)
    .insn r 0x5b, 0x0, 0x00, x22, x15, x0  # cgetbase x22, c15  -- expect 0x80010700 (really c4's own Base -- confirms it's genuinely the unsealed DATA cap, not something else)

    li   t2, 0x1
    bne  x20, t2, fail
    li   t2, 0xFFFF
    bne  x21, t2, fail
    li   t2, 0x80010700
    bne  x22, t2, fail

    # Milestone 19 (Veda-Purecap Enforcement) addition: this test never
    # exits the OCInvoke-entered compartment before this point (unlike
    # vc_pcc_bounds.S, whose own equivalent landing_pad already does a
    # return-OCInvoke to widen PCC back to unbounded first) -- a real,
    # honest gap this milestone's new enforcement exposed, found via
    # actual testing (a genuine trap loop), not assumed: RVMODEL_HALT_PASS
    # itself uses an ordinary `sw` to the tohost MMIO region, which the
    # new ext_data_get_addr hook now correctly blocks from inside any
    # still-live compartment (veda_pcc_length != VEDA_PCC_UNBOUNDED),
    # exactly like it blocks any other ordinary store there. Fixed the
    # architecturally correct way, mirroring vc_pcc_bounds.S's own
    # already-established "return OCInvoke into an unbounded capability"
    # pattern -- not by weakening the enforcement.
    # -- Object_ID=33 (return CODE): Base=return_pad, Length=0xFFFFF
    #    (VEDA_PCC_UNBOUNDED, 20-bit sentinel since the 2026-08-19
    #    widening), Perms=Permit_Execute|Permit_Invoke=0x0402. Plain
    #    VEDA_ODT_POPULATE's own 16-bit-capped Length field can never
    #    represent this value (NEXT_STEPS_ROADMAP.md "Break 3"), so
    #    VEDA_ODT_POPULATE_FAST + veda_attr is required here. --
    li   t1, 0xFFFFF0402           # veda_attr: Length=0xFFFFF, Perms=0x0402
    csrw 0x7c4, t1
    la   t0, return_pad
    li   x1, 33
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2  # veda.odt.populate.fast x5, x1, x2

    # -- Object_ID=34 (return DATA): Permit_Invoke only = 0x0400. --
    li   x1, 34
    li   x2, 0x8001090000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 33
    .insn i 0x0b, 0x5, x5, x1, 0  # veda.bind c5, x1  -- return CODE
    li   x1, 34
    .insn i 0x0b, 0x5, x6, x1, 0  # veda.bind c6, x1  -- return DATA

    .insn r 0x5b, 0x1, 0x10, x7, x5, x2  # cseal c7, c5, c2  -- sealed return CODE
    .insn r 0x5b, 0x1, 0x10, x8, x6, x2  # cseal c8, c6, c2  -- sealed return DATA

    .insn r 0x5b, 0x1, 0x12, x0, x7, x8  # ocinvoke c7, c8   -- widens PCC back to unbounded

return_pad:
    RVMODEL_HALT_PASS

fail:
    RVMODEL_HALT_FAIL
