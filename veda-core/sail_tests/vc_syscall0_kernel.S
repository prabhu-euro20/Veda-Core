.include "veda_selfcheck_macros.S"
.section .text
.global _start

# Syscall-0 Step 1 (jolly-leaping-lark.md, approved plan): the KERNEL side
# of a real, dispatching ecall handler -- two real Linux syscall NUMBERS
# (__NR_write=64, __NR_exit=93), a caller-supplied {Object_ID, offset}
# pair (a1/a2) replacing the raw pointer real Linux would use for `buf`
# (this ISA has no raw pointers), and a full GPR save/restore around the
# handler body (the M25/M26 idiom, scoped down: no thread-resume-jump
# machinery, since this handler always returns to the SAME interrupted
# context via plain mepc+mret, unlike a real thread switch).
#
# Builds directly on Step 0 (vc_syscall0_step0_spike.S), which proved a
# syscall-shaped ecall composes correctly with M21-restore's PCC
# auto-restore-on-mret. That file's own real, objdump-confirmed lesson
# (compartment_u's own Length must cover its own post-ecall check code,
# not just its pre-ecall body) is reapplied here: Length is set generously
# and will be confirmed, not assumed.
#
# Object_IDs 450-454, grep-audited fresh against every existing
# `veda-core/**/*.S` literal before picking (highest prior use: 448,
# veda-core/compiler/veda_struct_array_global_entry.S).
#   450 = compartment_u CODE (Execute|Invoke)
#   451 = type-authority (Seal|Unseal)
#   452 = USER_MSG -- doubles as OCInvoke's DATA-role object (Load|Store|
#         Invoke), matching veda_sched_asm.S's own established "cut setup
#         from N objects to fewer when a role genuinely doubles" pattern.
#         This is the object sys_write's caller-supplied Object_ID (a1)
#         names -- the real point of this milestone: the kernel validates
#         it via hardware (`veda.bind`, trapping), never trusting it blindly.
#   453 = KERNEL_SAVE_AREA (Load|Store) -- the full-GPR-save backing store.
#   454 = KERNEL_CONSOLE_BUF (Load|Store) -- sys_write's real destination.
#         A real, honest scope limit: this milestone explicitly defers "a
#         real console I/O device" (TOOLCHAIN_MILESTONE_20_KERNEL_GAPS_
#         RESULTS.md), so sys_write's data movement is proven against a
#         real, kernel-owned scratch object instead of a device that
#         doesn't exist -- not hidden, named here and in the results doc.

# SAVE_REG/REST_REG: OCS.D/OCL.D through c2 (KERNEL_SAVE_AREA), using x5
# as the shared per-iteration offset scratch. x5 itself is handled
# specially (see h_ecall) -- these macros are never invoked with regnum=5.
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

    la   t0, handler
    csrw mtvec, t0

    # -- populate USER_MSG's real content BEFORE narrowing (ordinary
    #    store: legal here, PCC still unbounded, purecap mode off by
    #    default -- vc_purecap_reset_default_off already confirms this).
    #    A real, distinctive, non-zero, non-repeating pattern -- guards
    #    against a copy-loop-does-nothing bug silently "passing" against
    #    an all-zero expectation. --
    la   t0, user_msg_buf
    li   t1, 0x1122334455667788
    sd   t1, 0(t0)
    li   t1, 0x99AABBCCDDEEFF00
    sd   t1, 8(t0)

    # -- ODT-Populate: compartment_u CODE (450). Length=0x80, generous --
    #    confirmed sufficient via objdump after assembly (Step 0's own
    #    lesson: never assume a hand-counted instruction length). --
    la   t0, compartment_u
    slli t0, t0, 32
    li   t1, 0x00800402
    or   t0, t0, t1
    li   x1, 450
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- ODT-Populate: type-authority (451). Base is a real, owned dummy
    #    object -- never actually dereferenced (CSeal/CUnseal only check
    #    Perms and otype identity, per VEDA_CORE_SPEC.md Section 1), but
    #    pointed at real backing memory rather than an arbitrary literal
    #    for consistency with every other object here. --
    la   t0, type_authority_dummy
    slli t0, t0, 32
    li   t1, 0x00400300
    or   t0, t0, t1
    li   x1, 451
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- ODT-Populate: USER_MSG (452), Load|Store|Invoke --
    la   t0, user_msg_buf
    slli t0, t0, 32
    li   t1, 0x0040040C
    or   t0, t0, t1
    li   x1, 452
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- ODT-Populate: KERNEL_SAVE_AREA (453), Load|Store --
    la   t0, kernel_save_area
    slli t0, t0, 32
    li   t1, 0x0100000C
    or   t0, t0, t1
    li   x1, 453
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- ODT-Populate: KERNEL_CONSOLE_BUF (454), Load|Store --
    la   t0, kernel_console_buf
    slli t0, t0, 32
    li   t1, 0x0040000C
    or   t0, t0, t1
    li   x1, 454
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2

    # -- bind + cseal + ocinvoke ceremony (identical shape to Step 0) --
    li   x1, 450
    .insn i 0x0b, 0x5, x0, x1, 0    # veda.bind c0, x1 -- CODE
    li   x1, 452
    .insn i 0x0b, 0x5, x1, x1, 0    # veda.bind c1, x1 -- USER_MSG (DATA role)
    li   x1, 451
    .insn i 0x0b, 0x5, x2, x1, 0    # veda.bind c2, x1 -- type-authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2   # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2   # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4   # ocinvoke c3, c4 -- narrows PCC to compartment_u

