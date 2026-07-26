.section .text
.global _start
_start:
    li   x1, 1          # Object_ID = 1 (the capability to be sealed)
    .word 0x0000d00b    # veda.bind c0, x1
    li   x1, 3           # Object_ID = 3 (the type-authority object, Perms=0x300)
    .word 0x0000d10b     # veda.bind c2, x1
    li   x2, 5            # otype value to seal with
    .word 0x1421115b      # oca c2, c2, x2   (c2.Offset = 0+5 = 5, still authorized: Length=0x10)
    .word 0x202010db      # cseal c1, c0, c2  (c1 = c0 sealed with otype = c2.Offset = 5)
    .word 0x0800855b       # cgettype x10, c1  -- expect 5
    .word 0x060085db       # cgettag  x11, c1  -- expect 1
1:
    j 1b
