.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core: closes the honest gap MILESTONE_21_RESULTS.md flagged as
    # "not verified by a real test... no real interrupt source is
    # currently active" -- confirms handle_trap_extension (universal
    # PCC-reset-on-any-trap, Milestone 21) fires correctly for a genuine
    # ASYNCHRONOUS machine-timer interrupt landing inside a live OCInvoke
    # compartment, not just for synchronous ecall/capability-violation
    # traps as every prior test exercised.
    #
    # Real CLINT MMIO addresses (plat_clint_base=0x02000000 per
    # veda_test_sail.json's "clint".base=33554432, offsets from
    # toolchain/sail-riscv/model/sys/platform.sail:79,81 --
    # MTIMECMP_BASE=0x4000, MTIME_BASE=0xbff8):
    #   mtimecmp = 0x02004000
    #
    # Determinism, not a timing race: mtimecmp is armed to 0 from
    # unconstrained (pre-compartment) context. Since mtime >= 0 always
    # (unsigned), mip.MTI (Machine Timer Interrupt Pending) latches true
    # immediately on that store (platform.sail's clint_dispatch, called
    # from clint_store) and stays pending. mie.MTI is also enabled here,
    # but mstatus.MIE (the global enable) is deliberately left OFF, so no
    # trap is taken yet. Only once execution is INSIDE the compartment do
    # we flip mstatus.MIE -- per the RISC-V Privileged spec, an already
    # -pending+enabled interrupt is taken at the very next instruction
    # boundary once globally enabled, so the trap fires deterministically
    # right there, with PCC genuinely narrowed, no polling or spin loop
    # needed.
    la   t0, real_handler          # a REALISTIC handler, outside the compartment
    csrw mtvec, t0

    li   t0, 0x02004000            # mtimecmp MMIO address
    li   t1, 0
    sd   t1, 0(t0)                 # mtimecmp = 0 -> mip.MTI latches pending now

    li   t0, 0x80                  # mie.MTIE (bit 7)
    csrs mie, t0                   # enable the timer source; mstatus.MIE stays 0

    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x00400402
    or   t0, t0, t1
    li   x1, 60
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate CODE

    li   x1, 61
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate DATA

    li   x1, 62
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate type authority

    li   x1, 60
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x1, 61
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1
    li   x1, 62
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4  -- narrows PCC to [landing_pad, landing_pad+0x40)

landing_pad:
    li   t0, 0x8                   # mstatus.MIE (bit 3)
    csrs mstatus, t0               # flip global enable -- interrupt taken at the NEXT
                                    # instruction boundary, deterministically, from inside
                                    # the live compartment (PCC still narrowed here).
    # -- reached only if real_handler ran and correctly returned here --
    li   x22, 0x900D
    j    done

.balign 4
real_handler:
    # -- confirms two independent things: (1) this code is only fetchable
    #    at all if veda_pcc_length was already reset to unbounded before
    #    this fetch (ext_fetch_check_pc applies to every fetch, including
    #    a trap handler's own first instruction, per Milestone 21's own
    #    established mechanism); (2) the trap is genuinely the async
    #    timer interrupt, not some other cause, via the explicit mcause
    #    check below.
    csrr t3, mcause
    li   t4, 0x8000000000000007    # Interrupt=1 (bit 63), code=7 (Machine Timer)
    bne  t3, t4, fail

    csrr t3, 0x7c1                 # veda_pcc_length -- expect VEDA_PCC_UNBOUNDED
    li   t4, 0xFFFF
    bne  t3, t4, fail

    # Disable the timer source so it can't re-fire after mret (mtimecmp
    # stays 0 and mie.MTIE stays set otherwise -- this is cleanup, not
    # part of the property under test).
    li   t3, 0x80
    csrc mie, t3

    li   x21, 0x600D

    # NOTE: unlike ecall's mepc (which points AT the trapping ecall
    # instruction, requiring +4 to skip past it), an interrupt's mepc
    # already holds the address of the instruction that was ABOUT to
    # execute when the interrupt preempted it -- that instruction never
    # ran. So mepc must NOT be incremented here; mret must resume exactly
    # at mepc, or the still-pending `csrs mstatus,t0` at landing_pad would
    # be skipped and mstatus.MIE would incorrectly stay 0 on return in a
    # differently-shaped test. (In this specific test that one instruction
    # is idempotent to re-run since mie.MTIE was just cleared above, but
    # the general principle -- do not adjust mepc for an interrupt -- is
    # the real, load-bearing point being verified.)
    mret

done:
    li   t2, 0x600D
    bne  x21, t2, fail
    li   t2, 0x900D
    bne  x22, t2, fail

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
