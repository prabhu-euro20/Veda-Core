.section .text
.global _start
_start:
    li   x1, 1          # x1 = Object_ID = 1
    .word 0x0000d00b    # veda.bind c0, x1
    li   x2, 0x10         # offset for OCS.D / OCA delta
    li   x3, 0x100         # initial value
    .word 0x0220318b        # ocs.d c0, x2, x3   (store 0x100 at Base+0x10)
    .word 0x142010db         # oca c1, c0, x2     (c1.Offset = 0x10)
    li   x4, 0x23              # NMC_ADD operand
    li   x5, 0                  # clear x5
    .word 0x0440b28b              # nmc_add.d x5, c1, x4  (x5<-old 0x100; mem<-0x123)
    li   x6, 0x0F                  # AMOXOR operand
    li   x7, 0                      # clear x7
    .word 0x2060b3ab                  # veda.amoxor.d x7, c1, x6 (x7<-old 0x123; mem<-0x12C)
    li   x8, 0                          # clear x8
    .word 0x0020340b                      # ocl.d x8, c0, x2  (load back from Base+0x10, expect 0x12C)
    # Expected: x5==0x100 (NMC_ADD old value), x7==0x123 (Atomic old value),
    #           x8==0x12C (0x100+0x23=0x123, 0x123^0x0F=0x12C).
1:
    j 1b
