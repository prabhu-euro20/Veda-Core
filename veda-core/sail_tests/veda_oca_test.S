.section .text
.global _start
_start:
    li   x1, 1          # x1 = Object_ID = 1
    .word 0x0000d00b    # veda.bind c0, x1
    li   x2, 0x10        # x2 = offset delta / fresh OCS.D offset = 0x10
    li   x3, 0x100       # x3 = initial value to store at Base+0x10
    .word 0x0220318b     # ocs.d c0, x2, x3   (store 0x100 at c0.Base + 0x10)
    .word 0x142010db     # oca c1, c0, x2     (c1 = c0 with persistent Offset = 0x10)
    li   x4, 0x55        # x4 = value to add via NMC_ADD.D on c1
    li   x5, 0            # clear x5
    .word 0x0440b28b     # nmc_add.d x5, c1, x4  (uses c1's own persistent Offset=0x10; x5<-old 0x100; mem<-0x155)
    li   x6, 0            # clear x6
    .word 0x0020330b      # ocl.d x6, c0, x2   (load back from Base+0x10 via c0's fresh offset, should be 0x155)
    # Expected: x5 == 0x100 (old value via NMC_ADD through OCA-positioned c1),
    #           x6 == 0x155 (confirms the write landed at Base+0x10, not Base+0).
1:
    j 1b
