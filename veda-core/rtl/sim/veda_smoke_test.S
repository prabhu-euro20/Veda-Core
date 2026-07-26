.section .text
.global _start
_start:
    li   x1, 1          # x1 = Object_ID = 1 (RTL Milestone 1 test-seeded ODT entry)
    .word 0x0000d00b    # veda.bind c0, x1
    li   x2, 0          # offset
    li   x3, 0x1234      # value to store
    .word 0x0220318b     # ocs.d c0, x2, x3
    li   x4, 0             # clear x4 so a no-op can't accidentally pass
    .word 0x0020320b        # ocl.d c0, x2, x4
    # Expected: x4 == 0x1234 (real round trip through Veda-Core RTL's own
    # capability register file, ODT lookup, and elfmem access).
1:
    j 1b
