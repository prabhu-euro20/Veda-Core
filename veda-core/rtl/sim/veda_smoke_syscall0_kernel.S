.section .text
.global _start

# RTL Part C: mirrors Task #297's real Sail-side deliverable
# (sail_tests/vc_syscall0_kernel.S) -- a real, dispatching KERNEL ecall
# handler with two real Linux syscall NUMBERS (__NR_write=64,
# __NR_exit=93), a caller-supplied {Object_ID, offset} pair (a1/a2)
# replacing the raw pointer real Linux would use for `buf` (this ISA has
# no raw pointers, so the kernel validates the caller's own Object_ID via
# a real, TRAPPING veda.bind rather than trusting a raw address), and a
# full GPR save/restore around the handler body (the M25/M26 idiom,
# already RTL-proven in veda_smoke_m23_scheduler.S, scoped down here:
# this handler always mret's back to the SAME interrupted context, no
# thread-resume-jump machinery). Depends on BOTH RTL prerequisite mirrors
# built earlier in this same plan: M21-restore (Part A, so compartment_u
# resumes correctly bounded after sys_write's own mret without any
# explicit software restore) and M27-mtvec-gate (Part B, unrelated to
# this test's own behavior but proves the same veda_core.tlv revision).
#
# RTL harness convention (this project's own established pattern, not
# tohost/HTIF): the sys_exit halt becomes "write a sentinel GPR and
# spin" (x21=0x600D pass, x22=0xDEAD fail) instead of RVMODEL_HALT_PASS/
# FAIL. One real simplification this enables over the Sail source: an
# RTL `li x22,0xDEAD` is a register-only op (not a memory store), so
# unlike the Sail version's own documented two-hop PURECAP_VIOLATION
# path (RVMODEL_HALT_FAIL's own `sw`), taking a direct `bne ...,fail`
# from inside the still-narrow compartment does NOT itself trap on
# purecap grounds -- it only needs `fail:`'s own address to lie inside
# compartment_u's Length window, exactly the same fetch-bounds concern
# already handled (via objdump) for every other narrow-compartment test
# in this file set.
#
# Object_IDs 130-134, grep-audited fresh against every existing
# rtl/sim/*.S Object_ID literal before picking (100-102/110-123/140-152
# are the only ones in use; 130-134 is a clean, unused block within the
# already-established 100-199 free range -- this is the exact block the
# approved plan reserved for this test).
#   130 = compartment_u CODE (Execute|Invoke)
#   131 = type-authority (Seal|Unseal)
#   132 = USER_MSG -- doubles as OCInvoke's DATA-role object (Load|Store|
#         Invoke). This is the object sys_write's caller-supplied
#         Object_ID (a1) names -- the real point of this milestone: the
#         kernel validates it via hardware (veda.bind, trapping), never
#         trusting it blindly.
#   133 = KERNEL_SAVE_AREA (Load|Store) -- the full-GPR-save backing store.
#   134 = KERNEL_CONSOLE_BUF (Load|Store) -- sys_write's real destination
#         (a real, kernel-owned scratch object, matching the Sail side's
#         own honest "no real console device" scope limit).

# SAVE_REG/REST_REG: OCS.D/OCL.D through c2 (KERNEL_SAVE_AREA), using x5
# as the shared per-iteration offset scratch -- identical macro shape to
# the Sail source, and the same primitive already RTL-proven in
# veda_smoke_m23_scheduler.S's own switcher_entry.
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

    # -- populate USER_MSG's real content BEFORE narrowing (ordinary
    #    store: legal here, PCC still unbounded). A real, distinctive,
    #    non-zero, non-repeating pattern -- guards against a copy-loop-
    #    does-nothing bug silently "passing" against an all-zero
    #    expectation. --
    la   t0, user_msg_buf
    li   t1, 0x1122334455667788
    sd   t1, 0(t0)
    li   t1, 0x99AABBCCDDEEFF00
    sd   t1, 8(t0)

    # -- ODT-Populate: compartment_u CODE (130). Length=0x0068 --
    #    objdump-confirmed: the real minimum needed (straight-line
    #    execution through the sys_exit-request ecall, the last
    #    instruction fetched on the PASS path) is 0x4f; 0x68 is a
    #    generous, comfortable margin (also covers fail:'s own body),
    #    matching the Sail source's own "Length is set generously and
    #    will be confirmed, not assumed" choice, not a tightly-computed
    #    boundary value -- this test proves a positive round trip, not
    #    an exact escape boundary. --
    la   t0, compartment_u
    slli t0, t0, 32
    li   t1, 0x00680402
    or   t0, t0, t1
    li   x1, 130
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- ODT-Populate: type-authority (131). --
    la   t0, type_authority_dummy
    slli t0, t0, 32
    li   t1, 0x00400300
    or   t0, t0, t1
    li   x1, 131
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- ODT-Populate: USER_MSG (132), Load|Store|Invoke --
    la   t0, user_msg_buf
    slli t0, t0, 32
    li   t1, 0x0040040C
    or   t0, t0, t1
    li   x1, 132
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- ODT-Populate: KERNEL_SAVE_AREA (133), Load|Store --
    la   t0, kernel_save_area
    slli t0, t0, 32
    li   t1, 0x0100000C
    or   t0, t0, t1
    li   x1, 133
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- ODT-Populate: KERNEL_CONSOLE_BUF (134), Load|Store --
    la   t0, kernel_console_buf
    slli t0, t0, 32
    li   t1, 0x0040000C
    or   t0, t0, t1
    li   x1, 134
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- bind + cseal + ocinvoke ceremony --
    li   x1, 130
    .insn i 0x0b, 0x5, x0, x1, 0    # veda.bind c0, x1 -- CODE
    li   x1, 132
    .insn i 0x0b, 0x5, x1, x1, 0    # veda.bind c1, x1 -- USER_MSG (DATA role)
    li   x1, 131
    .insn i 0x0b, 0x5, x2, x1, 0    # veda.bind c2, x1 -- type-authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2   # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2   # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4   # ocinvoke c3, c4 -- narrows PCC to compartment_u

