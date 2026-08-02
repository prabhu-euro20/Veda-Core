# Veda-Core runtime: raw ISA-level primitives, real mnemonics (this is the
# first real software in this project to use the assembler built in
# Toolchain Milestones 5a/5b-M6 instead of hand-encoded `.insn`/hex).
# C-callable per the standard RV64 integer calling convention (args in
# a0-a7, return in a0).
#
# The runtime's own single working capability register is c1 -- a fixed,
# documented convention (no dynamic capability-register allocation exists
# before Toolchain Milestone 8/9's compiler pass), matching how the RISC-V
# calling convention itself reserves fixed GPRs for fixed roles (sp=x2,
# ra=x1) rather than allocating them dynamically. c0 is deliberately left
# unused/reserved for a future second concurrently-live object, should a
# later milestone need one; this minimal runtime never needs two capability
# registers live at once (every access re-binds c1 fresh, veda_rt.c).

.section .text

# uint64_t veda_odt_populate_fast_asm(uint64_t object_id /*a0*/, uint64_t base /*a1*/)
# Returns 0 in a0 on success (X(rd)=zeros() per the real execute clause).
# Callers in this runtime never invoke this on a slot their own software
# bookkeeping (veda_rt.c) has marked retired -- the one exception is the
# generation-exhaustion negative test's own deliberate direct probe, which
# expects (and catches) the real Illegal_Instruction() hard trap this
# produces when called against an already-retired Object_ID.
.global veda_odt_populate_fast_asm
veda_odt_populate_fast_asm:
    veda.odt.populate.fast a0, a0, a1
    ret

# uint64_t veda_odt_destroy_asm(uint64_t object_id /*a0*/)
.global veda_odt_destroy_asm
veda_odt_destroy_asm:
    veda.odt.destroy a0, a0
    ret

# int veda_bind_scratch_asm(uint64_t object_id /*a0*/)
# Binds c1 via veda.bind.notrap (never hard-traps, matching this runtime's
# established "no unexpected hard fault on a recoverable condition" design
# -- see veda_rt.c). Returns 1 (tag set, bind succeeded) or 0 (object never
# populated / already destroyed) in a0, via cgettag.
.global veda_bind_scratch_asm
veda_bind_scratch_asm:
    veda.bind.notrap c1, a0
    cgettag a0, c1
    ret

# void veda_ocl_d_scratch_asm(uint64_t offset /*a0*/, uint64_t *out /*a1*/)
# Reads via c1, already bound by a prior veda_bind_scratch_asm call. Does
# NOT itself guard against an out-of-bounds/permission-violating offset --
# that is real hardware's own job (veda_check_access), and an invalid
# offset is expected to (and does) hard-trap here, by design.
.global veda_ocl_d_scratch_asm
veda_ocl_d_scratch_asm:
    ocl.d a2, c1, a0
    sd    a2, 0(a1)
    ret

# void veda_ocs_d_scratch_asm(uint64_t offset /*a0*/, uint64_t value /*a1*/)
.global veda_ocs_d_scratch_asm
veda_ocs_d_scratch_asm:
    ocs.d c1, a0, a1
    ret
