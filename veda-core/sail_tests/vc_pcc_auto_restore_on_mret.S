.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core: verifies the new automatic PCC restore-on-mret/sret
    # (veda_pcc_restore_on_xret(), extensions/I/base_insts.sail's execute
    # MRET()/SRET() calls, gated on hartSupports(Ext_Veda)). Three real,
    # distinct properties -- one compartment per phase, distinct
    # Object_IDs and distinct Length values throughout, so no phase can
    # accidentally pass by reusing another phase's leftover state.
    #
    # NOTE on this test's own design history, honestly recorded per this
    # project's own established discipline: the milestone's original plan
    # named a third property as "a nested nested trap incorrectly
    # restoring a stale, unrelated saved value." Tracing that scenario
    # precisely while writing this file found it does not test what was
    # intended -- an INNER trap's own mret restoring a value saved by an
    # OUTER, still-in-progress trap handler is real, CHERI-consistent
    # behavior (real CHERI's own mepcc-unseal-on-mret is unconditional on
    # every mret, nesting included; managing that is standard OS/software
    # responsibility, the same discipline mepc itself already requires
    # for any handler that permits re-entrancy) -- not a bug this
    # milestone's self-consuming reset does or should prevent. What the
    # self-consuming reset actually, verifiably guarantees is narrower:
    # a single saved value is never applied to more than one mret. Phase
    # 3 below tests that real, well-defined property (repeatability with
    # a fresh save/restore cycle) instead. General nested/re-entrant trap
    # handling remains a real, separate, explicitly out-of-scope gap --
    # named here, not silently assumed solved.
    la   t0, handler
    csrw mtvec, t0
    li   x30, 0                    # phase-counter, incremented once per trap in `handler`

    # ============================================================
    # Phase 1 -- positive automatic restore, self-consuming, and real
    # enforcement (not just CSR-readback) of the restored bounds.
    # ============================================================
    la   t0, compartment_a
    slli t0, t0, 32
    li   t1, 0x00400402            # Length=0x0040, Permit_Execute|Permit_Invoke
    or   t0, t0, t1
    li   x1, 60
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate CODE (Object_ID 60)

    li   x1, 61
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate DATA (Object_ID 61)

    li   x1, 62
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate type authority (Object_ID 62)

    li   x1, 60
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x1, 61
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1
    li   x1, 62
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4 -- narrows PCC to compartment_a [.., ..+0x40)

compartment_a:
    ecall                          # phase 1's own trap -- handler runs WITHOUT touching mepcc
phase1_resume:
    # -- reached only via mret's own new automatic restore (nobody
    #    explicitly wrote veda_pcc_base/_length back) --
    csrr t3, 0x7c1                 # veda_pcc_length -- expect the ORIGINAL 0x0040, not unbounded
    li   t4, 0x0040
    bne  t3, t4, fail
    csrr t3, 0x7c0                 # veda_pcc_base -- expect compartment_a's own address
    la   t4, compartment_a
    bne  t3, t4, fail
    csrr t3, 0x7c3                 # veda_mepcc_length -- self-consuming: must already read back UNBOUNDED
    li   t4, 0xFFFF
    bne  t3, t4, fail
    li   x24, 0x600D               # phase 1 restore + self-consume: correct

    # Real enforcement, not just CSR readback: this file's own checks
    # above already run right up against compartment_a's real 0x0040
    # -byte window (confirmed empirically while writing this test -- an
    # earlier version of this phase deliberately attempted a self-widen
    # CSR write here, expecting Milestone 20's own CSR-gate to trap it,
    # but the fetch of the CSR-write instruction itself already lies
    # past the real, restored 0x40-byte boundary, so a genuine, ordinary
    # PCC bounds-violation fetch fault (cause 0x18, the same real
    # mechanism vc_pcc_bounds_neg.S already proves) fires first --
    # arguably a more direct enforcement proof than the originally
    # -planned CSR-write block, since it demonstrates the restored
    # window is real and enforced against ordinary instruction fetch,
    # not a Veda-instruction-specific check). If the restore above were
    # a no-op (bug: still unbounded), fetch would keep succeeding past
    # this point instead of trapping, and phase 1 would incorrectly
    # "pass" without ever proving real enforcement.
    nop                             # the next fetch after this genuinely exceeds 0x40 bytes
    j    fail                      # unreachable if the boundary correctly fired above

    # ============================================================
    # Phase 2 -- explicit override still honored: handler deliberately
    # clears veda_mepcc_length before mret; auto-restore must NOT fire.
    # ============================================================
phase2_start:
    la   t0, compartment_b
    slli t0, t0, 32
    li   t1, 0x00400402
    or   t0, t0, t1
    li   x1, 70
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # CODE (Object_ID 70)

    li   x1, 71
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # DATA (Object_ID 71)

    li   x1, 72
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # type authority (Object_ID 72)

    li   x1, 70
    .insn i 0x0b, 0x5, x0, x1, 0
    li   x1, 71
    .insn i 0x0b, 0x5, x1, x1, 0
    li   x1, 72
    .insn i 0x0b, 0x5, x2, x1, 0

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke -- narrows PCC to compartment_b

compartment_b:
    ecall                          # phase 2's own trap -- handler EXPLICITLY overrides
