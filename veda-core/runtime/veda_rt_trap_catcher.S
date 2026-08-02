# Real trap-catch-and-RESUME helper for veda_rt_retire_neg_test.c's own
# direct hardware probe. Every existing self-check test's own trap handler
# (sail_tests/vc_*.S) halts permanently from inside the handler -- reaching
# the handler correctly IS their terminal pass condition. This test needs
# something those don't: catch one specific expected hard trap, record it,
# and RESUME normal execution afterward so main() can keep running and
# return a real pass/fail code through the normal crt0 flow.
#
# mepc+4 skips exactly the one faulting instruction (Custom-0 opcode
# 0b0001011 has opcode[1:0]==11, a real, standard-width 32-bit RISC-V
# instruction, matching every existing self-check test's own identical
# `addi t3,t3,4`-style skip). Real, standard `mret` semantics (RISC-V
# Privileged ISA) then resume execution there -- which lands exactly on
# the calling convention's own `ret` inside
# veda_odt_populate_fast_asm (veda_rt_asm.S), so the C call that
# deliberately triggered the trap returns to its caller completely
# normally, `ra` never having been disturbed.

.section .text
.global veda_rt_trap_catcher_install
veda_rt_trap_catcher_install:
    la   t0, veda_rt_trap_catcher
    csrw mtvec, t0
    la   t0, g_trap_fired
    sw   x0, 0(t0)
    ret

.balign 4
veda_rt_trap_catcher:
    csrr t0, mcause
    la   t1, g_trap_mcause
    sd   t0, 0(t1)
    li   t0, 1
    la   t1, g_trap_fired
    sw   t0, 0(t1)
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret

.section .bss
.balign 8
.global g_trap_fired
g_trap_fired: .word 0
.global g_trap_mcause
g_trap_mcause: .dword 0
