.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core Milestone 19: the critical regression guard -- proves
    # Veda's own real, capability-checked OCL.D/OCS.D are architecturally
    # untouched by the new ext_data_get_addr hook, even while
    # veda_purecap is set. This isn't asserted from the design alone (all
    # 8 real Veda memory-touching call sites use read_ram/write_ram
    # directly, never vmem_read/vmem_write) -- it's proven here with a
    # real write-then-read round trip through OCS.D/OCL.D under the new
    # mode, matching this project's own "prove it, don't just claim it"
    # discipline.
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0         # veda.bind c0, x1  -- Object_ID=1

    li   x6, 1
    csrw 0x7c5, x6                       # veda_mode.veda_purecap := 1 -- BEFORE the real Veda access

    li   x2, 0                           # offset = 0
    li   x3, 0x600DF00D
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2  # ocs.d c0, x2, x3  -- capability-checked write, purecap ON

    .insn r 0x0b, 0x3, 0x00, x4, x0, x2  # ocl.d x4, c0, x2  -- capability-checked read, purecap ON

    li   t2, 0x600DF00D
    bne  x4, t2, fail

    # Real, honest consequence of this milestone's own enforcement,
    # discovered via actual testing (a trap loop), not assumed:
    # RVMODEL_HALT_PASS's own ordinary `sw` to the tohost MMIO region
    # would itself be blocked while veda_purecap is still set -- clear it
    # first (the OCL.D/OCS.D round trip above, the actual thing under
    # test, has already completed by this point).
    csrw 0x7c5, x0
    RVMODEL_HALT_PASS
fail:
    csrw 0x7c5, x0
    RVMODEL_HALT_FAIL
