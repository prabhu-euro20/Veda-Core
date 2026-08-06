.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Minimal OS kernel Milestone B (MINIMAL_OS_KERNEL_DESIGN.md): the
    # single most important negative test in this milestone -- proves
    # ordinary, software-directed CSeal genuinely cannot forge a sentry.
    # Builds a type-authority object, walks its own Offset up to exactly
    # VEDA_OTYPE_SENTRY (0xFFFE) via OCA (the same real, already-proven
    # "offset the authority's Offset field" technique vc_ocjalr_neg.S's
    # own Negative-2 case already uses), then attempts an ordinary CSeal
    # through it. If the hardened VEDA_CSEAL authorization
    # (`cs2.Offset != VEDA_OTYPE_SENTRY`) were ever missing or wrong, this
    # would produce a capability indistinguishable from a genuine
    # CSealEntry-minted sentry to every downstream consumer (OCRETURN) --
    # a real, direct security hole, not a cosmetic one. CSeal soft-fails
    # rather than trapping (VEDA_CORE_SPEC.md's own real, already-proven
    # convention, confirmed against vc_cseal_unauth_neg.S), so the
    # assertion here is Tag==0, not a trap.

    # Object_ID=50: an ordinary target capability to attempt sealing,
    # Perms=Execute (bit1)=0x0002.
    li   x1, 50
    li   x2, 0x8005000000400002
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    # Object_ID=51: type-authority object, Permit_Seal|Permit_Unseal
    # (bits 8+9)=0x0300, Length=0xFFFF (generous enough to keep
    # Offset=0xFFFE genuinely in-bounds after the OCA walk below -- OCA's
    # own real semantics soft-fail, clearing the tag, if Offset would
    # land >= Length, confirmed by reading VEDA_OCA's execute clause
    # directly before relying on this).
    li   x1, 51
    li   x2, 0x80051000FFFF0300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 50
    .insn i 0x0b, 0x5, x5, x1, 0  # veda.bind c5, x1  -- target, unsealed
    li   x1, 51
    .insn i 0x0b, 0x5, x6, x1, 0  # veda.bind c6, x1  -- authority, unsealed, Offset=0

    li   x9, 0xFFFE
    .insn r 0x5b, 0x1, 0x0a, x6, x6, x9  # oca c6, c6, x9  -- c6.Offset: 0 -> 0xFFFE (still tagged: 0xFFFE < Length=0xFFFF)
    .insn r 0x5b, 0x0, 0x03, x12, x6, x0  # cgettag x12, c6  -- expect 1 (the OCA walk itself must have succeeded)

    # -- The actual forgery attempt: cs2 (c6) now has Offset==0xFFFE,
    #    exactly VEDA_OTYPE_SENTRY. Ordinary CSeal must refuse. --
    .insn r 0x5b, 0x1, 0x10, x7, x5, x6  # cseal c7, c5, c6  -- must SOFT-FAIL (Tag==0)
    .insn r 0x5b, 0x0, 0x03, x10, x7, x0  # cgettag x10, c7  -- expect 0

    li   t2, 1
    bne  x12, t2, fail
    li   t2, 0
    bne  x10, t2, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