compartment_u:
    li   s1, 0xCAFEF00D              # canary -- must survive BOTH ecalls below

    # sys_write(fd=1, oid=USER_MSG(132), offset=0, count=16). ABI:
    # a0=fd, a1=Object_ID, a2=offset, a3=count, a7=64.
    li   a0, 1
    li   a1, 132
    li   a2, 0
    li   a3, 16
    li   a7, 64
    ecall
    # -- resumed here via mret; RTL M21-restore mirror (Part A) has
    #    already restored veda_pcc_base/_length back to compartment_u's
    #    own real bounds by the time this fetches -- a0 holds the real
    #    write()-convention return value (bytes written = count). --
    li   t3, 16
    bne  a0, t3, fail

    li   t3, 0xCAFEF00D
    bne  s1, t3, fail                # canary must have survived the full sys_write round trip

    # sys_exit(0) -- never returns on the pass path.
    li   a0, 0
    li   a7, 93
    ecall
    j    fail                        # unreachable if sys_exit correctly halted

fail:
    li   x22, 0xDEAD
done:
1:
    j    1b

.balign 4
handler:
    csrr t3, mcause
    li   t4, 11                      # E_M_EnvCall -- the only trap cause this file expects
    beq  t3, t4, h_ecall
    j    fail                        # unexpected trap cause

h_ecall:
    # ---- Full GPR save (x1-x31, x0 omitted) into KERNEL_SAVE_AREA ----
    csrrw x5, mscratch, x5           # free x5 (true value now parked in mscratch)
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
    .insn r 0x0b, 0x3, 0x01, x31, x2, x5   # ocs.d c2, x5(=32), x31(=x5's true value)

    # ---- Dispatch on a7 (real Linux syscall numbers) ----
    li   x6, 64
    beq  a7, x6, do_sys_write
    li   x6, 93
    beq  a7, x6, do_sys_exit
    j    fail                        # unrecognized syscall

do_sys_write:
    # Bind the CALLER-SUPPLIED Object_ID (a1) into c3 -- TRAPPING
    # veda.bind: hardware validates existence + ownership atomically. A
    # forged Object_ID hard-traps HERE, never reaching the copy loop
    # below -- the real security property this milestone exists to
    # prove (Task #299's own RTL parity is a natural follow-on, not
    # required here).
    .insn i 0x0b, 0x5, x3, a1, 0     # veda.bind c3, a1

    li   x6, 134
    .insn i 0x0b, 0x5, x4, x6, 0     # veda.bind c4, x6 -- KERNEL_CONSOLE_BUF (fixed, kernel-known)

    # Dword-granular copy loop (OCL.D/OCS.D move exactly 8 bytes per
    # access on RV64). Copies ceil(count/8) dwords.
    mv   x7, x0                      # i = 0 (dword index)
copy_loop:
    slli x28, x7, 3                  # x28 = i*8
    add  x29, a2, x28                # source offset = a2 + i*8
    .insn r 0x0b, 0x3, 0x00, x30, x3, x29   # ocl.d c3, x29(offset), x30(dest)
    .insn r 0x0b, 0x3, 0x01, x30, x4, x28   # ocs.d c4, x28(offset), x30(value)
    addi x7, x7, 1
    slli x6, x7, 3                   # bytes copied so far
    bltu x6, a3, copy_loop

    # -- self-check: KERNEL_CONSOLE_BUF now holds the real message bytes,
    #    verified via an ORDINARY load from M-mode context (PCC already
    #    unbounded here, per M21-restore's own trap-time reset). --
    la   x6, kernel_console_buf
    ld   x7, 0(x6)
    li   x28, 0x1122334455667788
    bne  x7, x28, fail
    ld   x7, 8(x6)
    li   x28, 0x99AABBCCDDEEFF00
    bne  x7, x28, fail

    mv   a0, a3                      # return value: bytes written = count

    # ---- Full GPR restore ---- (a0 deliberately excluded: return value)
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
    .insn r 0x0b, 0x3, 0x00, x5, x2, x5   # x5's own restore (self-referential, safe by construction)

    csrr x6, mepc
    addi x6, x6, 4
    csrw mepc, x6
    mret

do_sys_exit:
    # ABI: a0=status, a7=93. RTL harness convention: never returns on the
    # pass path -- writes the shared sentinel and spins (no tohost here).
    beqz a0, do_sys_exit_pass
    li   x22, 0xDEAD
    j    done
do_sys_exit_pass:
    li   x21, 0x600D                 # sentinel: full sys_write + sys_exit round trip, all correct
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
