.section .text
.global _start
_start:
    li   x1, 1          # Object_ID = 1 (capability to attempt to seal)
    .word 0x0000d00b    # veda.bind c0, x1
    li   x1, 4           # Object_ID = 4 (seeded WITHOUT Permit_Seal, Perms=0)
    .word 0x0000d10b     # veda.bind c2, x1
    li   x2, 5             # candidate otype value
    .word 0x1421115b       # oca c2, c2, x2   (structurally fine, c2 unsealed & in-bounds; OCA needs no Permit_Seal)
    .word 0x202010db        # cseal c1, c0, c2  -- c2 lacks Permit_Seal: must SOFT-FAIL (c1.Tag=0), not trap
    .word 0x0600855b         # cgettag x10, c1  -- expect 0 (soft-fail confirmed, no trap occurred)
1:
    j 1b