compartment_u:
    li   s1, 0xCAFEF00D              # canary -- must survive BOTH ecalls below

    # sys_write(fd=1, oid=USER_MSG(452), offset=0, count=16). ABI:
    # a0=fd, a1=Object_ID, a2=offset, a3=count, a7=64 -- a deliberate
    # divergence from real Linux's a0-a2-only layout (buf is one raw
    # pointer there; here it is two registers, since there is no raw
    # pointer to begin with), matching this milestone's own already-
    # agreed, NOT-binary-compatible design.
    li   a0, 1
    li   a1, 452
    li   a2, 0
    li   a3, 16
    li   a7, 64
    ecall
    # -- resumed here via mret; a0 holds the real write()-convention
    #    return value (bytes written = count). --
    li   t3, 16
    bne  a0, t3, fail

    li   t3, 0xCAFEF00D
    bne  s1, t3, fail                # canary must have survived the full sys_write round trip

    # sys_exit(0) -- halts the simulator directly via RVMODEL_HALT_PASS/
    # FAIL (this milestone's own real, honest exit mechanism -- "real
    # per-process exit semantics" stays explicitly deferred); never
    # returns, so no mret/GPR-restore is needed on this path.
    li   a0, 0
    li   a7, 93
    ecall
    j    fail                        # unreachable if sys_exit correctly halted

fail:
    # -- Note: `fail:` sits within compartment_u's own generous Length
    #    (0x80) window. A `bne ...,fail` taken from INSIDE the compartment
    #    reaches this label with PCC still narrowed, so this macro's own
    #    ordinary `sw` genuinely trips a real PURECAP_VIOLATION trap
    #    (cause=0x07) instead of halting directly -- `handler:`'s own
    #    catch-all `j fail` then re-enters this same label from M-mode
    #    (PCC reset-to-unbounded by that trap), where the store succeeds
    #    and the simulator correctly reports FAILURE. A real, observed,
    #    two-hop path -- confirmed via --trace-exception, not assumed --
    #    but still a correct, deterministic FAILURE outcome either way. --
    RVMODEL_HALT_FAIL

.balign 4
handler:
    csrr t3, mcause
    li   t4, 11                      # E_M_EnvCall -- the only trap cause this file expects
    beq  t3, t4, h_ecall
    j    fail                        # unexpected trap cause

