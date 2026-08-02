.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 20 positive test: outside any live
    # compartment (veda_pcc_length == UNBOUNDED at reset), ordinary
    # writes to the newly-gated compartment-state CSRs must still
    # succeed exactly as before -- the real regression-safety property
    # this milestone must not break. veda_pcc_base/_length are
    # deliberately NOT exercised with arbitrary values here (matching
    # the Sail side's own identical scoping note, MILESTONE_20_RESULTS.md):
    # doing so risks immediately tripping Milestone 14's own real
    # PCC-fetch enforcement on this test's own next instruction fetch.
    # mepcc_base/_length and veda_mode carry no such risk.
    # ─────────────────────────────────────────────────────────────
    la   t0, target
    csrw 0x7c2, t0               # veda_mepcc_base
    csrr x9, 0x7c2                # expect target's own address

    li   t1, 0x0080
    csrw 0x7c3, t1                # veda_mepcc_length
    csrr x10, 0x7c3                # expect 0x0080

    li   t2, 1
    csrw 0x7c5, t2                # veda_mode
    csrr x11, 0x7c5                # expect 1
    csrw 0x7c5, x0
    csrr x12, 0x7c5                # expect 0

done:
1:
    j 1b

.section .data
.align 3
target:
    .dword 0
