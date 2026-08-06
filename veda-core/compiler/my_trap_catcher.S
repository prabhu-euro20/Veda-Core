.section .text
.global my_trap_catcher_install
my_trap_catcher_install:
    la   t0, my_trap_catcher
    csrw mtvec, t0
    la   t0, g_trap_fired
    sw   x0, 0(t0)
    ret

.balign 4
my_trap_catcher:
    csrr t0, mcause
    la   t1, g_trap_mcause
    sd   t0, 0(t1)
    csrr t0, mtval
    la   t1, g_trap_mtval
    sd   t0, 0(t1)
    csrr t0, mepc
    la   t1, g_trap_mepc
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
.global g_trap_mtval
g_trap_mtval: .dword 0
.global g_trap_mepc
g_trap_mepc: .dword 0
