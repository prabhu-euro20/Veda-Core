.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # R21 fix (rtl/veda_core.tlv, $veda_dram_stall_req): a DRAM-tier
    # OCL.C/OCS.C access that ALSO violates (bounds/perm/tag/seal, or a
    # plain Bind's own ODT-miss/wrong-owner) used to still fire the
    # DRAM-latency stall request -- the stall drives $veda_dram_busy,
    # which the $pc mux ranks ABOVE the trap redirect, discarding it
    # while trap STATE effects still fire. Found independently on the
    # Linux line's own fork of this same Milestone 24 mechanism,
    # confirmed still live here by direct re-derivation of this core's
    # real trap terms (not copied from that fork -- this core has no
    # domain/region concepts, so the fix shape differs).
    #
    # This test uses Object_ID=1, a reset-seeded object
    # (Base=0x80010000, Length=0x40, Perms=0x100C) -- real DRAM tier
    # (nowhere near TCM_SCRATCH_BASE=0xA000_0000, so this is always a
    # real TCM miss) and a deliberate offset of 1000, far past
    # Length=0x40, a real bounds violation.
    #
    # At the shipped DRAM_EXTRA_CYCLES=0 default this test's job is to
    # confirm the violation still traps correctly (x20 reaches 0x600D,
    # never 0xE5CA) -- the stall path is structurally unreachable at
    # E=0 (matches every other Milestone 24 test's own "busy stays 0"
    # convention), so this alone does not exercise R21 itself. The real
    # escape reproduction (pre-fix) and fix confirmation (post-fix) at
    # a temporarily nonzero DRAM_EXTRA_CYCLES is a separate,
    # non-committed verification pass -- see
    # MILESTONE_R21_DRAM_STALL_TRAP_FIX_RESULTS.md for both real runs.
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    li   x1, 1
    .insn i 0x0b, 0x5, x1, x1, 0          # veda.bind c1, x1  (Object_ID=1: Base=0x80010000 Length=0x40 Perms=0x100C)

    li   x20, 0xDEAD                       # sentinel: neither escaped nor trapped yet

    li   t3, 1000                          # offset 1000 >> Length=0x40 -- real bounds violation, real DRAM-tier address
    .insn r 0x0b, 0x4, 0x00, x0, x1, t3    # ocl.c c1, t3, c0  -- must hard-trap, not fall through

    li   x20, 0xE5CA                       # ESCAPED marker -- must NEVER be reached if the trap fired
    j    done

trap_handler:
    csrr t4, mcause
    li   t5, 0x18                          # Veda-Core's own umbrella cause
    bne  t4, t5, fail

    li   x20, 0x600D                       # sentinel: correctly trapped, no escape

    la   t4, recovery
    csrw mepc, t4
    mret

recovery:
    j    done

fail:
    li   x20, 0xBAD

done:
1:
    j 1b
