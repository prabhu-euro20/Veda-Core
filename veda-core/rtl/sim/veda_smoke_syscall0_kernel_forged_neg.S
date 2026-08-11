.section .text
.global _start

# RTL Part D: mirrors Task #299's real Sail-side deliverable
# (compiler/veda_syscall0_kernel_entry_forged.S) -- the real security
# proof this whole clean-room-OS direction depends on. Reuses Part C's
# own KERNEL dispatcher UNCHANGED (do_sys_write/do_sys_exit/copy_loop/
# macros below are byte-for-byte identical to veda_smoke_syscall0_kernel.S
# -- this is the same real, unmodified kernel code path, matching the
# Sail source's own "reuse hello_world.c unchanged" philosophy), and
# changes only the CALLER's own request: compartment_u hands sys_write a
# deliberately forged, never-populated Object_ID (99999, matching the
# Sail side's own real value) instead of its real USER_MSG id (132).
#
# Expected outcome: do_sys_write's own FIRST instruction -- the
# trapping `veda.bind c3, a1` -- hard-traps (mcause=0x18,
# mtval=0x65 == cap_idx=3<<5 | cause=0x05 VEDA_CAUSE_OBJECT_NOT_FOUND)
# before the second bind (c4, KERNEL_CONSOLE_BUF) or the copy loop ever
# runs -- zero software-side validation anywhere in the syscall path,
# purely a hardware rejection. Proven two ways, mirroring this project's
# own "prove enforcement, not just state" discipline:
#   1. mepc points at the exact trapping instruction (not something
#      later) -- confirms this is really the very first thing
#      do_sys_write attempted.
#   2. KERNEL_CONSOLE_BUF's own real backing memory stays all-zero --
#      directly observable proof that no data movement ever happened,
#      not an inference from cause code alone.
#
# Object_IDs 130-134, identical to veda_smoke_syscall0_kernel.S (Part C)
# -- this file reuses that test's own scaffold exactly; 99999 (the
# forged id) is never populated by any veda.odt.populate anywhere in
# this file, by construction.

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
    csrw mscratch, t0               # one-time seed (M25/M26 idiom)

    la   t0, handler
    csrw mtvec, t0

    la   t0, user_msg_buf
    li   t1, 0x1122334455667788
    sd   t1, 0(t0)
    li   t1, 0x99AABBCCDDEEFF00
    sd   t1, 8(t0)

    la   t0, compartment_u
    slli t0, t0, 32
    li   t1, 0x00680402
    or   t0, t0, t1
    li   x1, 130
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    la   t0, type_authority_dummy
    slli t0, t0, 32
    li   t1, 0x00400300
    or   t0, t0, t1
    li   x1, 131
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    la   t0, user_msg_buf
    slli t0, t0, 32
    li   t1, 0x0040040C
    or   t0, t0, t1
    li   x1, 132
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    la   t0, kernel_save_area
    slli t0, t0, 32
    li   t1, 0x0100000C
    or   t0, t0, t1
    li   x1, 133
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    la   t0, kernel_console_buf
    slli t0, t0, 32
    li   t1, 0x0040000C
    or   t0, t0, t1
    li   x1, 134
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    li   x1, 130
    .insn i 0x0b, 0x5, x0, x1, 0    # veda.bind c0, x1 -- CODE
    li   x1, 132
    .insn i 0x0b, 0x5, x1, x1, 0    # veda.bind c1, x1 -- USER_MSG (the caller's own REAL object --
                                    # never actually named to the kernel below; deliberately not
                                    # what a1 will carry)
    li   x1, 131
    .insn i 0x0b, 0x5, x2, x1, 0    # veda.bind c2, x1 -- type-authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2   # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2   # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4   # ocinvoke c3, c4 -- narrows PCC to compartment_u

compartment_u:
    li   s1, 0xCAFEF00D              # canary -- irrelevant to the outcome here, kept for structural
                                     # parity with Part C's own compartment_u body

    # sys_write(fd=1, oid=<FORGED, never populated>, offset=0, count=16).
    # The one real change from Part C: a1 names an Object_ID the kernel
    # never populated anywhere -- the caller-supplied value the trapping
    # veda.bind inside do_sys_write below must reject.
    li   a0, 1
    li   a1, 99999
    li   a2, 0
    li   a3, 16
    li   a7, 64
    ecall
    # -- unreachable on the real (expected) path: the ecall traps into
    #    do_sys_write, which itself traps again on the forged bind and
    #    never mret's back here. Kept only for structural parity/as a
    #    real, deterministic FAILURE outcome if the forged id were ever
    #    (wrongly) accepted. --
    li   x22, 0xDEAD
    j    done

