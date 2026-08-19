.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Length/Offset widening RTL mirror (mirrors vc_oclc_alignment_neg.S's
    # own Sail scenario exactly): OCL.C/OCS.C now require the real,
    # physical store address to be 32-byte aligned -- real Sail/RTL
    # parity with the RTL's own already-decided tag-store design (2
    # statically-adjacent granule writes), matching real CHERI-RISC-V's
    # own [C]LC/[C]SC alignment requirement. This test proves the gate
    # actually fires in RTL: an object deliberately based at a
    # 16-byte-aligned-but-NOT-32-byte-aligned address, accessed at
    # offset 0 (so the real store address equals the object's own
    # Base), must hard-trap with the new VEDA_CAUSE_ALIGNMENT_VIOLATION
    # (0x08) cause -- not silently succeed, and not trap with the
    # wrong cause (which would mean some OTHER check, not this one,
    # actually fired).
    #
    # Adversarial-review Finding #3: Base is deliberately chosen
    # 16-byte aligned but NOT 32-byte aligned (mod 32 == 16), not the
    # earlier draft's Base=0x80010004 (mod 32 == 4, misaligned at
    # every power-of-two >= 8 simultaneously). That earlier value
    # could not isolate WHICH alignment boundary the real gate
    # enforces: a hypothetical, accidentally-coarser-than-intended
    # 16-byte-only check would ALSO have trapped it, so the test
    # couldn't tell the two apart. Base=0x80010010 is a real
    # discriminator: it satisfies a (wrong) 16-byte-only check but
    # violates the real 32-byte one, so a hypothetical 16-byte-only
    # regression would make this test wrongly PASS the access (no
    # trap) instead of trapping it -- the test would then correctly
    # fail, catching the regression. Under the real, correct 32-byte
    # gate, this access still hard-traps as before.
    #
    # Object_ID=502 (fresh block).
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    # Object_ID=502 (target, Load|Store): Base=0x80010010 -- 16 mod 32,
    # genuinely 16-byte aligned but NOT 32-byte aligned, so this test
    # isolates the real 32-byte requirement precisely (see Finding #3
    # note above) rather than merely being misaligned at every
    # power-of-two the way a coarser choice would be. Length=0x0020
    # (32 bytes), generous headroom over the 17-byte OCS.C access this
    # test attempts. Plain VEDA_ODT_POPULATE suffices here (Length
    # fits easily in 16 bits, no widened-Length descriptor needed).
    li   x1, 502
    li   x2, 0x800100100020000C   # Base=0x80010010, Length=0x0020, Perms=0x000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2

    li   x1, 502
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1  -- target/address capability

    # Object_ID=1 (this RTL's own reset-seeded fixture): a real, ordinary
    # tagged capability to attempt storing through the misaligned target
    # -- this test's own focus is the ALIGNMENT gate, not the value
    # being stored.
    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 0   # veda.bind c1, x1  -- value capability

    li   x5, 0
    .insn r 0x0b, 0x4, 0x01, x1, x0, x5   # ocs.c c0, x5(=0), c1  -- store through misaligned c0 -- must trap

    li   x21, 0xBAD1  # must NOT be reached
    j    done

trap_handler:
    csrr t4, mcause
    li   t5, 0x18
    bne  t4, t5, fail
    csrr t4, mtval
    li   t5, 0x08        # (cap_idx=0<<5)|cause=0x08 (VEDA_CAUSE_ALIGNMENT_VIOLATION)
    bne  t4, t5, fail

    li   x21, 0x600D     # sentinel: reached the handler with the correct mcause/mtval
    j    done

fail:
    li   x21, 0xBAD

done:
1:
    j 1b
