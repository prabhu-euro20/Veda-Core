.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # RTL mirror of sail_tests/vc_local_handler_pos.S
    # (LOCAL_FAULT_RECOVERY_DESIGN.md / LOCAL_FAULT_RECOVERY_RESULTS.md):
    # positive test for VEDA_LOCAL_HANDLER. A live compartment
    # self-registers its own local-handler entry point via
    # `osethandler`, then deliberately drives a real out-of-bounds
    # fetch (an explicit far jump, not merely running off the end --
    # keeps the fault unambiguous and reusable by other tests). Confirms:
    #   (1) the redirect lands at handler_entry, NOT at mtvec's own
    #       trap_handler (x20 set, trap_handler's own poison x22=0xBAD2
    #       never set);
    #   (2) veda_pcc_base/veda_pcc_length (CSRs 0x7c0/0x7c1) read back
    #       INSIDE the handler show the SAME pre-fault bounds --
    #       narrowed, not widened, not reset -- proving the redirect
    #       preserves rather than escalates privilege;
    #   (3) the handler exits cleanly via a pre-minted sentry OCRETURN,
    #       landing at return_landing with PCC genuinely widened back out
    #       (x21 = success sentinel).
    #
    # Object_IDs 590 (CODE)/591 (DATA)/592 (TYPE authority)/593 (sentry
    # source) -- grep-audited fresh against every existing rtl/sim/*.S
    # Object_ID literal before picking (highest in use: 562, from
    # veda_smoke_trap_quarantine_csr_clear_pos.S; 590+ is a clean, unused
    # block).
    # ─────────────────────────────────────────────────────────────
    la   t0, trap_handler
    csrw mtvec, t0

    li   x20, 0                    # sentinel: 1 once handler_entry is genuinely reached
    li   x23, 0                    # sentinel: 1 once veda_pcc_base readback matches pre-fault base
    li   x24, 0                    # sentinel: 1 once veda_pcc_length readback matches pre-fault length
    li   x21, 0                    # final success sentinel (0x600D on clean OCRETURN exit)
    li   x22, 0                    # fail-reason code, 0 = no failure recorded yet

    # -- Object_ID=590 (CODE): Base=compartment_start, Length=0x0040
    #    (64 bytes -- objdump-confirmed real extent: setup + osethandler +
    #    the deliberate OOB jump + the handler body (its own base/length
    #    readback checks) + its own OCRETURN, all inside bounds --
    #    matches veda_smoke_mosB_sentry.S's own established 0x40 size for
    #    a similarly-shaped compartment), Permit_Execute|Permit_Invoke=0x0402. --
    la   t0, compartment_start
    slli t0, t0, 32
    li   t1, 0x00400402
    or   t0, t0, t1
    li   x1, 590
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- CODE

    # -- Object_ID=591 (DATA): Permit_Invoke only. --
    li   x1, 591
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- DATA

    # -- Object_ID=592: type authority, Permit_Seal|Permit_Unseal. --
    li   x1, 592
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- TYPE

    # -- Object_ID=593: sentry source, Base=return_landing, Length=0xFFFF,
    #    Perms=Execute only (mirrors veda_smoke_mosB_sentry.S's own
    #    already-verified pattern exactly). --
    la   t0, return_landing
    slli t0, t0, 32
    li   t1, 0xFFFF0002
    or   t0, t0, t1
    li   x1, 593
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2 -- sentry source

    li   x1, 590
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1 -- CODE (kept, unsealed, survives OCInvoke)
    li   x1, 591
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1 -- DATA
    li   x1, 592
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1 -- type authority
    li   x1, 593
    .insn i 0x0b, 0x5, x8, x1, 0  # veda.bind c8, x1 -- sentry source

    .insn r 0x5b, 0x1, 0x15, x9, x8, x0  # csealentry c9, c8  -- MINT sentry (otype=0xFFFE)

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2  -- sealed CODE
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2  -- sealed DATA

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4  -- narrows PCC to [compartment_start, +0x18)
poison_entry:
    j poison_entry                        # must NOT be reached -- OCInvoke's own real jump must fire

.balign 4
compartment_start:
    # c0 (unsealed CODE cap, Base=compartment_start, Length=0x40,
    # Offset=0) survives OCInvoke untouched -- capability registers are
    # not cleared, only PCC narrows (the same real property
    # veda_smoke_mosB_sentry.S's own c9 sentry already relies on).
    li   x30, 20                          # real, objdump-confirmed offset of handler_entry from
                                           # compartment_start (NOT 16 -- poison_mid's own 4-byte dead
                                           # instruction sits between the jal and handler_entry)
    .insn r 0x5b, 0x1, 0x0a, x11, x0, x30 # oca c11, c0, x30 -- c11 = {Base=compartment_start, Offset=20}, i.e.
                                           # handler_entry. Deliberately NOT c9 -- c9 already holds the
                                           # real minted sentry (csealentry, before OCInvoke); reusing it
                                           # here would clobber the sentry before OCRETURN ever gets to
                                           # consume it (a real bug this file's own testing caught).
    .insn r 0x5b, 0x1, 0x17, x0, x11, x0  # osethandler c11  -- self-register handler_entry for THIS otype
    jal  x0, trap_handler          # deliberate, unambiguous OOB fetch target -- must REDIRECT to
                                            # handler_entry, not fall through to mtvec's trap_handler

poison_mid:
    j poison_mid                          # dead code -- only ever fetched if the jal somehow didn't fault

.balign 4
handler_entry:
    li   x20, 1                           # reached via redirect -- proves the mechanism fired at all
    la   t0, compartment_start
    csrr t1, 0x7c0                        # veda_pcc_base -- must equal compartment_start (narrowed, not reset)
    bne  t0, t1, base_mismatch
    li   x23, 1
    li   t2, 0x40
    csrr t3, 0x7c1                        # veda_pcc_length -- must equal 0x40 (SAME pre-fault bounds, not widened)
    bne  t2, t3, length_mismatch
    li   x24, 1
    .insn r 0x5b, 0x1, 0x16, x0, x9, x0   # ocreturn c9  -- widen PCC to sentry's own bounds, jump to return_landing

poison_after_return:
    j poison_after_return                 # must NOT be reached -- OCRETURN's own real jump must fire

base_mismatch:
    li   x22, 0xBAD3
    j    done
length_mismatch:
    li   x22, 0xBAD4
    j    done

.balign 4
trap_handler:
    li   x22, 0xBAD2                      # must NEVER be reached: the redirect must fire in place of the
                                           # ordinary global fallback
    j    done

.balign 4
return_landing:
    li   x21, 0x600D                      # success sentinel
    j    done

done:
1:
    j 1b
