.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 19 positive test: Veda-Purecap
    # Enforcement. Proves three real properties in one program:
    # (1) veda_purecap defaults OFF at reset -- an ordinary sd/ld
    #     round-trip must succeed completely unmodified, the real
    #     regression-safety property this milestone must not break
    #     (the entire pre-existing 27-test RTL corpus and 51/51 ACT4
    #     conformance depend on this).
    # (2) veda_mode (CSR 0x7c5) round-trips a software write/read
    #     correctly, matching veda_attr's own already-proven CSR
    #     pattern (Milestone 18).
    # (3) A real Veda-Core OCL.D/OCS.D pair (Object_ID=1, the reset-
    #     seeded fixture Milestone 1/2's own tests already use) keeps
    #     working correctly even while veda_purecap is ON -- proving
    #     this milestone's enforcement hook shares zero code path with
    #     a real, legitimate Veda access (checked directly against
    #     $veda_purecap_violation's own definition before writing this:
    #     it is gated on $is_load/$is_store, the base-ISA opcodes only,
    #     never on $is_veda_ocl/$is_veda_ocs).
    # ─────────────────────────────────────────────────────────────

    # -- (1) ordinary base-ISA store/load, BEFORE purecap is ever touched --
    la   t0, scratch
    li   t1, 0x1234
    sd   t1, 0(t0)
    ld   x9, 0(t0)               # expect 0x1234 -- purecap OFF at reset must not block this

    # -- (2) veda_mode CSR round-trip --
    li   t2, 1
    csrw 0x7c5, t2
    csrr x10, 0x7c5              # expect 1

    # -- (3) a real Object-Bind + OCS.D + OCL.D pair, WHILE purecap is ON --
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- Object_ID=1, reset-seeded (Base=0x80010000, Load|Store)
    li   x3, 0x0
    li   x4, 0xABCD
    .insn r 0x0b, 0x3, 0x01, x4, x0, x3   # ocs.d c0, x3, x4
    .insn r 0x0b, 0x3, 0x00, x11, x0, x3  # ocl.d x11, c0, x3   -- expect 0xABCD, unaffected by purecap=1

    # -- turn purecap back off, confirm ordinary access resumes --
    csrw 0x7c5, x0
    csrr x12, 0x7c5              # expect 0
    li   t3, 0x5678
    sd   t3, 0(t0)
    ld   x13, 0(t0)              # expect 0x5678 -- ordinary access works again once purecap clears

done:
1:
    j 1b

.section .data
.align 3
scratch:
    .dword 0
