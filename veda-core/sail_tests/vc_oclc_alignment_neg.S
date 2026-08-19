.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Length/Offset widening (NEXT_STEPS_ROADMAP.md, "a thorough
    # pre-implementation audit"): OCL.C/OCS.C now require the real,
    # physical store address to be 32-byte aligned -- real Sail/RTL
    # parity with the already-decided RTL tag-store design (2
    # statically-adjacent granule writes), matching real CHERI-RISC-V's
    # own [C]LC/[C]SC alignment requirement. This test proves the gate
    # actually fires: an object deliberately based at a NON-32-byte
    # -aligned address, accessed at offset 0 (so the real store address
    # equals the object's own misaligned Base), must hard-trap with the
    # new VEDA_CAUSE_ALIGNMENT_VIOLATION (0x08) cause -- not silently
    # succeed, and not trap with the wrong cause (which would mean some
    # OTHER check, not this one, actually fired).
    la   t0, trap_handler
    csrw mtvec, t0

    # Object_ID=463 (target, Load|Store): Base=0x80010004 -- 4 mod 32,
    # deliberately misaligned, but still 4-byte aligned (so this is
    # genuinely testing the NEW 32-byte requirement, not an ordinary
    # base-ISA misaligned-access fault). Length=0x0020 (32 bytes),
    # generous headroom over the 17-byte OCS.C access this test
    # attempts. Plain VEDA_ODT_POPULATE suffices here (Length fits
    # easily in 16 bits, no widened-Length descriptor needed).
    li   x1, 463
    li   x2, 0x800100040020000C   # Base=0x80010004, Length=0x0020, Perms=0x000C
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate x5, x1, x2

    li   x1, 463
    .insn i 0x0b, 0x5, x0, x1, 0   # veda.bind c0, x1  -- target/address capability

    # Object_ID=1 (veda_test_seed_odt's own permanent seed): a real,
    # ordinary tagged capability to attempt storing through the
    # misaligned target -- this test's own focus is the ALIGNMENT gate,
    # not the value being stored.
    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 0   # veda.bind c1, x1  -- value capability

    li   x5, 0
    .insn r 0x0b, 0x4, 0x01, x1, x0, x5   # ocs.c c0, x5(=0), c1  -- store through misaligned c0 -- must trap

    li   x20, 0xBAD                        # must NOT be reached
    j    done

trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0x08                          # (cap_idx=0<<5)|cause=0x08 (VEDA_CAUSE_ALIGNMENT_VIOLATION)
    bne  t3, t4, fail
    li   x20, 0x600D
    j    done

fail:
    li   x20, 0xDEAD

done:
    li   t2, 0x600D
    bne  x20, t2, real_fail
    RVMODEL_HALT_PASS
real_fail:
    RVMODEL_HALT_FAIL