fail:
    li   x22, 0xDEAD
done:
1:
    j    1b

.balign 4
handler:
    csrr t3, mcause
    li   t4, 11                      # E_M_EnvCall
    beq  t3, t4, h_ecall
    li   t4, 0x18                    # Veda-Core's own cause -- the expected forged-bind rejection
    beq  t3, t4, h_bind_fault
    j    fail                        # unexpected trap cause

h_bind_fault:
    # -- the real security proof: confirm the exact cause/cap_idx AND
    #    that this fired from the exact expected instruction AND that
    #    the destination buffer's own real memory was never touched. --
    csrr x28, mtval
    li   x29, 0x65                   # cap_idx=3 (c3, do_sys_write's own trapping-bind target),
                                     # cause=0x05 (VEDA_CAUSE_OBJECT_NOT_FOUND)
    bne  x28, x29, fail

    csrr x28, mepc
    la   x29, do_sys_write_bind_attempt
    bne  x28, x29, fail             # must be the exact trapping instruction, not something later

    # KERNEL_CONSOLE_BUF's own real backing memory must still be
    # all-zero -- direct, observable proof the copy loop never ran
    # (the second bind, c4, and everything after it in do_sys_write is
    # unreached: this trap fires on do_sys_write's own FIRST instruction).
    la   x28, kernel_console_buf
    ld   x29, 0(x28)
    bnez x29, fail
    ld   x29, 8(x28)
    bnez x29, fail

    li   x21, 0x600D                 # sentinel: forged Object_ID correctly rejected in hardware,
                                     # before any data movement, zero software-side validation
    j    done

h_ecall:
    # ---- Full GPR save (x1-x31, x0 omitted) into KERNEL_SAVE_AREA ----
    # Byte-for-byte identical to Part C's own real kernel code, reused
    # unchanged.
    csrrw x5, mscratch, x5
    li    x5, 133
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
    .insn r 0x0b, 0x3, 0x01, x31, x2, x5

    li   x6, 64
    beq  a7, x6, do_sys_write
    li   x6, 93
    beq  a7, x6, do_sys_exit
    j    fail

do_sys_write:
    # -- the real, unmodified kernel code: bind the CALLER-SUPPLIED
    #    Object_ID (a1) into c3. THIS is the trapping instruction this
    #    whole test exists to exercise -- a1 carries the forged id, so
    #    this hard-traps HERE, before c4's own bind or the copy loop
    #    below are ever reached. --
do_sys_write_bind_attempt:
    .insn i 0x0b, 0x5, x3, a1, 0     # veda.bind c3, a1

    li   x6, 134
    .insn i 0x0b, 0x5, x4, x6, 0     # veda.bind c4, x6 -- KERNEL_CONSOLE_BUF

    mv   x7, x0
copy_loop:
    slli x28, x7, 3
    add  x29, a2, x28
    .insn r 0x0b, 0x3, 0x00, x30, x3, x29
    .insn r 0x0b, 0x3, 0x01, x30, x4, x28
    addi x7, x7, 1
    slli x6, x7, 3
    bltu x6, a3, copy_loop

    la   x6, kernel_console_buf
    ld   x7, 0(x6)
    li   x28, 0x1122334455667788
    bne  x7, x28, fail
    ld   x7, 8(x6)
    li   x28, 0x99AABBCCDDEEFF00
    bne  x7, x28, fail

    mv   a0, a3

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
    li   x22, 0xDEAD
    j    done
do_sys_exit_pass:
    li   x22, 0xDEAD                 # -- unreachable on the real path: sys_exit is never requested
                                     #    in this negative test. If somehow reached (the forged id was
                                     #    wrongly accepted and the whole round trip completed), that
                                     #    is itself a real FAILURE outcome, not a pass -- deliberately
                                     #    NOT x21=0x600D here (h_bind_fault above is the only place
                                     #    that sets the pass sentinel).
    j    done

.section .data
.align 4
user_msg_buf:
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
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

.align 4
type_authority_dummy:
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
    .dword 0