phase2_resume:
    csrr t3, 0x7c1                 # expect still UNBOUNDED -- override honored, not restored
    li   t4, 0xFFFF
    bne  t3, t4, fail
    li   x27, 0x600D               # phase 2 override: correct
    j    phase3_start

    # ============================================================
    # Phase 3 -- repeatability: a second, independent compartment (fresh
    # Object_IDs, a distinct Length) proves the mechanism genuinely
    # re-arms for a new save/restore cycle rather than being a one-shot
    # artifact of phase 1's own specific state.
    # ============================================================
phase3_start:
    la   t0, compartment_c
    slli t0, t0, 32
    li   t1, 0x00300402            # Length=0x0030 -- deliberately different from phase 1's 0x0040
    or   t0, t0, t1
    li   x1, 80
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # CODE (Object_ID 80)

    li   x1, 81
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # DATA (Object_ID 81)

    li   x1, 82
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # type authority (Object_ID 82)

    li   x1, 80
    .insn i 0x0b, 0x5, x0, x1, 0
    li   x1, 81
    .insn i 0x0b, 0x5, x1, x1, 0
    li   x1, 82
    .insn i 0x0b, 0x5, x2, x1, 0

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke -- narrows PCC to compartment_c

compartment_c:
    ecall                          # phase 3's own trap -- handler again does NOT touch mepcc
phase3_resume:
    csrr t3, 0x7c1                 # expect compartment_c's own 0x0030, proving a fresh cycle
    li   t4, 0x0030
    bne  t3, t4, fail
    la   t4, compartment_c
    csrr t3, 0x7c0
    bne  t3, t4, fail
    li   x25, 0x600D               # phase 3 repeatability: correct

    # Explicit unbind to reach `done` -- reuses the same real
    # boundary-fetch trap already proven in phase 1 (compartment_c's own
    # 0x30-byte window is tighter still, so the next fetch after this
    # point genuinely exceeds it), landing back in `handler` a third
    # time.
    nop
    j    fail                      # unreachable if the boundary correctly fired above

done:
    li   t2, 0x600D
    bne  x21, t2, real_fail
    bne  x24, t2, real_fail
    bne  x27, t2, real_fail
    bne  x25, t2, real_fail
    li   t2, 0x900D
    bne  x22, t2, real_fail

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
real_fail:
    RVMODEL_HALT_FAIL

.balign 4
handler:
    # Single shared handler for every trap in this file, dispatched by a
    # small counter (x30) since three phases plus two CSR-escape-trap
    # exits share this one entry point -- mirroring this project's own
    # established one-handler-per-file convention where the trap
    # sequence is fixed and known in advance (vc_pcc_bounds_neg.S's own
    # single trap_handler is the same shape, just for one trap instead
    # of five).
    addi x30, x30, 1

    li   t4, 1
    beq  x30, t4, h_phase1_ecall
    li   t4, 2
    beq  x30, t4, h_phase1_escape
    li   t4, 3
    beq  x30, t4, h_phase2_ecall
    li   t4, 4
    beq  x30, t4, h_phase3_ecall
    li   t4, 5
    beq  x30, t4, h_phase3_escape
    j    fail                      # unreachable -- more traps fired than expected

h_phase1_ecall:
    csrr t3, mcause
    li   t4, 11
    bne  t3, t4, fail
    li   x21, 0x600D
    # -- deliberately do NOT touch mepcc: this is the whole point of
    #    phase 1, auto-restore must do the work with zero handler code. --
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret

h_phase1_escape:
    # -- the fetch past compartment_a's real 0x40-byte boundary (see the
    #    long comment at phase1_resume's own tail) trapped here as an
    #    ordinary PCC bounds violation (cause=0x18, mtval cap_idx=16<<5 |
    #    cause=0x01 = 0x201, the identical real mechanism
    #    vc_pcc_bounds_neg.S already proves), confirming the restored
    #    bounds were genuinely enforced, not merely CSR-readable. --
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0x201
    bne  t3, t4, fail
    # -- explicit, full unbind: the fault itself already ran
    #    veda_pcc_save_and_reset() (live is unbounded again), but also
    #    clear the shadow so this phase's own now-abandoned compartment
    #    can never be auto-restored later. --
    li   t3, 0xFFFF
    csrw 0x7c3, t3
    # -- resume at phase2_start directly, NOT mepc+4: +4 would only skip
    #    past the trapping `csrw 0x7c1` itself, landing on the very next
    #    line (`j fail`), which would then incorrectly execute. --
    la   t3, phase2_start
    csrw mepc, t3
    mret

h_phase2_ecall:
    csrr t3, mcause
    li   t4, 11
    bne  t3, t4, fail
    li   x27, 0x600D
    # -- explicit override: this is phase 2's whole point --
    li   t3, 0xFFFF
    csrw 0x7c3, t3                 # veda_mepcc_length := VEDA_PCC_UNBOUNDED
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret

h_phase3_ecall:
    csrr t3, mcause
    li   t4, 11
    bne  t3, t4, fail
    # -- deliberately do NOT touch mepcc again, same as phase 1 --
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret

h_phase3_escape:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, fail
    csrr t3, mtval
    li   t4, 0x201
    bne  t3, t4, fail
    li   t3, 0xFFFF
    csrw 0x7c3, t3
    li   x22, 0x900D               # final sentinel -- all three phases completed in order
    # -- resume at done directly, NOT mepc+4, same reasoning as
    #    h_phase1_escape above. --
    la   t3, done
    csrw mepc, t3
    mret
