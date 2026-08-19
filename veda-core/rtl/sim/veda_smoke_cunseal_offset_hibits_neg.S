.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Adversarial-review Finding #2 (HIGH): CUnseal's own widened-
    # otype compare site ($veda_cunseal_authorized, veda_core.tlv
    # around lines 2184-2187) is a SEPARATE RTL expression from
    # CSeal's own precondition (already covered by
    # veda_smoke_cseal_offset_hibits_neg.S) -- never independently
    # tested. This proves CUnseal correctly REJECTS a forgery: an
    # "attacker" authority capability whose own Offset (0x10005)
    # shares the real otype's low 16 bits (5) but has nonzero
    # bits[19:16] must NOT unseal a capability whose real otype is 5,
    # because correct zero-extension ({4'b0, cs1.otype} = 0x00005)
    # != the full 20-bit 0x10005. A truncating (pre-widening-style)
    # bug at this specific site would wrongly let the forgery through.
    # A genuine, exact-match authority (Offset=5) unsealing the SAME
    # sealed capability into a separate destination register succeeds
    # (Tag=1) in the same test, proving the forgery's rejection isn't
    # just "CUnseal is broken generally".
    #
    # Object_ID=508 (real, small-Length authority that mints the
    # sealed cap), 509 (attacker, widened-Length authority). Fresh
    # block -- 500-507 already used by this pass's other new tests.
    # ─────────────────────────────────────────────────────────────

    # Object_ID=508: real authority, Perms=Permit_Seal|Permit_Unseal
    # (0x0300), ordinary small Length -- plain VEDA_ODT_POPULATE
    # suffices (no widened value needed for the real authority).
    li   x1, 508
    li   x2, 0x8003000000400300   # Base=0x80030000, Length=0x0040, Perms=0x0300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2

    li   x1, 508
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1  -- real authority, unsealed, Offset=0

    # Move c0's Offset to 5 -- the real otype value about to be minted.
    li   x2, 5
    .insn r 0x5b, 0x1, 0x0a, x1, x0, x2   # oca c1, c0, x2  -- c1.Offset := 5 (real authority)
    .insn r 0x5b, 0x0, 0x03, x10, x1, x0  # cgettag x10, c1  -- expect 1 (in-range, sanity)

    # Object_ID=1 (this RTL's own reset-seeded fixture): a real,
    # ordinary unsealed capability to seal -- this test's own focus is
    # the AUTHORITY side (cs2), not cs1.
    li   x1, 1
    .insn i 0x0b, 0x5, x2, x1, 0   # veda.bind c2, x1  -- cs1, unsealed

    # Mint the real sealed capability: c3.otype := c1.Offset = 5.
    .insn r 0x5b, 0x1, 0x10, x3, x2, x1   # cseal c3, c2, c1
    .insn r 0x5b, 0x0, 0x03, x11, x3, x0  # cgettag x11, c3  -- expect 1 (mint succeeded, otype=5)

    # Object_ID=509: attacker authority, widened Length (>0x10005, so
    # Offset=0x10005 stays genuinely in-bounds -- this test's only
    # focus is the otype-compare gate, not an incidental bounds
    # violation), same Permit_Seal|Permit_Unseal Perms. Mirrors the
    # setup pattern in veda_smoke_cseal_offset_hibits_neg.S.
    li   t1, 0x100100300   # veda_attr: Length=0x10010, Perms=0x0300
    csrw 0x7c4, t1
    li   x1, 509
    li   x2, 0x80040000
    .insn r 0x0b, 0x0, 0x04, x5, x1, x2   # veda.odt.populate.fast x5, x1, x2

    li   x1, 509
    .insn i 0x0b, 0x5, x4, x1, 0   # veda.bind c4, x1  -- attacker authority, unsealed, Offset=0

    # Move c4's Offset to 0x10005 -- same low 16 bits as the real
    # otype (5), but bits[19:16]=0x1, genuinely nonzero.
    li   x2, 0x10005
    .insn r 0x5b, 0x1, 0x0a, x5, x4, x2   # oca c5, c4, x2  -- c5.Offset := 0x10005 (attacker)
    .insn r 0x5b, 0x0, 0x03, x12, x5, x0  # cgettag x12, c5  -- expect 1 (in-range, sanity -- 0x10005 < 0x10010)

    # THE FORGERY ATTEMPT: attacker authority (c5, Offset=0x10005)
    # against the real sealed cap (c3, otype=5). Correct zero-extended
    # compare: 0x10005 != {4'b0, 5} (=0x00005) -> MUST soft-fail.
    .insn r 0x5b, 0x1, 0x11, x6, x3, x5   # cunseal c6, c3, c5
    .insn r 0x5b, 0x0, 0x03, x13, x6, x0  # cgettag x13, c6  -- expect 0 (forgery correctly REJECTED)

    # THE GENUINE UNSEAL: real authority (c1, Offset=5, EXACT match)
    # against the SAME sealed cap (c3) -- proves the rejection above is
    # specific to the widened-bits mismatch, not CUnseal being broken.
    .insn r 0x5b, 0x1, 0x11, x7, x3, x1   # cunseal c7, c3, c1
    .insn r 0x5b, 0x0, 0x03, x14, x7, x0  # cgettag x14, c7  -- expect 1 (genuine unseal succeeds)

1:
    j 1b
