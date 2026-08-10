.include "../sail_tests/veda_selfcheck_macros.S"
.section .text
.global _start

# Toolchain Milestone "Syscall-0" Step 2 (task #298): hand-written
# compartment-entry point for a REAL, compiled C program
# (veda_syscall0_hello_world.c) that issues real write()/exit() syscalls.
# Bootstrap+OCInvoke ceremony mirrors veda_alloca_protect_entry.S
# (Toolchain Milestone 12) field-for-field -- the closest real precedent
# for "OCInvoke into a compiled C function with its own local variables"
# (SSC establishment). The mtvec-installed handler below is NOT the
# M12-style purecap-violation catcher those demos use -- it is Task
# #297's own proven KERNEL ecall dispatcher (sail_tests/vc_syscall0_kernel.S,
# 65/65 regression), reused verbatim: the dispatch/full-GPR-save/
# sys_write/sys_exit logic is trap-source-agnostic and identically correct
# regardless of which compartment ceremony narrowed PCC beforehand.
#
# Object_IDs 460-467, grep-audited fresh against every existing
# "li x1, N" Object_ID literal across the whole repo before picking
# (highest prior use: 454, sail_tests/vc_syscall0_kernel.S).
#   460 = hello_world_thread CODE (Execute|Invoke)
#   461 = OCInvoke DATA-role placeholder (Invoke only -- hello_world_thread
#         never uses c15/IDC for anything; this object exists purely to
#         satisfy OCInvoke's own cs2 operand requirement)
#   462 = type-authority (Seal|Unseal)
#   463 = STACK_REGION (SSC, Load|Store, Length=0x1000 matching
#         kVedaSSCRegionLength in VedaShadowPropagation.cpp)
#   464 = KERNEL_SAVE_AREA (full-GPR-save backing store, Task #297's design)
#   465 = KERNEL_CONSOLE_BUF (sys_write's real destination)

.macro SAVE_REG regnum, off
    li   x5, \off
    .insn r 0x0b, 0x3, 0x01, x\regnum, x2, x5   # ocs.d c2, x5(offset), x\regnum(value)
.endm
.macro REST_REG regnum, off
    li   x5, \off
    .insn r 0x0b, 0x3, 0x00, x\regnum, x2, x5   # ocl.d c2, x5(offset), x\regnum(dest)
.endm

