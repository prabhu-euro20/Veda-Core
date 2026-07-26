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
    .word 0x0620828b        # veda.odt.populate x5, x1, x2

    # Object_ID=31 (DATA): Permit_Invoke(bit10) ONLY = 0x0400 --
    # deliberately NOT Permit_Execute, both to satisfy OCInvoke's own
    # "data capability must be non-executable" check and to prove it's
    # enforced (vc_ocinvoke_neg.S's own job, not this file's).
    li   x1, 31
    li   x2, 0x8001070000400400
    .word 0x0620828b        # veda.odt.populate x5, x1, x2

    # Object_ID=32: a type-authority object, Permit_Seal|Permit_Unseal
    # (bits 8+9) = 0x0300 -- the same real fixture pattern already
    # proven in MILESTONE_V-B_RESULTS.md's own CSeal/CUnseal tests.
    li   x1, 32
    li   x2, 0x8001080000400300
    .word 0x0620828b        # veda.odt.populate x5, x1, x2

    li   x1, 30
    .word 0x0000d00b        # veda.bind c0, x1   -- CODE, unsealed, Offset=0 (target = landing_pad exactly)
    li   x1, 31
    .word 0x0000d08b        # veda.bind c1, x1   -- DATA, unsealed
    li   x1, 32
    .word 0x0000d10b        # veda.bind c2, x1   -- type authority

    .word 0x202011db        # cseal c3, c0, c2   -- sealed CODE, otype=c2.Offset=0
    .word 0x0601855b        # cgettag  x10, c3   -- expect 1
    .word 0x080185db        # cgettype x11, c3   -- expect 0 (sealed, not 0xFFFF)

    .word 0x2020925b        # cseal c4, c1, c2   -- sealed DATA, otype=c2.Offset=0 (MATCHES c3's own otype)
    .word 0x0602065b        # cgettag  x12, c4   -- expect 1
    .word 0x080206db        # cgettype x13, c4   -- expect 0

    # -- The real invoke: atomically unseals c3/c4 and jumps to c3's
    #    own resolved target address (landing_pad), installing unsealed
    #    c4 into c15 (IDC). If any check fails, this hard-traps instead
    #    (no handler installed in this positive test -- a real trap here
    #    would correctly fail the test via sail_riscv_sim's own real
    #    unhandled-trap behavior, not silently continue).
    .word 0x2441905b         # ocinvoke c3, c4

    # If OCInvoke somehow fell through instead of jumping or trapping,
    # execution would reach here (landing_pad's own address minus 4) --
    # a real, distinct failure signature, not just relying on the trap
    # path alone.
    j    fail

landing_pad:
    # -- proves the jump landed at the EXACT resolved target (this is
    #    the only path that reaches RVMODEL_HALT_PASS). --
    .word 0x06078a5b          # cgettag  x20, c15  -- expect 1 (IDC populated)
    .word 0x08078adb          # cgettype x21, c15  -- expect 0xFFFF (unsealed again)
    .word 0x00078b5b          # cgetbase x22, c15  -- expect 0x80010700 (really c4's own Base -- confirms it's genuinely the unsealed DATA cap, not something else)

    li   t2, 0x1
    bne  x20, t2, fail
    li   t2, 0xFFFF
    bne  x21, t2, fail
    li   t2, 0x80010700
    bne  x22, t2, fail

    RVMODEL_HALT_PASS

fail:
    RVMODEL_HALT_FAIL
