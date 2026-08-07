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

# Toolchain Milestone 12: stack-local (alloca) protection primitives.
# Unlike the c1-based primitives above (Object_ID-driven, fresh
# veda.bind.notrap per call), these derive a tightly-bounded scratch
# capability directly from c15 -- the persistent Stack-Spill Capability a
# veda_compartment function's own hand-written entry point already
# established once per compartment entry (Toolchain Milestone 11). No
# Object_ID, no fresh bind: c15 is already bound.
#
# c13 is the hand-picked scratch destination -- confirmed via a real
# grep audit (not assumed) free of collision with c15 (persistent SSC,
# never overwritten here) and c14 (an existing informal "OSpecialRW
# -discard" convention across 3 unrelated files -- reusing an ambiguously
# -typed register for a real, live, load-bearing value here would be
# exactly the risk Milestone 11's own C15-over-C14 register choice was
# made to avoid). c13 itself is used elsewhere only as a transient
# type-authority bind in veda_sched_asm.S's own unrelated scheduler
# -invocation call path, never live during a veda_compartment function
# body's own execution.
#
# Real, load-bearing instruction order (verified against veda_cap_insts.
# sail's own real semantics before writing this, not assumed): OCA must
# run FIRST to reach an arbitrary region_offset within c15's whole
# region (CSetBounds's own new Base starts at the capability's CURRENT
# offset, not an arbitrary one -- so CSetBounds-first only works when
# region_offset is already 0). THEN CSetBounds narrows to exactly `size`
# bytes -- this alloca's own real allocation size, not the individual
# access width -- giving a real, hardware-enforced perimeter around
# exactly this one local variable, isolating it from every other local
# variable in the same SSC region (the actual protection this milestone
# exists to provide). Both OCA and CSetBounds are real, already-tested
# (Milestone V-B) soft-fail instructions -- an out-of-range region_offset
# or size clears c13's own Tag bit rather than trapping immediately; the
# subsequent OCL.D/OCS.D against an untagged c13 is what genuinely hard
# -traps (Tag Violation or Bounds Violation), the real completion
# criterion this milestone's own verification test proves empirically.

# uint64_t veda_ocl_stack_d_scratch_asm(uint64_t region_offset /*a0*/,
#                                        uint64_t access_offset /*a1*/,
#                                        uint64_t size /*a2*/)
# Real, empirically-found requirement (Toolchain Milestone 12, found via a
# real sail_riscv_sim trace): unlike veda_ocl_d_scratch_asm above (which
# writes its loaded value through an out-param pointer via a plain `sd` --
# safe there since that path is never reached from inside a live
# compartment), this helper's callers ARE always inside a live
# veda_compartment call graph, where M19's purecap enforcement forbids
# ANY raw load/store, including a write-back through an out-param to the
# caller's own real stack address. Returns the loaded value directly in
# a0 instead -- no memory access, no out-param, sidestepping the problem
# entirely rather than routing around it.
.global veda_ocl_stack_d_scratch_asm
veda_ocl_stack_d_scratch_asm:
    oca        c13, c15, a0
    csetbounds c13, c13, a2
    ocl.d      a0, c13, a1
    ret

# void veda_ocs_stack_d_scratch_asm(uint64_t region_offset /*a0*/,
#                                    uint64_t access_offset /*a1*/,
#                                    uint64_t size /*a2*/, uint64_t value /*a3*/)
.global veda_ocs_stack_d_scratch_asm
veda_ocs_stack_d_scratch_asm:
    oca        c13, c15, a0
    csetbounds c13, c13, a2
    ocs.d      c13, a1, a3
    ret