_start:
    li   t0, 0
    csrw mscratch, t0               # one-time seed (M25 idiom)

    la   t0, kernel_handler
    csrw mtvec, t0

    la   sp, _stack_top

    # -- veda_rt_init + veda_malloc_raw, PRE-OCInvoke. Real, empirically-
    #    found requirement: veda_compiler_rt.c/runtime/veda_rt.c are
    #    compiled WITHOUT -fpass-plugin in every established build script
    #    in this repo -- their own internal bookkeeping (g_in_use[]/etc.)
    #    is always ordinary, un-instrumented C. Calling veda_malloc_raw
    #    from INSIDE hello_world_thread (post-OCInvoke) hit a real
    #    PURECAP_VIOLATION (cause=0x07) on veda_rt_init's own ordinary
    #    `sb` bookkeeping write, confirmed via --trace-instr before this
    #    fix. Mirrors veda_global_protect_entry.S's own already-
    #    established pre-OCInvoke veda_rt_init_globals() call, for the
    #    identical real reason ("purecap enforcement is not yet active at
    #    that point"). --
    li   a0, 64
    li   a1, 12
    call veda_rt_init

    li   a0, 16
    la   a1, msg_oid_scratch
    call veda_malloc_raw
    la   t0, msg_oid_scratch
    lw   s1, 0(t0)                  # s1 := real Object_ID -- callee-saved,
                                    # kept alive through the whole ceremony
                                    # below (nothing else here touches s1)
                                    # until `call hello_world_thread`.

    # -- write the real message bytes via a real, hardware-checked OCS.D
    #    round trip (works regardless of PCC bounds state -- OCS.D only
    #    cares about the CAPABILITY's own bounds/perms, not PCC). Two
    #    dwords, computed precisely (not hand-encoded) for
    #    "Hello, world!\n" (14 bytes, little-endian, zero-padded to 16). --
    mv   x1, s1
    .insn i 0x0b, 0x5, x5, x1, 0    # veda.bind c5, x1(=msg Object_ID)
    li   x6, 0
    li   t3, 0x77202C6F6C6C6548     # "Hello, w"
    .insn r 0x0b, 0x3, 0x01, t3, x5, x6   # ocs.d c5, x6(=0), t3(value)
    li   x6, 8
    li   t3, 0x00000A21646C726F     # "orld!\n" + 2 zero pad bytes
    .insn r 0x0b, 0x3, 0x01, t3, x5, x6   # ocs.d c5, x6(=8), t3(value)

    # -- ODT-Populate: hello_world_thread CODE (460). Length=0x1000,
    #    comfortably covers a real compiled function that calls external,
    #    separately-linked helpers (veda_rt_init/veda_malloc_raw/
    #    sys_write/sys_exit) -- matching veda_alloca_protect_entry.S's own
    #    already-empirically-justified choice for the identical reason. --
    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x10000402
    or   t0, t0, t1
    li   x1, 460
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- ODT-Populate: OCInvoke DATA-role placeholder (461), Invoke only --
    la   t0, dummy_data_region
    slli t0, t0, 32
    li   t1, 0x00400400
    or   t0, t0, t1
    li   x1, 461
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- ODT-Populate: type-authority (462) --
    la   t0, dummy_type_authority
    slli t0, t0, 32
    li   t1, 0x00400300
    or   t0, t0, t1
    li   x1, 462
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- ODT-Populate: KERNEL_SAVE_AREA (464), Load|Store -- must exist
    #    BEFORE the first ecall, since h_ecall binds it unconditionally on
    #    every entry. --
    la   t0, kernel_save_area
    slli t0, t0, 32
    li   t1, 0x0100000C
    or   t0, t0, t1
    li   x1, 464
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- ODT-Populate: KERNEL_CONSOLE_BUF (465), Load|Store --
    la   t0, kernel_console_buf
    slli t0, t0, 32
    li   t1, 0x0040000C
    or   t0, t0, t1
    li   x1, 465
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    li   x1, 460
    .insn i 0x0b, 0x5, x0, x1, 0    # veda.bind c0, x1 -- CODE
    li   x1, 461
    .insn i 0x0b, 0x5, x1, x1, 0    # veda.bind c1, x1 -- DATA-role placeholder
    li   x1, 462
    .insn i 0x0b, 0x5, x2, x1, 0    # veda.bind c2, x1 -- type-authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2   # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2   # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4   # ocinvoke c3, c4

landing_pad:
    # -- Establish SSC (identical ceremony to veda_alloca_protect_entry.S) --
    la   t0, _stack_top
    addi t0, t0, -0x800
    slli t0, t0, 32
    li   t1, 0x1000000C   # Length=0x1000, Perms=Load|Store
    or   t0, t0, t1
    li   x1, 463
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2   # veda.odt.populate -- STACK_REGION
    li   x1, 463
    .insn i 0x0b, 0x5, x15, x1, 0   # veda.bind c15, x1
    .insn r 0x5b, 0x1, 0x13, x14, x15, x2   # ospecialrw c14(discard-old), ssc, c15

    li   sp, 0x1000   # logical, region-relative

    mv   a0, s1        # a0 = real Object_ID -- hello_world_thread's only
                       # (scalar, non-pointer) parameter
    call hello_world_thread

    # -- Unreachable on the real, expected path: hello_world_thread's own
    #    sys_exit() halts the simulator directly (Task #297's do_sys_exit,
    #    reused verbatim below) and never returns here. A defensive-only
    #    fallback, matching this project's own established convention for
    #    "should never execute" paths. --
    j    fail

fail:
    RVMODEL_HALT_FAIL

.balign 4
kernel_handler:
    # ==== Task #297's proven KERNEL ecall dispatcher, reused verbatim ====
    csrr t3, mcause
    li   t4, 11                      # E_M_EnvCall -- the only trap cause this file expects
    beq  t3, t4, h_ecall
    j    fail                        # unexpected trap cause

