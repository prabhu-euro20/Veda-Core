.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL mirror of minimal OS kernel Milestone B negative
    # paths (MILESTONE_B_RESULTS.md), mirroring Sail's own already-
    # verified vc_cseal_sentry_forge_neg.S and vc_ocreturn_untagged_neg.S.
    #
    # Negative 1: the single most important negative test in this
    # milestone -- an authority capability walked to Offset=0xFFFE (the
    # reserved sentry otype) via OCA, then used with ORDINARY CSeal, must
    # soft-fail (Tag=0), not produce a forged sentry. Real RTL proof that
    # the hardened $veda_cseal_authorized check (`!= 16'hFFFE`) genuinely
    # blocks forgery, not merely assumed from the Sail-side proof.
    #
    # Object_ID=51: type-authority object, Perms=Seal|Unseal=0x0300,
    # Length=0xFFFF (generous enough to keep Offset=0xFFFE genuinely
    # in-bounds after the OCA walk -- OCA soft-fails, clearing the tag,
    # if Offset would land >= Length).
    # ─────────────────────────────────────────────────────────────
    li   x1, 51
    li   x2, 0x80051000FFFF0300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 51
    .insn i 0x0b, 0x5, x6, x1, 0  # veda.bind c6, x1  -- authority, unsealed, Offset=0

    li   x9, 0xFFFE
    .insn r 0x5b, 0x1, 0x0a, x6, x6, x9  # oca c6, c6, x9  -- c6.Offset: 0 -> 0xFFFE (still tagged)
    .insn r 0x5b, 0x0, 0x03, x12, x6, x0  # cgettag x12, c6  -- expect 1 (the OCA walk itself must have succeeded)

    # Object_ID=50: an ordinary target capability to attempt sealing,
    # Perms=Execute=0x0002.
    li   x1, 50
    li   x2, 0x8005000000400002
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2
    li   x1, 50
    .insn i 0x0b, 0x5, x5, x1, 0  # veda.bind c5, x1  -- target, unsealed

    # -- the actual forgery attempt: cs2 (c6) now has Offset==0xFFFE. --
    .insn r 0x5b, 0x1, 0x10, x7, x5, x6  # cseal c7, c5, c6  -- must SOFT-FAIL (Tag==0)
    .insn r 0x5b, 0x0, 0x03, x10, x7, x0  # cgettag x10, c7  -- expect 0

    # ─────────────────────────────────────────────────────────────
    # Negative 2: OCRETURN through an untagged capability (c1 was never
    # bound) must hard-trap TAG_VIOLATION -- the same real check OCJALR's
    # own cs1-side already performs, cause/cap_idx encoding verified
    # against the already-proven veda_smoke_m22.S convention.
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

ocreturn_fault:
    .insn r 0x5b, 0x1, 0x16, x0, x1, x0  # ocreturn c1  -- c1 was never bound, untagged -- must TRAP
    li   x22, 0xBAD1                      # must NOT be reached directly
    j    done

trap_handler:
    csrr t4, mcause
    li   t5, 0x18
    bne  t4, t5, fail
    csrr t4, mtval
    li   t5, 0x22                         # TAG_VIOLATION(0x02), cap_idx=1 (c1) -> (1<<5)|0x02=0x22
    bne  t4, t5, fail

    li   x11, 0x600D                       # sentinel: reached the handler with the correct mcause/mtval
    la   t4, done
    csrw mepc, t4
    mret

fail:
    li   x11, 0xBAD

done:
1:
    j 1b
