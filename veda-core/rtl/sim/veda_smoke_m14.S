.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 14: PCC compartment bounding -- mirrors
    # vc_pcc_bounds.S's own Sail scenario exactly (same objects, same
    # encodings, identical bit layout in both layers). Proves the real
    # state transitions via the new veda_pcc_base/veda_pcc_length CSRs
    # (0x7c0/0x7c1): a fresh hart starts unbounded; a successful OCInvoke
    # narrows the live compartment to the invoked CODE capability's own
    # Base/Length; a second OCInvoke into an unbounded return capability
    # widens it back. Fetch-time enforcement of these bounds (the actual
    # trap) is proven separately in veda_smoke_m14_neg.S.
    # ─────────────────────────────────────────────────────────────
    csrr x9, 0x7c1                # pcc_length BEFORE any OCInvoke -- expect 0xFFFF

    # -- Object_ID=50 (CODE): Permit_Execute|Permit_Invoke=0x0402,
    #    Base=landing_pad, Length=0x0100. --
    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x01000402
    or   t0, t0, t1
    li   x1, 50
    mv   x2, t0
    .word 0x0620828b              # veda.odt.populate x5, x1, x2

    # -- Object_ID=51 (DATA): Permit_Invoke only=0x0400. --
    li   x1, 51
    li   x2, 0x8001070000400400
    .word 0x0620828b              # veda.odt.populate x5, x1, x2

    # -- Object_ID=52: type authority, Permit_Seal|Permit_Unseal=0x0300. --
    li   x1, 52
    li   x2, 0x8001080000400300
    .word 0x0620828b              # veda.odt.populate x5, x1, x2

    li   x1, 50
    .word 0x0000d00b              # veda.bind c0, x1  -- CODE
    li   x1, 51
    .word 0x0000d08b              # veda.bind c1, x1  -- DATA
    li   x1, 52
    .word 0x0000d10b              # veda.bind c2, x1  -- type authority

    .word 0x202011db              # cseal c3, c0, c2
    .word 0x2020925b              # cseal c4, c1, c2

    .word 0x2441905b              # ocinvoke c3, c4   -- narrows PCC to Object_ID=50's own Base/Length

landing_pad:
    csrr x10, 0x7c0                # pcc_base AFTER OCInvoke -- expect landing_pad's own runtime address
    csrr x11, 0x7c1                # pcc_length AFTER OCInvoke -- expect 0x0100

    # -- Object_ID=53 (return CODE): Base=return_pad, Length=0xFFFF
    #    (unbounded -- a real "return to the unconstrained caller
    #    context" capability). --
    la   t0, return_pad
    slli t0, t0, 32
    li   t1, 0xFFFF0402
    or   t0, t0, t1
    li   x1, 53
    mv   x2, t0
    .word 0x0620828b              # veda.odt.populate x5, x1, x2

    li   x1, 54
    li   x2, 0x8001090000400400
    .word 0x0620828b              # veda.odt.populate x5, x1, x2  -- Object_ID=54 (return DATA)

    li   x1, 53
    .word 0x0000d28b              # veda.bind c5, x1  -- return CODE
    li   x1, 54
    .word 0x0000d30b              # veda.bind c6, x1  -- return DATA

    .word 0x202293db              # cseal c7, c5, c2
    .word 0x2023145b              # cseal c8, c6, c2

    .word 0x2483905b              # ocinvoke c7, c8   -- widens PCC back to unbounded

return_pad:
    csrr x12, 0x7c1                # pcc_length AFTER the return OCInvoke -- expect 0xFFFF again

1:
    j 1b