h_ecall:
    csrrw x5, mscratch, x5           # free x5 (true value now parked in mscratch)
    li    x5, 464
    .insn i 0x0b, 0x5, x2, x5, 0     # veda.bind c2, x5 -- KERNEL_SAVE_AREA

    SAVE_REG 1, 0
    SAVE_REG 2, 8
    SAVE_REG 3, 16
    SAVE_REG 4, 24
    SAVE_REG 6, 40
    SAVE_REG 7, 48
    SAVE_REG 8, 56
    SAVE_REG 9, 64
    SAVE_REG 10, 72
    SAVE_REG 11, 80
    SAVE_REG 12, 88
    SAVE_REG 13, 96
    SAVE_REG 14, 104
    SAVE_REG 15, 112
    SAVE_REG 16, 120
    SAVE_REG 17, 128
    SAVE_REG 18, 136
    SAVE_REG 19, 144
    SAVE_REG 20, 152
    SAVE_REG 21, 160
    SAVE_REG 22, 168
    SAVE_REG 23, 176
    SAVE_REG 24, 184
    SAVE_REG 25, 192
    SAVE_REG 26, 200
    SAVE_REG 27, 208
    SAVE_REG 28, 216
    SAVE_REG 29, 224
    SAVE_REG 30, 232
    SAVE_REG 31, 240

    csrr  x31, mscratch
    li    x5, 32
    .insn r 0x0b, 0x3, 0x01, x31, x2, x5   # ocs.d c2, x5(=32), x31(=x5's true value)

    li   x6, 64
    beq  a7, x6, do_sys_write
    li   x6, 93
    beq  a7, x6, do_sys_exit
    j    fail

do_sys_write:
    .insn i 0x0b, 0x5, x3, a1, 0     # veda.bind c3, a1 -- TRAPPING bind on
                                     # the CALLER-SUPPLIED Object_ID

    li   x6, 465
    .insn i 0x0b, 0x5, x4, x6, 0     # veda.bind c4, x6 -- KERNEL_CONSOLE_BUF

    mv   x7, x0
copy_loop:
    slli x28, x7, 3
    add  x29, a2, x28
    .insn r 0x0b, 0x3, 0x00, x30, x3, x29   # ocl.d c3, x29(offset), x30(dest)
    .insn r 0x0b, 0x3, 0x01, x30, x4, x28   # ocs.d c4, x28(offset), x30(value)
    addi x7, x7, 1
    slli x6, x7, 3
    bltu x6, a3, copy_loop

    # -- self-check: KERNEL_CONSOLE_BUF now holds hello_world's real
    #    message bytes, verified via an ORDINARY load from raw M-mode
    #    context (legal here -- purecap mode off, PCC unbounded, before
    #    mret). Matches the exact literals the entry point itself wrote
    #    into the source object pre-OCInvoke. --
    la   x6, kernel_console_buf
    ld   x7, 0(x6)
    li   x28, 0x77202C6F6C6C6548
    bne  x7, x28, fail
    ld   x7, 8(x6)
    li   x28, 0x00000A21646C726F
    bne  x7, x28, fail

    mv   a0, a3                      # return value: bytes written = count

    REST_REG 1, 0
    REST_REG 2, 8
    REST_REG 3, 16
    REST_REG 4, 24
    REST_REG 6, 40
    REST_REG 7, 48
    REST_REG 8, 56
    REST_REG 9, 64
    REST_REG 11, 80
    REST_REG 12, 88
    REST_REG 13, 96
    REST_REG 14, 104
    REST_REG 15, 112
    REST_REG 16, 120
    REST_REG 17, 128
    REST_REG 18, 136
    REST_REG 19, 144
    REST_REG 20, 152
    REST_REG 21, 160
    REST_REG 22, 168
    REST_REG 23, 176
    REST_REG 24, 184
    REST_REG 25, 192
    REST_REG 26, 200
    REST_REG 27, 208
    REST_REG 28, 216
    REST_REG 29, 224
    REST_REG 30, 232
    REST_REG 31, 240

    li   x5, 32
    .insn r 0x0b, 0x3, 0x00, x5, x2, x5

    csrr x6, mepc
    addi x6, x6, 4
    csrw mepc, x6
    mret

do_sys_exit:
    beqz a0, do_sys_exit_pass
    RVMODEL_HALT_FAIL
do_sys_exit_pass:
    RVMODEL_HALT_PASS

.section .data
.align 4
msg_oid_scratch:
    .word 0

.align 4
dummy_data_region:
    .dword 0
    .dword 0

.align 4
dummy_type_authority:
    .dword 0
    .dword 0

.align 4
kernel_save_area:
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0

.align 4
kernel_console_buf:
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
# _stack_top is provided by runtime/veda_rt.ld itself (_end + 0x10000,
# a real, already-generous 64KiB region) -- matching every other
# compiler/ entry point's own convention (none define it locally).
