.section .text
.global _start
_start:
    # ─────────────────────────────────────────────────────────────
    # Veda-Core RTL Milestone 4 positive test: the full privileged
    # lifecycle -- ODT-Populate a fresh Object_ID, Bind/use it, then
    # ODT-Destroy it, confirmed via a stale-generation re-check and a
    # post-destroy rebind both correctly rejected. Runs privileged
    # throughout ($priv resets to 1, matching real RISC-V's own
    # "harts reset into the highest privilege level" convention) --
    # `veda.droppriv` is exercised only by the separate negative test.
    # ─────────────────────────────────────────────────────────────
    # RTL Milestone 9 addendum: this file's own final OCL.D (line ~32,
    # the deliberate stale-generation re-check) is a "use"-family
    # violation ($veda_ocl_violation via $veda_gen_stale) -- since
    # Milestone 9 gave this RTL a real hard trap instead of only
    # suppressing the write, this now genuinely traps. Install a
    # generic "skip the faulting instruction and resume" handler up
    # front (no mcause/mtval assertion needed -- this file's own actual
    # subject is the ODT-Populate/Bind/Destroy lifecycle, not trap
    # delivery itself, which is MILESTONE_9_RESULTS.md's own test's
    # job) so this file's original x11-survives-untouched assertion
    # keeps meaning exactly what it always meant.
    la   t0, generic_trap_handler
    csrw mtvec, t0

    li   x1, 3                       # Object_ID = 3 (never seeded at reset -- a real fresh mint)
    li   x2, 0x800102000040100C      # descriptor: Base=0x80010200 Length=0x40 Perms=0x100C (Load|Store|NMC_Compute)
    .word 0x0620828b                 # veda.odt.populate x5, x1, x2  (privileged -> real write)

    .word 0x0000d00b                 # veda.bind c0, x1   -- expect c0.Tag=1, Base=0x80010200 (the just-populated values, not a stale seed)

    li   x3, 0                       # OCS/OCL offset
    li   x4, 0x1234567890ABCDEF      # value to round-trip through c0
    .word 0x0230320b                 # ocs.d c0, x3, x4   -- store x4 at c0's own Base+0
    .word 0x0030330b                 # ocl.d c0, x3, x6   -- expect x6 == x4

    .word 0x000003db                 # cgetbase x7, c0    -- expect 0x80010200 (confirms the populate's own Base actually landed, not the ODT's old contents)

    .word 0x0600948b                 # veda.odt.destroy x9, x1   -- invalidate Object_ID=3, bump generation

    .word 0x0000d08b                 # veda.bind c1, x1   -- rebind against the now-destroyed Object_ID -- expect c1.Tag=0 (ODT entry invalid)
    .word 0x0600855b                 # cgettag x10, c1    -- expect 0

    li   x11, 0xDEAD                 # sentinel -- must survive untouched below
    .word 0x0030358b                 # ocl.d c0, x3, x11  -- c0's own cached generation is now stale (destroy bumped the ODT's); must be rejected, x11 stays 0xDEAD
1:
    j 1b

# A generic, assertion-free trap handler: skip the one faulting
# instruction (mepc += 4) and resume. Reused verbatim by every
# pre-Milestone-9 test file in this suite whose own real subject is a
# different milestone's feature, not trap delivery -- kept identical
# across those files rather than each reinventing it, matching this
# project's own "no fresh design where a proven pattern already exists"
# discipline (already applied once for the +elf_hex/tohost harness).
generic_trap_handler:
    csrr t6, mepc
    addi t6, t6, 4
    csrw mepc, t6
    mret
