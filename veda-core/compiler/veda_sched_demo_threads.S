# Hand-written thread bodies for the C-API scheduler demo. MUST contain
# ZERO ordinary memory traffic -- Milestone 19's purecap rule blocks any
# ordinary load/store unconditionally inside a live, narrowly
# OCInvoke/OCRETURN-bound compartment, and (found empirically this
# session, clang -S inspection) even a trivial compiler-generated
# function's own callee-saved-register prologue spill would violate this
# -- which is exactly why these bodies are hand-written, not compiled C.
#
# Persistent state lives only in a dedicated GPR per thread (x20/x21),
# matching sail_tests/vc_scheduler_cooperative_yield.S's own established
# convention exactly: the register FILE itself survives every
# OCInvoke/OCRETURN compartment switch (only PCC narrows, GPRs are never
# cleared), so no explicit save/restore is needed for these counters at
# all -- they are read back directly by main() (in veda_sched_demo.c,
# ordinary unbounded C, once the scheduler has returned) via inline asm.
#
# Each function is far under its declared code_length (0x40, see
# veda_sched_demo.c) -- generously padded, not tightly measured, matching
# this project's own established convention (the original hand-assembled
# test also hand-picked a generous Length=0x0100 rather than computing an
# exact byte count).

.section .text

.balign 4
.global veda_demo_thread0
veda_demo_thread0:
    li   x20, 0
thread0_loop:
    addi x20, x20, 1
    ecall
    j    thread0_loop

.balign 4
.global veda_demo_thread1
veda_demo_thread1:
    li   x21, 0
thread1_loop:
    addi x21, x21, 1
    ecall
    j    thread1_loop
