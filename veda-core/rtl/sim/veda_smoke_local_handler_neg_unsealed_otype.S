.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # RTL mirror of sail_tests/vc_local_handler_neg_unsealed_otype.S:
    # real bug found by adversarial review of this same RTL mirror
    # (present identically on the Sail side, fixed there the same way):
    # PCC can be genuinely bounded (a live compartment's real Base/
    # Length, correctly restored) while $veda_pcc_otype STILL holds the
    # shared UNSEALED_OTYPE sentinel (16'hFFFF) -- the ORDINARY state
    # after any successful VEDA_OCRETURN (which always sets otype to
    # 16'hFFFF, since a return target has no per-destination identity)
    # or after any trap+mret round trip that never goes through OCInvoke
    # again ($veda_pcc_otype's own mux has no is_mret arm, by design).
    # Before the fix, osethandler succeeded in this window and
    # registered a handler-table entry keyed under the SHARED 16'hFFFF
    # slot -- any other unrelated compartment resumed into that same
    # ordinary window (confirmed reachable by this project's own shipped
    # veda_sched_asm.S scheduler threads, entered exclusively via
    # OCReturn) would collide on that same key on its own next fault.
    # This test reproduces the simplest real instance directly: OCRETURN
    # through a sentry into a BOUNDED region, called from the initial,
    # never-compartmentalized _start context (PCC starts unbounded,
    # otype starts at its own default UNSEALED_OTYPE) -- no OCInvoke
    # anywhere in this file at all. osethandler must now hard-trap
    # (VEDA_CAUSE_NO_LIVE_COMPARTMENT=0x0a), proving the shared-identity
    # registration window is closed.
    #
    # Object_ID=610 (CODE-shaped) -- grep-audited fresh against every
    # existing rtl/sim/*.S Object_ID literal (highest in use across the
    # local_handler family: 603; 610+ is a clean, unused block).
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    li   x20, 0                    # sentinel: 1 once trap_handler is genuinely reached
    li   x23, 0                    # sentinel: 1 once cause==0x0a confirmed
    li   x24, 0                    # sentinel: 1 once cap_idx==8 confirmed
    li   x21, 0                    # final success sentinel
    li   x22, 0                    # fail-reason code, 0 = no failure recorded yet

    # -- Object_ID=610 (CODE-shaped): Base=target_region, Length=0x40,
    #    Perms=Permit_Execute|Permit_Invoke=0x0402 -- the identical
    #    established descriptor shape veda_smoke_local_handler_pos.S's
    #    own compartment_start object uses. Doubles as both the sentry
    #    SOURCE (sealed below into c9) and the later in-bounds
    #    osethandler operand (bound fresh to c8). --
    la   t0, target_region
    slli t0, t0, 32
    li   t1, 0x00400402
    or   t0, t0, t1
    li   x1, 610
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 610
    .insn i 0x0b, 0x5, x8, x1, 0   # veda.bind c8, x1  -- kept unsealed, for osethandler's own operand
    .insn i 0x0b, 0x5, x9, x1, 0   # veda.bind c9, x1  -- sealed into a sentry below

    .insn r 0x5b, 0x1, 0x15, x9, x9, x0  # csealentry c9, c9  -- MINT sentry, bounds [target_region, +0x40)

    # -- OCRETURN directly from _start -- no OCInvoke anywhere in this
    #    file. PCC narrows to target_region's own bounds; otype is
    #    explicitly (re)set to UNSEALED_OTYPE by OCRETURN itself. --
    .insn r 0x5b, 0x1, 0x16, x0, x9, x0  # ocreturn c9
poison_entry:
    j poison_entry                       # must NOT be reached

.balign 4
target_region:
    # -- reached ONLY via the OCRETURN above. c8 is still bound (Base=
    #    target_region, Length=0x40, Permit_Execute) and its own target
    #    address (target_region+0) lies genuinely WITHIN the
    #    just-narrowed live bounds -- an ordinary, in-bounds osethandler
    #    attempt, exercising ONLY the otype-identity gap (the bounds/
    #    confused-deputy check is already covered by
    #    veda_smoke_local_handler_neg_bounds_guard.S). Must hard-trap. --
    .insn r 0x5b, 0x1, 0x17, x0, x8, x0  # osethandler c8 -- must trap, no live otype identity
    j    fail_unexpected_no_trap          # must NOT be reached

fail_unexpected_no_trap:
    li   x22, 0xBAD1
    j    done

.balign 4
trap_handler:
    li   x20, 1                     # reached the ordinary global fallback, as expected
    csrr t4, 0x343                  # mtval -- decode cap_idx/cause per this file's own established convention
    andi t5, t4, 0x1f                # cause (low 5 bits)
    li   t6, 0x0a                    # VEDA_CAUSE_NO_LIVE_COMPARTMENT
    bne  t5, t6, cause_mismatch
    li   x23, 1
    srli t5, t4, 5
    li   t6, 8                       # c8, the osethandler operand
    bne  t5, t6, capidx_mismatch
    li   x24, 1

    csrr t1, 0x7c0                  # veda_pcc_base -- ordinary fallback, reset to 0
    bne  t1, x0, base_mismatch
    li   t2, 0xFFFFF
    csrr t3, 0x7c1                  # veda_pcc_length -- reset to VEDA_PCC_UNBOUNDED
    bne  t2, t3, length_mismatch

    li   x21, 0x600D                 # success sentinel
    j    done

cause_mismatch:
    li   x22, 0xBAD5
    j    done
capidx_mismatch:
    li   x22, 0xBAD6
    j    done
base_mismatch:
    li   x22, 0xBAD3
    j    done
length_mismatch:
    li   x22, 0xBAD4
    j    done

done:
1:
    j 1b
