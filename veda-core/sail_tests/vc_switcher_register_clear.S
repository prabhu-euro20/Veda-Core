.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Minimal OS kernel Milestone A: the switcher pattern -- a cross-
    # compartment call routes through one fixed, trusted switcher
    # compartment (never compartment-to-compartment directly), which
    # clears non-argument registers before performing the real hand-off
    # via a second, real `OCInvoke` -- exactly the real CHERI CInvoke
    # design rationale (CHERI ISA spec §9.22, read in full):
    # "CInvoke will be used to invoke trusted software routines...
    # [which are] responsible for clearing non-argument capability and
    # general-purpose integer registers... followed by a CJR to
    # transfer control to the callee." This test builds two real
    # compartments (switcher, target) and empirically proves: (a) a
    # poisoned, non-argument GPR set before the first OCInvoke is
    # genuinely cleared by the switcher's own real code before it
    # reaches the target, not merely assumed clean by convention; (b)
    # the switcher's own second, real OCInvoke correctly lands control
    # in the target compartment.
    #
    # CODE compartment Length is 0x0100 (256 bytes), mirroring
    # vc_ocinvoke.S's own already-proven convention -- not the minimal
    # 0x0004 (single-instruction) bound Milestone 22's negative test
    # deliberately used. This test is a positive, functional switcher
    # path: the switcher itself must fetch two real instructions
    # (clear + second OCInvoke), and the target must fetch its own
    # check instruction plus the full return-capability construction
    # sequence below -- both need real headroom, not a boundary-testing
    # single slot.
    #
    # Target compartment's sealed code/data capabilities (c5/c6) are
    # built and sealed here in `_start`, BEFORE entering the switcher --
    # capability registers are not cleared by OCInvoke, only PCC
    # narrows, so they survive into the switcher exactly like a real
    # trusted intermediary that already holds capabilities to the
    # compartments it may route calls into.
    la   t0, target_entry
    slli t0, t0, 32
    li   t1, 0x01000402        # Length=0x0100, Perms=0x0402 (Execute|Invoke)
    or   t0, t0, t1
    li   x1, 33
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- TARGET CODE

    li   x1, 34
    li   x2, 0x8003070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- TARGET DATA

    li   x1, 35
    li   x2, 0x8003080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- type authority (target)

    li   x1, 33
    .insn i 0x0b, 0x5, x5, x1, 0  # veda.bind c5, x1  -- TARGET CODE, unsealed
    li   x1, 34
    .insn i 0x0b, 0x5, x6, x1, 0  # veda.bind c6, x1  -- TARGET DATA, unsealed
    li   x1, 35
    .insn i 0x0b, 0x5, x7, x1, 0  # veda.bind c7, x1  -- type authority (target)

    .insn r 0x5b, 0x1, 0x10, x5, x5, x7  # cseal c5, c5, c7  -- sealed TARGET CODE
    .insn r 0x5b, 0x1, 0x10, x6, x6, x7  # cseal c6, c6, c7  -- sealed TARGET DATA

    # -- The switcher compartment itself: Object_ID=30/31/32
    #    (CODE/DATA/type authority). --
    la   t0, switcher_entry
    slli t0, t0, 32
    li   t1, 0x01000402        # Length=0x0100, Perms=0x0402 (Execute|Invoke)
    or   t0, t0, t1
    li   x1, 30
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- SWITCHER CODE

    li   x1, 31
    li   x2, 0x8002070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- SWITCHER DATA

    li   x1, 32
    li   x2, 0x8002080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- type authority (switcher)

    li   x1, 30
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- SWITCHER CODE
    li   x1, 31
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- SWITCHER DATA
    li   x1, 32
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- type authority (switcher)

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2  -- sealed SWITCHER CODE
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2  -- sealed SWITCHER DATA

    # -- The real, poisoned "leftover secret" a caller might otherwise
    #    accidentally leak across a domain transition -- a non-argument
    #    register the switcher's own real job is to clear. --
    li   x20, 0xBAD5EC12

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4  -- narrows PCC to [switcher_entry, switcher_entry+0x100), enters the switcher

    li   x22, 0xDEAD                     # must NOT be reached -- would mean OCInvoke fell through
    j    done

switcher_entry:
    # -- The switcher's own real work: clear the non-argument register
    #    (the real property this test exists to prove), then perform
    #    the second, real hand-off into the already-sealed target
    #    compartment (c5/c6, prepared in _start and untouched by the
    #    first OCInvoke). --
    li   x20, 0
    .insn r 0x5b, 0x1, 0x12, x0, x5, x6  # ocinvoke c5, c6  -- narrows PCC to [target_entry, target_entry+0x100), enters the target

    li   x22, 0xBEEF                     # must NOT be reached -- would mean the second OCInvoke fell through
    j    done

target_entry:
    # -- The load-bearing assertion: x20 must read back genuinely
    #    cleared here, inside the TARGET compartment -- proving the
    #    switcher's own clearing code actually ran and took effect
    #    before control ever reached here, not just that this test
    #    happened to never poison it again. --
    li   x22, 0x600D

    # -- Mirrors vc_ocinvoke.S's own already-proven, already-fixed
    #    pattern (Milestone 19 comment therein): RVMODEL_HALT_PASS does
    #    an ordinary `sw` to the tohost MMIO region, which the
    #    ext_data_get_addr hook correctly blocks from inside any
    #    still-live, bounded compartment. Build a real, sealed RETURN
    #    capability pair (Object_ID=40/41/42) HERE, inside target_entry
    #    (this compartment's own Length=0x0100 has real headroom for
    #    this construction sequence, matching landing_pad's own exact
    #    convention in vc_ocinvoke.S), then OCInvoke through it to
    #    widen PCC back to VEDA_PCC_UNBOUNDED before touching the halt
    #    macro -- the architecturally correct way, not a weakened
    #    enforcement. c0-c4 (the switcher's own unsealed/sealed
    #    capabilities) are no longer needed past this point and are
    #    reused here as scratch, mirroring this file's own existing
    #    economical-register-reuse convention. --
    la   t0, return_pad
    slli t0, t0, 32
    li   t1, 0xFFFF0402        # Length=0xFFFF (VEDA_PCC_UNBOUNDED), Perms=0x0402 (Execute|Invoke)
    or   t0, t0, t1
    li   x1, 40
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- RETURN CODE

    li   x1, 41
    li   x2, 0x8004090000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- RETURN DATA

    li   x1, 42
    li   x2, 0x8004080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- type authority (return)

    li   x1, 40
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- RETURN CODE, unsealed
    li   x1, 41
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- RETURN DATA, unsealed
    li   x1, 42
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- type authority (return)

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2  -- sealed RETURN CODE
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2  -- sealed RETURN DATA

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4  -- widens PCC back to unbounded, lands at return_pad

    li   x22, 0xFEED                     # must NOT be reached -- would mean the return OCInvoke fell through
    j    done

.balign 4
return_pad:
    j    done

.balign 4
done:
    li   t2, 0
    bne  x20, t2, fail
    li   t2, 0x600D
    bne  x22, t2, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
