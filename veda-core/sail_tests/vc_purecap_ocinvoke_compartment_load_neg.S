.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Veda-Core Milestone 19: proves the second, newly identified trigger
    # condition independently of the first (global veda_purecap, tested
    # in vc_purecap_load_after_cgetbase_neg.S) -- code entered via a real
    # OCInvoke compartment (Milestone 14) must also lose ordinary
    # LOAD/STORE access, even with veda_purecap never set anywhere in
    # this file. Reuses the exact real compartment-entry fixture from
    # vc_ocinvoke.S (Object_ID=30 CODE/31 DATA/32 type-authority).
    la   t0, trap_handler
    csrw mtvec, t0

    la   t0, landing_pad
    slli t0, t0, 32
    li   t1, 0x01000402
    or   t0, t0, t1
    li   x1, 30
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- CODE

    li   x1, 31
    li   x2, 0x8001070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- DATA

    li   x1, 32
    li   x2, 0x8001080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- type authority

    li   x1, 30
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- CODE
    li   x1, 31
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- DATA
    li   x1, 32
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- type authority

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4   -- narrows PCC to [landing_pad, landing_pad+0x100)

landing_pad:
    # -- deliberately NOT setting veda_purecap anywhere in this file --
    #    isolates the compartment-bounding trigger condition alone.
    li   x8, 0x80010000                  # Object_ID=1's own pre-seeded Base -- a real, valid RAM address
    ld   x9, 0(x8)                       # ordinary LOAD from inside the compartment -- must trap
    RVMODEL_HALT_FAIL

.balign 4
trap_handler:
    csrr t3, mcause
    li   t4, 0x18
    bne  t3, t4, check_fail
    csrr t3, mtval
    li   t4, 0x227        # (cap_idx=17<<5)|cause=0x07 -- confirms this is the PURECAP cause,
                           # NOT the PCC-fetch cause (which would read 0x201) -- proves the
                           # right one of the two trigger conditions actually fired
    bne  t3, t4, check_fail
    RVMODEL_HALT_PASS
check_fail:
    RVMODEL_HALT_FAIL
