# Toolchain Milestone 9 negative demo: real trap handler proving a
# deliberate out-of-bounds access through a compiler-generated OCL.D call
# genuinely hard-traps with the correct cause. Halts directly from the
# handler (RVMODEL_HALT_PASS/FAIL) -- the same real, established
# self-check convention every other trap test in this project uses (e.g.
# sail_tests/vc_odt_lifecycle.S), not a resume-and-continue pattern (no
# further C code needs to run afterward for this specific test).
#
# Expected real values, cross-checked against this project's own existing
# precedent (MILESTONE_18_RESULTS.md, already cited in
# TOOLCHAIN_MILESTONE_8_RESULTS.md's own header comment): mcause=0x18
# (E_Extension, veda_trap()'s own real trap class) and mtval=0x21 -- the
# runtime's fixed scratch capability register is c1 (index 1, see
# runtime/veda_rt_asm.S), and veda_bind_insts.sail's own real
# veda_xtval(cap_idx,cause) packs mtval = (cap_idx<<5)|cause, so a real
# Bounds Violation (cause=0x01) via c1 gives (1<<5)|0x01 = 0x21 exactly.

# Real RVMODEL_HALT_PASS/FAIL bodies inlined directly (not `.include`d from
# veda_selfcheck_macros.S) -- that shared file also defines the `tohost`/
# `fromhost` .tohost-section globals, which crt0.S (linked into the same
# binary) already provides; including it a second time here would produce
# a real duplicate-symbol link error. `tohost` is referenced here as an
# external symbol instead, same real values/protocol either way.
.extern tohost

.section .text
.global veda_demo_install_trap_handler
veda_demo_install_trap_handler:
    la   t0, veda_demo_trap_handler
    csrw mtvec, t0
    ret

.balign 4
veda_demo_trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, demo_trap_fail
    csrr t3, mtval
    li   t4, 0x21
    bne  t3, t4, demo_trap_fail
    li   x1, 1
    la   t0, tohost
    sw   x1, 0(t0)
    sw   x0, 4(t0)
    j    .
demo_trap_fail:
    li   x1, 3
    la   t0, tohost
    sw   x1, 0(t0)
    sw   x0, 4(t0)
    j    .
