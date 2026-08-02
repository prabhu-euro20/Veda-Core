.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core Milestone 19: positive control for
    # vc_purecap_load_after_cgetbase_neg.S -- identical setup, but
    # veda_purecap is never set. Proves the new ext_data_get_addr hook's
    # default passthrough (Ext_DataAddr_OK) is unaffected when the mode
    # bit is clear -- zero regression to ordinary RV64I semantics outside
    # purecap mode. Also proves the raw-address LOAD genuinely reads real
    # memory content: a known value is first written via the real,
    # capability-checked OCS.D path, then read back via the ordinary,
    # raw-address `ld` -- both must agree.
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0         # veda.bind c0, x1  -- Object_ID=1

    li   x2, 0                           # offset = 0
    li   x3, 0xABCD1234
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2  # ocs.d c0, x2, x3  -- capability-checked write

    .insn r 0x5b, 0x0, 0x00, x5, x0, x0  # cgetbase x5, c0  -- x5 = raw Base

    ld   x7, 0(x5)                       # ordinary LOAD through the raw address -- purecap OFF, must succeed

    li   t2, 0xABCD1234
    bne  x7, t2, fail

    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
