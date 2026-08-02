.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 19 negative test 1: the real,
    # previously-open CGetBase-then-ordinary-load/store bypass this
    # milestone closes. With veda_purecap set, an ordinary `sd`/`ld`
    # through a plain GPR address must hard-trap -- cause=0x07
    # (VEDA_CAUSE_PURECAP_VIOLATION), cap_idx=17 (0b10001, the
    # "purecap enforcement, not a real capability register" sentinel,
    # the next free value after PCC's own 16) -- mtval = (17<<5)|0x07
    # = 0x227, verified by hand before writing this test. Proves the
    # write is genuinely suppressed (the destination register keeps
    # its prior value, not corrupted with load data) and that a real
    # trap-and-recover cycle correctly resumes with purecap still
    # live (software, not hardware, clears it -- matching every other
    # Veda-Core CSR's own explicit-restore convention).
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    la   t1, scratch
    li   t2, 0x1234
    sd   t2, 0(t1)                # ordinary store, purecap still OFF -- must succeed

    li   t3, 1
    csrw 0x7c5, t3                # veda_purecap := 1

    li   x9, 0xDEAD                # sentinel: must survive untouched -- the blocked load must never overwrite it
    ld   x9, 0(t1)                 # BLOCKED: purecap is on -- must hard-trap, x9 must stay 0xDEAD

    li   x22, 0xBAD1                # must NOT be reached directly
    j    done

trap_handler:
    csrr t4, mcause
    li   t5, 0x18
    bne  t4, t5, fail
    csrr t4, mtval
    li   t5, 0x227                 # (cap_idx=17<<5)|cause=0x07 = 0x227
    bne  t4, t5, fail

    li   x21, 0x600D                # sentinel: reached the handler with the correct mcause/mtval

    # -- explicit recovery: clear purecap, resume past the blocked load --
    csrw 0x7c5, x0
    la   t4, recovery
    csrw mepc, t4
    mret

recovery:
    ld   x23, 0(t1)                  # purecap is OFF again -- ordinary load must now succeed, expect 0x1234
    li   x22, 0x900D                 # sentinel: correctly resumed and ordinary access works again
    j    done

fail:
    li   x22, 0xBAD

done:
1:
    j 1b

.section .data
.align 3
scratch:
    .dword 0