h_ecall:
    # ---- Full GPR save (x1-x31, x0 omitted) into KERNEL_SAVE_AREA ----
    # M25/M26 idiom, scoped down: no thread-resume-jump machinery (OCA/
    # CSealEntry/OCRETURN) -- this handler always mret's back to the SAME
    # interrupted context. Real ABI scope note: `handler:`'s own mcause
    # dispatch above already used t3/t4 before this save runs, matching
    # every other test in this corpus's own established treatment of
    # t3/t4 as trap-entry scratch (RISC-V's own ABI never guarantees a
    # temporary register survives a trap/call) -- every OTHER GPR,
    # including all callee-saved s-registers, is genuinely preserved.
    csrrw x5, mscratch, x5           # free x5 (true value now parked in mscratch)
    li    x5, 453
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

    # x5's own true value, relayed out of mscratch through x31 (already
    # safely saved above, free to reuse as a one-shot carrier -- mirrors
    # the exact already-proven M25 pattern for this same hazard).
    csrr  x31, mscratch
    li    x5, 32
    .insn r 0x0b, 0x3, 0x01, x31, x2, x5   # ocs.d c2, x5(=32), x31(=x5's true value)

    # ---- Dispatch on a7 (real Linux syscall numbers) ----
    li   x6, 64
    beq  a7, x6, do_sys_write
    li   x6, 93
    beq  a7, x6, do_sys_exit
    j    fail                        # unrecognized syscall -- hard fail (a real dispatch
                                     # table / -ENOSYS convention is explicitly deferred)

do_sys_write:
    # ABI: a0=fd, a1=Object_ID, a2=offset, a3=count, a7=64.
    # Bind the CALLER-SUPPLIED Object_ID (a1) into c3 -- TRAPPING
    # veda.bind: hardware validates existence + ownership atomically. A
    # forged Object_ID hard-traps HERE (VEDA_CAUSE_OBJECT_NOT_FOUND/
    # OWNER_VIOLATION), never reaching the copy loop below -- the real
    # security property this whole milestone exists to prove, and what
    # task #299's negative test exercises directly.
    .insn i 0x0b, 0x5, x3, a1, 0     # veda.bind c3, a1

    # Bind KERNEL_CONSOLE_BUF (454, a fixed kernel-known literal, never
    # caller-controlled) into c4.
    li   x6, 454
    .insn i 0x0b, 0x5, x4, x6, 0     # veda.bind c4, x6

    # Dword-granular copy loop (OCL.D/OCS.D move exactly xlen_bytes=8 per
    # access on RV64 -- there is no byte-granular Veda-Core memory
    # instruction, veda_ocl_insts.sail's own veda_check_access confirms
    # this). Copies ceil(count/8) dwords; the caller's own USER_MSG
    # object must have Length >= round_up_8(count), a normal, self-
    # contained caller-side responsibility like every other bounds
    # relationship in this ISA.
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
    #    verified via an ORDINARY load from raw M-mode context (legal
    #    here -- purecap mode is off, PCC unbounded, this runs before
    #    mret). Only the first `count` (16) bytes are asserted, matching
    #    the design's own stated scope (trailing pad within the last
    #    dword, if any, is not asserted -- none exists for this count). --
    la   x6, kernel_console_buf
    ld   x7, 0(x6)
    li   x28, 0x1122334455667788
    bne  x7, x28, fail
    ld   x7, 8(x6)
    li   x28, 0x99AABBCCDDEEFF00
    bne  x7, x28, fail

    mv   a0, a3                      # return value: bytes written = count

    # ---- Full GPR restore ----
    # x10 (a0) is deliberately EXCLUDED: it carries the syscall's own
    # return value (set just above), matching every real syscall ABI's
    # convention that a0 is the one register a call is EXPECTED to
    # change, never restored to its pre-call value. Every other GPR,
    # including a1-a7, is still genuinely restored (the extra-safe,
    # "defensive against hand-written-asm bugs" choice this design
    # already committed to, beyond what the real ABI strictly requires).
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

    # x5's own restore: self-referential (offset source AND dest both
    # name x5) -- safe by construction, already proven in this codebase
    # (MILESTONE_C_GPR_CONTEXT_SAVE_RESULTS.md: VEDA_OCL's real execute
    # clause binds `offset` to a local before the destination write).
    li   x5, 32
    .insn r 0x0b, 0x3, 0x00, x5, x2, x5

    csrr x6, mepc
    addi x6, x6, 4
    csrw mepc, x6
    mret

do_sys_exit:
    # ABI: a0=status, a7=93 (unchanged from real Linux -- no pointer
    # argument to adapt). Real termination via the already-proven tohost/
    # HTIF convention; never returns, so no GPR-restore/mret needed here.
    beqz a0, do_sys_exit_pass
    RVMODEL_HALT_FAIL
do_sys_exit_pass:
    RVMODEL_HALT_PASS

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
