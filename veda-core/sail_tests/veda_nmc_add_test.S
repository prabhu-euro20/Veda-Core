.section .text
.global _start
_start:
    li   x1, 1          # x1 = Object_ID = 1 (test-seeded in ext_reset, Perms now includes Permit_NMC_Compute)
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1
    li   x2, 0          # x2 = offset = 0
    li   x3, 0x100      # x3 = initial value to store
    .insn r 0x0b, 0x3, 0x01, x3, x0, x2  # ocs.d c0, x2, x3   (store 0x100 at c0.Base + 0)
    li   x4, 0x23       # x4 = value to add via NMC_ADD.D
    li   x5, 0          # clear x5 so a no-op can't accidentally look right
    .insn r 0x0b, 0x3, 0x02, x5, x0, x4  # nmc_add.d x5, c0, x4  (x5 <- old value 0x100; memory <- 0x100+0x23=0x123)
    li   x6, 0          # clear x6
    .insn r 0x0b, 0x3, 0x00, x6, x0, x2  # ocl.d x6, c0, x2   (load back from c0.Base + 0 into x6, should be 0x123)
    # Expected: x5 == 0x100 (old value returned by NMC_ADD.D), x6 == 0x123 (post-add value).
1:
    j 1b
