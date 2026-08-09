.section .text
.global _start
_start:
    # RTL Milestone 25 mirror: standalone, isolated proof that the new
    # mscratch CSR (0x340, veda_core.tlv) round-trips correctly in real
    # clocked simulation before it is trusted inside the much larger,
    # much-harder-to-debug 31-register scheduler port. Two real properties
    # checked: (1) plain csrw-then-csrr survives a write/read round trip;
    # (2) csrrw's own atomic "read OLD value into rd, write NEW value into
    # the CSR" semantics -- the exact mechanism the scheduler's own
    # trap-entry bootstrap depends on -- hold for a genuinely new CSR, not
    # just for the long-established mtvec this design was copied from.
    li   x5, 0x1234567890ABCDEF
    csrw mscratch, x5
    csrr x6, mscratch
    bne  x5, x6, fail            # plain write/read round trip

    li   x7, 0x0FEDCBA987654321
    csrrw x8, mscratch, x7       # x8 := OLD mscratch (must equal x5's pattern); mscratch := x7
    bne  x8, x5, fail
    csrr x9, mscratch
    bne  x9, x7, fail            # new value genuinely landed

    li   x21, 0x600D
    j    done
fail:
    li   x21, 0xDEAD
done:
1:
    j 1b
