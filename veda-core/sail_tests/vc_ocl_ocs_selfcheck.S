.include "veda_selfcheck_macros.S"

.section .text
.global _start
_start:
    li   x1, 1          # Object_ID = 1
    .word 0x0000d00b    # veda.bind c0, x1
    li   x2, 0          # offset
    li   x3, 0x1234      # value to store
    .word 0x0220318b     # ocs.d c0, x2, x3
    li   x4, 0             # clear x4 so a no-op can't accidentally pass
    .word 0x0020320b        # ocl.d c0, x2, x4
    li   x5, 0x1234          # expected value
    beq  x4, x5, pass
    RVMODEL_HALT_FAIL
pass:
    RVMODEL_HALT_PASS
