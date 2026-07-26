.section .text
.global _start
_start:
    li   x1, 1          # x1 = Object_ID = 1 (test-seeded in ext_reset)
    .word 0x0000d00b    # veda.bind c0, x1   (mode=Bind, rd=c0)
    li   x2, 0           # x2 = offset = 0
    li   x3, 0x1234      # x3 = test value to store
    .word 0x0220318b    # ocs.d c0, x2, x3   (store x3 at c0.Base + x2)
    li   x4, 0            # clear x4 so a no-op load can't accidentally pass
    .word 0x0020320b    # ocl.d c0, x2, x4   (load from c0.Base + x2 into x4)
    # x4 should now equal 0x1234 if OCL/OCS + Object-Bind worked correctly.
1:
    j 1b
