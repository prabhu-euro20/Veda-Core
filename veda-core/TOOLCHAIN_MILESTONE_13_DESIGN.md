# Toolchain Milestone 13 (Design): Hardware-Native Protection for C Global/Static Variables

## Context

Milestone 11 closed callee-saved-register spills (`RISCVFrameLowering`, backend-level, `C15`).
Milestone 12 closed stack-local `alloca`s (`VedaShadowPropagation.cpp` Phase B0, IR-level, offsets
inside the same `C15`/SSC region via `C13` scratch). Both explicitly named the same remaining gap in
their own "Not yet built" sections: **C global and static variables** — `int g;` at module scope, or
`static int s;` inside a function — which lower to an LLVM `GlobalVariable` at a fixed, link-time
address in `.data`/`.bss`/`.rodata`. Any access to one inside a `veda_compartment` function currently
emits an ordinary `lui`/`auipc`+`ld`/`sd` pair, which hard-traps under Milestone 19's purecap rule
(`VEDA_CAUSE_PURECAP_VIOLATION`, `cause = 0x07`) — a blanket rule on `veda_mode`, not scoped by
address or function identity (`VedaShadowPropagation.cpp` lines 685-696, `VEDA_CORE_SPEC.md` §3).

Before any code, three research tracks (own architectural state — CRF/SCR budget, register-audit
grep, Object-Bind/ODT semantics; real compiled LLVM IR shape at `-O0`/`-O1`; CHERI precedent) were
run and cross-checked. **This is a revision of the first version of this document.** The first version
was synthesized from only the first two tracks — the CHERI-precedent track failed to produce output
on the first run and had to be re-run separately, afterward. That gap led the first version to reject
per-global individually-bounded capabilities as "mechanically impossible at scale," reasoning only
about *persistently-live register-resident* capabilities (N live CRF registers for N globals — a real
impossibility, the CRF is a hard 4-bit/16-register file). It did not consider capabilities minted once
and stored *in memory*, loaded into a scratch register on demand — which is exactly what real CHERI
does via `__cap_relocs`, and which this project's own `OCL.C`/`OCS.C` instructions (Milestone 7)
already support. This revision reconciles that gap. Section 1 below is the corrected design; the
mechanism it lands on differs from the first draft's Section 1 in a real, substantive way, not a
wording fix.

## 1. Chosen mechanism: per-global individually-bounded capabilities, minted once at bootstrap and cached in an in-memory capability table — CHERI's real property, adapted (not copied 1:1) to Veda-Core's own 256-entry ODT budget

**Decision**: every module-scope `int g;`/`static int s;` in scope for v1 (Section 4) gets its own
individually-bounded capability, with `Base`/`Length` narrowed to exactly that symbol's own bytes —
the real CHERI `CBM_Conservative` property (a global's own bounds, not a shared whole-region bound
trusted at the symbol-offset level). Where this design *deliberately* departs from CHERI's own literal
mechanism is *how many ODT `Object_ID` entries that costs*: not one `Object_ID` per global (CHERI's
literal `__cap_relocs` shape, minting each global's capability directly off a `Base` value that is
itself a raw address), but **one `Object_ID` for the whole `.data+.bss` region and a second for the
whole `.rodata` region** (identical two-region split the first draft already chose, Section 1's own
`.rodata`-vs-`.data/.bss` `Perms` reasoning below is unchanged), with each individual global's own
precisely-bounded capability derived from one of those two region capabilities via `OCA`-then-
`CSetBounds` — **performed once, at program bootstrap, not once per access** — and the resulting
128-bit tagged capability **stored into a small in-memory capability table via `OCS.C`**, one 16-byte
slot per tracked global. Every real access site thereafter does one `OCL.C` (load the
already-exactly-bounded capability for this specific global from its table slot into a scratch
capability register) followed directly by `OCL.D`/`OCS.D` — no `OCA`/`CSetBounds` at any access site
at all, since the capability loaded from the table is already narrowed to exactly that global's own
bytes.

**Why this is the right reconciliation, not a retreat from CHERI's property**: CHERI's own real
mechanism (see the research below) does exactly this shape too — `__cap_relocs` capabilities are
individually bounded *per global*, but they are minted once (by `cheri_init_globals_impl`, walking a
link-time-computed relocation table) and then live in ordinary tagged memory, not in N permanently-
reserved capability registers; a running CHERI program loads a global's capability into a register
on demand via an ordinary tagged `clc`/`csc`-family load, exactly the role this design gives
`OCL.C`. The first draft's rejection of per-global bounds conflated "N globals need N live capability
registers" (true and impossible) with "N globals need N `Object_ID`s" (a separate, independent
question this design answers differently from CHERI's own literal answer, for a concrete, cited
reason below) with "N globals need N individually-bounded capabilities" (true, and now adopted, since
memory — not the CRF, and as shown below, not really the ODT either — is what actually holds them).

**Why NOT one `Object_ID` per global (CHERI's literal 1:1 mechanism), re-derived against this
project's own real, current ODT size**: `rtl/MILESTONE_PLAN.md`'s own Milestone 1 section states the
real, currently-built constraint plainly: *"sized to 256 entries for this milestone (real
silicon-area consciousness), not Sail's own 8.4M — `Object_ID` is masked to its low 8 bits for
indexing. Scaling this to anything near the real ID-space width is explicitly deferred, later work,
not attempted here."* This is a real, currently-binding truncation, confirmed directly against the
real RTL (`rtl/veda_core.tlv:994`, `$veda_odt_idx[7:0] = $veda_object_id[7:0]`) — not a saturating
clamp, a literal low-8-bit index, so two *simultaneously-bound* objects whose `Object_ID`s differ by a
multiple of 256 alias the same physical ODT slot. A grep across this project's own existing `.S`/test
corpus already finds real, in-use `Object_ID` literals up to 421 (`veda_alloca_protect_entry.S`'s own
`Object_ID`s 416-421), which only work today because no two of those IDs are simultaneously bound
*and* congruent mod 256 — the space is already being used carefully, not idly. Giving every global its
own permanent, program-lifetime `Object_ID` (CHERI's literal mechanism) means a real test program with,
say, 40 globals needs 40 more simultaneously-live entries *on top of* however many `Object_ID`s the
program's own compartment ceremony already needs concurrently (CODE + DATA + type-authority +
STACK_REGION per live compartment, e.g. `veda_compartment_entry.S`'s own 400-405 plus a nested
callee's own block) — for a program with several compartments and a non-trivial global count, this is
a real, concrete collision risk against a 256-slot space, not a hypothetical one, especially since
`Object_ID`s are hand-picked by grep-audit today with no compiler-enforced collision detection at all
(the exact same risk category the alloca-region-collision bug in Milestone 12 already demonstrated is
real, not theoretical, for a structurally similar reason). Two `Object_ID`s (one per data region)
instead of N is a deliberate, explained adaptation of CHERI's mechanism to Veda-Core's own real,
current resource ceiling — not a rejection of CHERI's individually-bounded-capability property, which
this design still delivers, just via table-resident capabilities derived from those two regions
instead of via N region `Object_ID`s of their own.

**Why the in-memory capability table (not per-access `OCA`/`CSetBounds` narrowing, the first draft's
own choice) is the correct v1 mechanism now that per-global bounds are in scope**: narrowing at every
access site (Phase B0's own repeated pattern for stack locals) is correct when there is no way to
cache the result — a stack local's address is only meaningful within one call's own live SSC binding,
so nothing durable exists to cache. A global is the opposite: the same bounded capability is valid for
the entire program's lifetime, identically across every call, every compartment, every thread — by
ordinary C semantics, computing and storing it once and reusing it is not just an optimization, it is
the architecturally correct model, and is exactly what CHERI's own real system does (mint once at
process start via `cheri_init_globals`, not re-derive per access). Re-deriving via `OCA`/`CSetBounds`
on every single access, as the first draft proposed, would work (mechanically identical primitives),
but would be strictly more instructions per access for no additional safety property, since the bounds
never change between accesses to the same global. `OCL.C`/`OCS.C` (Milestone 7,
`veda_ocl_insts.sail` lines 114-179, confirmed real, Sail-implemented, RTL-mirrored, already tested)
exist for exactly this "round-trip a full tagged capability through memory" role and are reused
unmodified, not extended.

**Why two regions (`.data+.bss` vs `.rodata`), not one** — unchanged from the first draft, still
correct: `veda_compartment_entry.S`'s own real ceremony already treats `Perms` as a per-object-class,
deliberately-chosen field — CODE gets `0x0402` (Execute|Invoke), the ceremony-only DATA capability gets
`0x0400` (no Load/Store), type-authority gets `0x0300` (Seal|Unseal), STACK_REGION gets `0x000C`
(Load|Store) — confirmed by direct read of that file (lines 32-93). A `.rodata`-backed global (a
`const` global, or a string literal) should architecturally get `Perms = 0x0004` (Load only,
`Permit_Store` withheld) so a compiled store into read-only data hard-traps at the hardware permission
check (`cause = 0x13`, PERMIT_STORE Violation) rather than silently succeeding. A `.data`/`.bss` global
needs `Perms = 0x000C` (Load|Store), identical to STACK_REGION. Stack locals never had this
distinction (an alloca is always read-write), so this is a genuinely new per-object-class decision
Milestone 13 must make that Milestone 12 did not have to. In this revision, the two regions are the
*source* capabilities each per-global entry is narrowed from — the `.rodata` region's own two
`OCA`/`CSetBounds`-derived, table-stored per-global capabilities inherit `Perms = 0x0004` from their
source (permission bits only ever narrow, never widen, under `CSetBounds`/`OCA`, the same real
monotonicity property already re-verified and relied on throughout this project); the `.data`/`.bss`
region's own derived capabilities inherit `0x000C`.

**Why NOT a new SCR (a 4th, "GDC"-style Special Capability Register)** — unchanged from the first
draft, still correct: mechanically there is room — `veda_scr` has only 3 real members
(`VEDA_SCR_ODA`/`_TSC`/`_SSC`, `veda_types.sail:250`, encoded in a 5-bit field with 29 of 32 values
unused, `veda_cap_insts.sail:689-693`) — but every existing SCR's own persistence semantics is wrong
for this job. TSC is thread-scoped, re-established per thread switch. SSC is *deliberately* cleared on
every single `OCInvoke`/`OCRETURN` crossing (`SSC_STACK_SPILL_CAPABILITY_DESIGN.md` §2, "deliberately
NOT persistent-and-OCInvoke-transparent") — that clearing exists specifically to stop a callee
compartment from inheriting the caller's stack. A global's backing region capability is
architecturally the *opposite*: the same `Object_ID`/`Base`/`Length` must be visible identically across
every compartment entry, every distinct compartment in the program, and every thread. This
reconciliation doesn't change this reasoning; if anything it strengthens the case for the in-memory
table over a register-resident SCR, since the table itself, once populated, needs no per-crossing
re-establishment at all — only the two region capabilities used to populate it (or, after bootstrap,
not even those, since the table's own contents are the durable artifact and the two region
capabilities are only needed again if a table slot is ever re-derived).

**Why not a 17th CRF slot** — unchanged, still correct: `vcapidx` is a hard 4-bit field
(`veda_types.sail:24-25`) — a 17th general-purpose capability register does not exist without a real
ISA change, out of scope for a toolchain-only milestone.

**Consequence — this is honestly NOT a purely toolchain-only milestone, and this revision makes that
consequence larger, not smaller, than the first draft's.** The first draft already flagged that a
persistent capability must be established once, before any compartment is entered, and held across
`OCInvoke`/`OCRETURN` crossings. This revision requires that *plus* a new, real bootstrap-time
minting loop (Section 3) that walks every in-scope global, performs `OCA`+`CSetBounds` once per
global, and writes the result into the capability table via `OCS.C` — genuinely more bootstrap work
than the first draft's two-region-bind-and-done plan, in exchange for per-global bounds instead of a
per-access-narrowed shared region. This is named explicitly, not glossed over, in Section 6.

## 2. Sail/RTL: no new instructions required; `OCL.C`/`OCS.C` (Milestone 7) now load-bearing for the core mechanism, not just an alternative

**Existing instructions suffice, unchanged — now including `OCL.C`/`OCS.C` as a first-class part of
the design, not a side note**: `ODT-Populate` (`funct7 = 0000011`, packed `Base<<32|Length<<16|Perms`
descriptor, `VEDA_CORE_SPEC.md` §5.1, real encoding re-confirmed against `veda_ocl_insts.sail:292-306`
this revision) to establish the two region `Object_ID`s (`.data+.bss`, `.rodata`); `Bind`/`Bind-NoTrap`
(Object-Bind I-type, `funct3 = 101`) to populate a capability register from each region `Object_ID`;
`OCA` (`CIncOffset`-equivalent, Custom-2 `funct7 = 0001010`) then `CSetBounds`/`CSetBoundsExact`
(`funct7 = 0001000`/`0001001`) to narrow, once per global at bootstrap, to that global's own
offset/size within its region — the identical `oca`/`csetbounds` sequence Phase B0 already proved for
stack locals (`SSC_STACK_SPILL_CAPABILITY_DESIGN.md`/`TOOLCHAIN_MILESTONE_12_RESULTS.md`), just run
once at bootstrap instead of once per access; and now, load-bearing for the first time in this
project's toolchain work, `OCL.C`/`OCS.C` (Custom-0, same `funct7` as `OCL.D`/`OCS.D`, differentiated
by `funct3 = 100`, targeting a capability register `rd` instead of a GPR) to store each narrowed
per-global capability into its table slot at bootstrap (`OCS.C`) and load it back into a scratch
capability register at each real access site thereafter (`OCL.C`), followed by an ordinary
`OCL.D`/`OCS.D` against that scratch register for the actual 64-bit data access.

**`OCL.C`/`OCS.C`'s real semantics, re-confirmed directly this session (`veda_ocl_insts.sail` lines
114-179, Milestone 7, already implemented and tested, not new)**: both reuse `veda_check_access`
unchanged (line 137/163) — bounds, permission, tag, seal, and generation checking are identical in
kind to `OCL.D`/`OCS.D`, only the access width differs (16 bytes = 128 bits, the capability's own real
on-the-wire width, vs. 8 for `OCL.D`/`OCS.D`). The load path (`VEDA_OCL_C`, lines 134-158) is the one
real access kind in this file that reads the memory-resident out-of-band Tag alongside the 128 data
bits (`read_ram(Read_plain, paddr, 16, true)`, `read_meta = true`, unlike `OCL.D`/`OCS.D`'s `false`) —
`CTag(rd) = tag` means a capability loaded back from the table is only as trustworthy as what a real,
prior `OCS.C` actually wrote there, exactly CHERI's own tagged-memory round-tripping property (bytes
that were never written by `OCS.C`, or were overwritten since by a plain `OCL.D`/`OCS.D`/`NMC_ADD`/
Atomic access — none of which ever touch the tag store — load back untagged, and any subsequent
`OCL.D`/`OCS.D` dereference through an untagged capability register hard-traps with
`VEDA_CAUSE_TAG_VIOLATION`, `veda_check_access` line 66). This is the real hardware property that
makes the capability table safe to place in ordinary `.data`-backed memory rather than needing its own
dedicated protected region: even if some other bug in the program corrupted the table's raw bytes
directly (bypassing `OCS.C`), the corrupted slot loads back untagged and any subsequent access through
it hard-traps rather than silently using forged bounds — the identical trust model CHERI's own
tagged memory provides for its `__cap_relocs`-populated capability table in `.data`.

**What is genuinely new, but is a convention plus a bootstrap routine, not new hardware**: which
registers hold the two region capabilities during bootstrap minting, which register is the
"global-access scratch" register at every real (post-bootstrap) access site, and where the capability
table itself lives in memory. `C15` is unavailable (SSC). `C13` is unavailable (Phase B0's own scratch
convention). Per the first draft's own still-valid reasoning, the register-audit track found no
register in `C0`–`C12` uniformly free across the existing hand-written `.S` corpus as a *persistent*
binding (each is used only as transient scratch) — but this revision needs persistence in a narrower,
cheaper way than the first draft did: only the **table base capability** (pointing at the in-memory
capability table itself, read-write, one region) needs to be persistent across every compartment
crossing; the two region capabilities (`.data+.bss`, `.rodata`) are only needed transiently, during
the one-time bootstrap minting loop, and can be discarded (or reused as ordinary scratch) once every
table slot is populated. This is a smaller persistent-register footprint than the first draft's
two-region-persistent-forever design. The pragmatic answer, consistent with how `C15`/`C13` were each
picked (grep-audit first, then commit): run the same audit and hand-pick one more register (e.g.
`C12`, pending that audit) as the fixed, compiler-reserved "global-table" register, holding a capability
bound over the whole in-memory table (read-write, `Perms = 0x000C`, its own dedicated small `Object_ID`
— a *third* region `Object_ID`, distinct from the `.data+.bss`/`.rodata` source regions, since the
table itself is a real allocation with its own bounds, not literally inside either source region) —
conditionally reserved in `RISCVRegisterInfo::getReservedRegs` exactly like `C15` is. No Sail or RTL
file needs to change to make this work — `getReservedRegs` is a pure LLVM-side register-allocation
concern, identical in kind to Milestone 11's own `C15` reservation.

**Bootstrap timing — the one real new architectural event, still using only existing instructions,
now with a concrete minting loop instead of just two `Bind`s**: at program start, before the first
`OCInvoke`: (1) `ODT-Populate` the `.data+.bss` region, the `.rodata` region, and the capability-table
region (three `Object_ID`s total, up from the first draft's two); (2) `Bind` each into a register;
(3) for every in-scope global, in a fixed, compiler-and-runtime-agreed order (Section 3): `OCA` +
`CSetBounds` off the appropriate source region into a scratch register, then `OCS.C` that scratch
register into the correct table slot (`table_base + slot_index * 16`); (4) discard the two source
region registers (or let them fall out of the persistent set); the table-base register remains bound
in the reserved persistent register for the rest of the program's life. Every real, later access
inside a `veda_compartment` function is then just `OCL.C <scratch>, <table-reg>, <slot-offset>` +
`OCL.D`/`OCS.D <scratch>, <access-offset>` — no `OCA`/`CSetBounds` anywhere outside the one-time
bootstrap loop. This is a new call site (a `_start`-level or shared-bootstrap routine every
compartment-containing program must run first), not new instruction semantics — every instruction
used here (`ODT-Populate`, `Bind`, `OCA`, `CSetBounds`, `OCL.C`, `OCS.C`, `OCL.D`, `OCS.D`) is already
idempotent and general-purpose, with no notion of "compartment context" or "bootstrap phase" baked
into its own semantics.

## 3. LLVM/Clang implementation surface

**New Phase (call it Phase B1) in `VedaShadowPropagation.cpp`, module-wide, NOT entry-block-of-one-
function.** Phase B0's scan (`propagateInFunction`, lines 394-495) iterates `F.getEntryBlock()`'s
`AllocaInst`s — architecturally single-function by construction, since an `alloca` only ever exists
inside the one function that emits it. `GlobalVariable`s are not function-scoped at the IR level at
all: the LLVM-internals track compiled a real probe and confirmed `@g_counter`/`@g_arr` are
referenced directly from both a `veda_compartment`-attributed function and an ordinary unattributed
one in the same module. Phase B1 must instead be a **module-wide pass step** that walks
`for (GlobalVariable &GV : M) for (User *U : GV.users())`, the identical `Value::users()` idiom
`rewriteSignatures()` (line 348, `for (User *U : F->users())`) already uses in this same file for
`Function`, just applied to `GlobalValue`'s own inherited `users()` (`GlobalObject → GlobalValue →
Constant → User → Value`, confirmed against the real checked-out `llvm/include/llvm/IR/Value.h`/
`GlobalVariable.h`). Concretely: Phase B1 runs once, module-wide, before `propagateInFunction`'s
per-function loop, and now (this revision) does strictly more than assign compile-time offsets — it
assigns each qualifying global a **table slot index** (a `DenseMap<GlobalVariable*, uint64_t>`, still
structurally the same map role as the first draft's offset map, but the value now means "which 16-byte
table slot" rather than "byte offset within one shared region"), and separately emits the byte
offset/size/region-selector data the bootstrap minting routine (below) needs to actually derive and
store each global's own capability.

**A structurally new dereference-address-matching rule is required, because global accesses do not
uniformly produce a `GetElementPtrInst`, but they do not uniformly avoid one either — this is the one
place this revision corrects the first draft's own stated reasoning, not just its conclusion.** The
first draft claimed real compiled probes found "zero `= getelementptr` instruction lines anywhere in
the module for any global access" — this was re-checked directly this session with the project's own
real `clang` (`--target=riscv64 -march=rv64i_zicsr -mno-relax -mcmodel=medany -O0`) and is **only true
for compile-time-constant-index accesses**. A literal-index access (`g_arr[1]`) does fold to a GEP
`ConstantExpr` embedded directly as the load/store's own pointer operand, exactly as the first draft
said, e.g.:
```llvm
%0 = load i64, ptr getelementptr inbounds ([8 x i64], ptr @g_arr, i64 0, i64 1), align 8
```
But a **runtime-variable-index access** (`g_arr[i]`, `i` a function parameter or loop variable — the
more common real-world pattern, and the exact pattern Milestone 12's own verification test used for
stack locals, `lower[i]=i`) compiles to a genuine `GetElementPtrInst`, a real SSA value, not a
`ConstantExpr`:
```llvm
%arrayidx = getelementptr inbounds nuw [8 x i64], ptr @g_arr, i64 0, i64 %0
%1 = load i64, ptr %arrayidx, align 8
```
(re-confirmed directly this session with a three-function probe — constant-index, single
runtime-index, and a `lower[i]=i`-shaped loop — all three compiled with this project's real `clang`;
the loop case, the closest analogue to Milestone 12's own test pattern, emits two ordinary
`getelementptr` *instructions* per iteration body, not ConstantExprs). Phase B0's existing
GEP-propagation code (`if (auto *GEP = dyn_cast<GetElementPtrInst>(&I))`, line 565) already handles
the instruction shape correctly for any pointer chain it walks — the gap the first draft actually
needed to name is narrower than "zero GEP instructions ever": it is that `dyn_cast<GetElementPtrInst>`
*structurally cannot* fire when the pointer operand is a `ConstantExpr` GEP (a `Constant`, not an
`Instruction`), which **does** happen for constant-index global accesses and needs its own path. Phase
B1's own Load/Store address resolution must therefore handle **both** shapes uniformly by pattern-
matching `dyn_cast<GEPOperator>(Addr)` — the real LLVM idiom that covers both a `GetElementPtrInst` and
a GEP `ConstantExpr` through one common interface — and compute the byte offset via
`GEPOperator::accumulateConstantOffset` (confirmed present, `llvm/include/llvm/IR/Operator.h:538`)
rather than reusing Phase B0's instruction-only GEP-shadow-lookup path as-is. The `dyn_cast<GEPOperator>`
recommendation itself is unchanged from the first draft and is still the right fix; what changes is
why: not because global accesses never produce a real instruction, but because they produce *both*
shapes depending on whether the index is compile-time-constant, and only `GEPOperator` covers both
uniformly. A direct-`@name`-operand case (offset 0, e.g. a scalar global with no indexing at all) is a
third, degenerate shape (neither a `GetElementPtrInst` nor a GEP `ConstantExpr`) that must also be
handled as offset-0 into the global's own slot.

**Sizing gate, matching Phase B0's own "diagnose and leave unrewritten" convention exactly.** Phase
B0 already uses `DataLayout::getTypeAllocSize` on the alloca's own `AllocatedType`
(`VedaShadowPropagation.cpp:469`); Phase B1 reuses the identical API on `GV->getValueType()`. But
`getTypeAllocSize` is unsafe to trust unconditionally for a `GlobalVariable`: the LLVM-internals track
empirically compiled `extern unsigned long g_incomplete_arr[];` (an incomplete C array type) with the
project's real `clang`/flags and got real IR `@g_incomplete_arr = external ... global [0 x i64]`,
where `getTypeAllocSize` returns **0**, not the real cross-translation-unit size — a genuinely unsafe
input, not hypothetical. A same-track probe of a *complete*-type extern
(`extern unsigned long g_complete_extern;`) correctly sized to 8 bytes, but is still
`GV->isDeclaration() == true`. Phase B1 must gate on `!GV.isDeclaration()` (equivalently
`GV.hasInitializer()`, `llvm/include/llvm/IR/GlobalVariable.h:110`) — i.e., **only globals actually
defined in this translation unit are given a table slot and rewritten in a first version**; any
qualifying use inside a `veda_compartment` function of a global that fails this gate is left
completely unrewritten (an ordinary, un-redirected load/store, which will purecap-trap if actually
executed) and should be diagnosed via `F.getContext().emitWarning`, mirroring `isAmbiguousAllocaPhi`'s
own "diagnose and skip" posture rather than Phase B0's `emitError`.

**Function-local `static` lowering to module-scope `GlobalVariable` with internal linkage — CONFIRMED,
not an open risk.** The first draft listed this as unverified. It was independently compiled and
inspected this session, with this project's own real `clang`/flags: `static unsigned long s_counter;`
inside a function named `thread` lowers to
```llvm
@thread.s_counter = internal global i64 0, align 8
```
— a genuine module-scope `GlobalVariable`, `internal` linkage, `funcname.varname` naming, confirmed
directly, not assumed from general LLVM knowledge. (The mangled name and `unnamed_addr` presence can
vary slightly by clang version/flags; the substantive, load-bearing fact — that it is a real
module-scope `GlobalVariable` reachable by exactly the same `for (GlobalVariable &GV : M)` scan Phase
B1 already uses for ordinary globals — is confirmed and needs no special-casing in Phase B1 at all.)
This item is removed from Section 6's open risks below.

**New runtime helper chain — now two chains, not one, because this revision has two genuinely
different jobs: one-time bootstrap minting, and per-access table lookup.**

*Bootstrap minting* (`compiler/veda_compiler_rt.c`/`runtime/veda_rt.c`/`runtime/veda_rt_asm.S`, new,
analogous in ABI shape to `veda_rt_ocl_stack_d`/`veda_rt_ocs_stack_d`'s own real pattern but
structurally new since nothing in Milestones 11/12 minted N capabilities in a loop): a
`veda_rt_init_globals()` routine, called once from the shared bootstrap sequence (Section 2) before
the first `OCInvoke`, iterating a **compiler-emitted table** — not a linker-emitted relocation section
(see below, this is a real, checked departure from CHERI's own literal mechanism) — of
`{ region_selector, region_offset, size, table_slot }` tuples, one per Phase-B1-qualifying global,
performing `oca`/`csetbounds`/`ocs.c` for each and writing the result into the real in-memory
capability table.

*Per-access load path*, mirroring `veda_rt_ocl_stack_d`/`veda_rt_ocs_stack_d`'s own real ABI shape:
`veda_rt_ocl_global_d`/`veda_rt_ocs_global_d` (`compiler/veda_compiler_rt.c`) →
`veda_ocl_global_d`/`veda_ocs_global_d` (`runtime/veda_rt.c`) →
`veda_ocl_global_d_scratch_asm`/`veda_ocs_global_d_scratch_asm` (`runtime/veda_rt_asm.S`), performing
`ocl.c <scratch_cap>, <table-reg>, <slot_offset>` then `ocl.d`/`ocs.d <gpr>, <scratch_cap>,
<access_offset>` — no `oca`/`csetbounds` at the access site at all, a real, load-bearing difference
from Phase B0's stack-local path (which narrows fresh on every access) and from the first draft's own
originally-proposed global-access path (which also narrowed fresh on every access). The load path must
return its value directly in `a0` (`uint64_t veda_ocl_global_d(uint64_t slot_offset, uint64_t
access_offset, uint64_t size)`), not via an out-param — Milestone 12's own finding 3 (an out-param
write-back is fundamentally incompatible with live purecap enforcement, since the writing function's
own prologue spill would itself need to be purecap-safe, and provenance tracking is purely
intraprocedural) applies identically here. All new runtime helper functions — both the bootstrap
minting routine and the per-access load/store wrappers — must themselves carry
`__attribute__((veda_compartment))` (Milestone 12's own finding 2: purecap enforcement is global to
`veda_mode`, not scoped per-function). `access_offset` (within one global's own bytes, needed for a
struct-field or array-element access within an already-narrowed per-global capability) is a genuinely
new parameter beyond Phase B0's stack-local path, needed because the table-loaded capability is bounded
to exactly one global, not a whole region, so any nonzero-offset access into that global's own
interior must still pass its own offset through to `OCL.D`/`OCS.D`.

**Whether a linker-emitted relocation table (CHERI's own literal `__cap_relocs` mechanism) is
achievable here — investigated directly this session, answer: no, not with this project's current
toolchain, so the compiler-emitted-table approach above is used instead, not assumed without
checking.** CHERI's real mechanism (see the cited research below) depends on the CHERI-LLVM fork's
own codegen emitting a `__cap_relocs` section, which either a CHERI-aware runtime linker or a static
`cheri_init_globals`-style C-startup routine walks. This project's real linker, checked directly this
session, is stock GNU `binutils` `ld` 2.46 (`toolchain/riscv-collab-gcc/riscv/bin/riscv64-unknown-elf-ld`,
confirmed the actual linker invoked by every existing test script's own `LD=` variable, e.g.
`compiler/run_veda_alloca_protect_test.sh:35`) — `ld --help` shows no `--cap-reloc`/CHERI-related
option at all. This project's own `clang` (`toolchain/llvm-project/build/bin/clang`, built from this
project's own checked-out `llvm-project` tree, `+xveda` target support, not the CHERI-LLVM fork) has
no `__cap_relocs`-emitting codegen either. A linker-emitted relocation table analogous to CHERI's own
is therefore not realistic to depend on for v1. The compiler-emitted-table approach above sidesteps
this entirely and stays inside what this project's real toolchain already does elsewhere: Phase B1
itself (an LLVM `ModulePass`, already-proven infrastructure) computes the `{region_selector,
region_offset, size, table_slot}` tuple set at compile time and emits it as ordinary compiler-generated
data (e.g. a synthesized `llvm.global_ctors`-independent constant array `GlobalVariable`, initialized
directly by the pass, in `.data` — no new linker feature, no new section type, no relocation-processing
code anywhere outside this project's own already-proven LLVM pass infrastructure). The bootstrap
minting routine (`veda_rt_init_globals`) is ordinary compiled/hand-written C/asm that walks this
ordinary array at a known symbol — ordinary global-array iteration, not relocation processing. This is
a real, deliberate departure from CHERI's literal implementation strategy, made because CHERI's own
strategy assumes linker/runtime-linker capabilities this project's real, current toolchain does not
have, not because the property being delivered (per-global bounds, computed once, applied on demand)
differs.

## CHERI precedent, cited directly, now folded into and consistent with the design above

CHERI's purecap ABI protects C/C++ global and static (`.data`/`.bss`/`.rodata`) variables with an
**individually-bounded capability per symbol**, not one coarse capability over the whole data segment
— the property Section 1 above adopts. The mechanism is `__cap_relocs` — a link-time-computed,
compile-time-emitted metadata table that a small piece of C-startup code (or, for dynamically-linked
objects, the run-time linker) walks once at process/image start to materialize (mint) one precisely-
bounded capability per global — the property this design's own bootstrap-minting-loop-into-a-table
adopts, adapted to a compiler-emitted table since this project's own toolchain has no linker-level
equivalent (see above).

1. **Per-symbol, individually-bounded capabilities**: the official CHERI-RISC-V ELF psABI
   (`CTSRD-CHERI/cheri-elf-psabi`, `riscv.md`, "Capability Relocations Section") defines the on-disk
   `cap_reloc` struct (`cr_location; cr_base; cr_offset; cr_length; cr_flags;`) and states: "`cr_length`:
   The length used for the bounds of the derived capability. This will be computed at link time from
   the size in the ELF symbol table of the symbol being pointed [to]" — a per-symbol size. The
   reference implementation, `cheri_init_globals.h` (`CTSRD-CHERI/clang`,
   `lib/Headers/cheri_init_globals.h`), in `cheri_init_globals_impl()`, per relocation entry: `src =
   __builtin_cheri_bounds_set(src, reloc->size);` — each global gets its own `bounds_set` call with
   that global's own size, exactly the per-global `CSetBounds` this design's bootstrap loop performs.
2. **A separate mechanism from stack bounds**: the CHERI C/C++ Programming Guide ("Bounds from the
   compiler and linker") states two separate clauses — compiler-generated stack bounds vs.
   linker-derived global bounds — matching this project's own separate Phase B0 (stack, per-access
   narrowing, no durable capability) vs. Phase B1 (globals, once-at-bootstrap narrowing plus a durable,
   table-resident capability) split.
3. **No dynamic-linker dependency for the static/bare-metal case**: the official psABI spec states the
   capability table "is filled in by the dynamic linker during loading, AND by the C startup code in
   statically linked executables" — direct proof static executables perform this fixup themselves.
   CherIOS (an official CTSRD-CHERI bare-metal OS) builds with `-relative-cap-relocs
   -no-dynamic-linker` — direct evidence this works with zero dynamic linker, exactly this project's
   own situation (no dynamic loader today). This is why this design's own bootstrap routine
   (`veda_rt_init_globals`, a C-startup-time routine, not a linker feature) is the right shape to adapt
   — it mirrors CHERI's own *static*-executable path, the one CHERI path that does not depend on
   linker/runtime-linker capabilities this project's toolchain lacks.
4. **Compatibility costs CHERI documents, noted for completeness, not fully applicable here**: CHERI
   flags that cross-object-file tentative/common-symbol definitions may not resolve size until
   run-time-linker time — does not apply the same way to this project's fully statically linked build
   with all sizes link-time-known (matches Section 4's own `!isDeclaration()` scope boundary). CHERI's
   general capability-compression/representability caveat for large/oddly-sized objects is a
   Veda-Core-inapplicable concern in the same form (Veda-Core's own capability encoding,
   `veda_types.sail`, is not a compressed/representability-limited encoding the way real CHERI's
   128-bit compressed format is — a distinct, real design difference between the two projects' own
   capability encodings, not re-litigated here).

## 4. Scope: in for v1, explicitly deferred

**In scope for v1**:
- Module-scope `int g;`-style globals and function-local `static` variables **defined in the current
  translation unit** (`!isDeclaration()`, confirmed empirically to include the function-local `static`
  case), of scalar or fixed-size-array/struct type, accessed via a direct `@name` operand, a
  constant-offset GEP `ConstantExpr`, or a runtime-variable-offset `GetElementPtrInst` — all three real
  compiled shapes, confirmed this session — from inside a `veda_compartment`-attributed function.
- The `.data`/`.bss` vs `.rodata` `Perms` distinction (`0x000C` vs `0x0004`) applied to each global's
  own table-resident capability, matching real precedent already established by
  `veda_compartment_entry.S`'s own per-object-class `Perms` choices.
- Both zero-initialized (`.bss`) and constant-data-initialized (`.data`) globals, handled identically
  at the IR-pass level — Phase B1's own sizing/slot-assignment logic depends only on
  `GV->getValueType()` via `getTypeAllocSize`, not on the initializer's contents. Should be verified
  with one dedicated `-O0` test of each kind before being called proven, not merely asserted.
- Function-local `static` variables — confirmed this session (see above), no longer conditional.
- A bounded, compile-time-known number of globals per program, consistent with a small, fixed
  in-memory capability table sized at compile/link time (see open risk below on exact sizing policy).

**Deferred, explicitly, matching Milestone 12's own "Not yet built" honesty precedent**:
- **Extern globals not defined in this translation unit** (`isDeclaration() == true`), especially
  incomplete-array-typed ones — a real, already-present example exists in this project's own
  `runtime/veda_rt.c:6-7` (`extern char _end[];`) — where `getTypeAllocSize` cannot be trusted at all.
  Left completely unrewritten (no table slot assigned); diagnosed, not silently mis-sized.
- **Rewriting a global access found inside a non-`veda_compartment`-attributed function**, even if
  that function is transitively reachable from inside a live compartment. V1 only rewrites uses found
  inside functions that already carry `veda_compartment`, matching Milestone 12's own finding 2
  precedent. An unattributed function's own untouched global access continues to work exactly as it
  does today outside any compartment.
- **Subobject/struct-field-internal bounds** — identical scope boundary Milestone 12 already drew,
  same CHERI `CBM_Conservative` justification: isolating separate globals from each other is in scope
  (and, per this revision, individually per-global, matching CHERI's own real default more closely
  than the first draft's coarse-region choice did); isolating fields within one global's own struct
  layout from each other is not.
- **A linker-emitted, `__cap_relocs`-analogous relocation mechanism** — investigated and rejected for
  v1 (see Section 3): this project's real, current `ld`/`clang` have no such feature. The
  compiler-emitted-table approach is the v1 answer; revisiting this if/when the toolchain grows real
  linker-level capability-relocation support is a legitimate later-milestone question, not settled
  permanently here.
- **Multiple independent compartments in the same program concurrently sharing the same global**,
  under the ODT's exclusive-by-default owner-hart binding policy (`VEDA_CORE_SPEC.md` §4.1) — no
  existing test corpus exercises multiple live compartments in one program at all; deferred as a real
  open question, not silently assumed safe. This revision's table-resident design makes this slightly
  easier in principle (every compartment reads the same table through the same reserved register, no
  per-compartment re-binding needed for *read* access), but the underlying ODT exclusive-ownership
  question for the three region `Object_ID`s themselves is unchanged and still unresolved.
- FPR/vector-typed globals, non-64-bit-width accesses — inherits the pass's own already-existing,
  hardware-forced 64-bit-only dereference-rewrite scope.

## 5. Verification test, mirroring Milestone 12's own CHERI-inter-object-overflow pattern

Directly modeled on `veda_alloca_protect_demo.c` and the official CHERI inter-object test it itself
was modeled on: two adjacent globals, `unsigned long g_lower[4]; unsigned long g_upper[4];`, both
inside `.bss` (zero-initialized, in scope per Section 4), accessed from one `veda_compartment`
function via a runtime-variable index (the more representative real-world shape, per Section 3's own
corrected finding — not a compile-time-constant index, which would exercise a different Phase B1 code
path). A `VEDA_OOB_INDEX`-controlled write: default `3` (in-bounds, `g_lower[3]`) must run to
completion returning a real, checkable value (e.g. `g_lower[3] + g_upper[0]`, not merely
absence-of-trap, matching Milestone 12's own `113` convention). Because this revision gives
`g_lower`/`g_upper` **separate, individually-bounded table capabilities** rather than one shared region
capability, `VEDA_OOB_INDEX=4` (one element past `g_lower`'s own 4-element bound) must hard-trap with
`VEDA_CAUSE_BOUNDS_VIOLATION` **before ever reaching `g_upper`'s own bytes at all** — a strictly
stronger, and more representative-of-real-CHERI, property than the first draft's coarse-region design
would have delivered (in the first draft's design, an OOB index landing inside a *different* global
within the *same* shared region would only be caught if it happened to also exceed that specific
global's own `CSetBounds`-narrowed scratch capability at the access site — correct for this specific
adjacent-array case, but the isolation boundary was the access-site narrowing, not the object itself;
in this revision, the isolation boundary is the per-global table capability itself, matching CHERI's
own real per-object default more directly). Traced via `--trace-instr --trace-exception --trace-csr`
and confirmed byte-for-byte against the expected `mtval = (scratch_idx<<5)|0x01`, exactly Milestone
12's own proof discipline, through the **new** global-access scratch register (not `C13`, to prove
Phase B1's own path is what caught it, not an accidental reuse of Phase B0's). A second, orthogonal
test proves the `Perms` split: a `const unsigned long g_ro = 7;` global, a compiled store attempt into
it from inside a `veda_compartment` function, expected to hard-trap with `PERMIT_STORE Violation`
(`cause = 0x13`) via that global's own table-resident capability's `Perms = 0x0004` (inherited from the
`.rodata` region capability it was narrowed from) — a property neither Milestone 11 nor 12 had any
equivalent for. A **third, new** test this revision specifically motivates: confirm the bootstrap
minting loop itself is correct — read back each global's table slot via a direct `OCL.C` immediately
after `veda_rt_init_globals()` runs (before any compartment touches it) and assert `Base`/`Length`/
`Perms`/`Tag` match the expected per-global values exactly, isolating a bootstrap-minting bug from an
access-path bug if the first two tests ever fail (the first draft's design had no equivalent
bootstrap-correctness checkpoint, since it had no bootstrap minting loop to check).

## 6. Open risks and unresolved questions, stated honestly

- **The persistent table-base register, and the two transient bootstrap-only region registers, have
  not yet been grep-audited or picked.** Milestone 11 and 12 both did a real, cited grep audit before
  committing to `C15`/`C13`; this document names the need but has not performed that audit — it must
  happen before implementation, per this project's own established discipline, not be assumed to land
  on `C12`.
- **Bootstrap-timing mechanics are unspecified in detail.** This document establishes *that* the
  minting loop must run once before any `OCInvoke`, not the exact mechanism (a new `_start`-level
  routine? a convention every compartment entry point must call first, idempotently?). This is real,
  load-bearing runtime/linker-level design work this milestone's own toolchain-only framing cannot
  avoid, and is not yet resolved here.
- **Capability-table sizing policy is unresolved.** This revision needs a small, fixed-size in-memory
  table (one 16-byte slot per in-scope global), but nothing here yet specifies how that size is
  decided — a fixed compile-time upper bound the compiler pass enforces (erroring or diagnosing if a
  program has "too many" globals), or a linker-computed exact size (matching the count Phase B1 itself
  determines at compile time, since the compiler already knows the exact global count when it emits
  the tuple table)? The tuple table itself (Section 3) already needs exactly this same count, so the
  natural answer is "exactly as many slots as the tuple table has entries, sized by the compiler pass
  itself, no separate policy needed" — but this has not been implemented or tested, and is named here
  as the concrete next design step, not assumed solved by this paragraph's own reasoning alone.
- **Whether the ODT's 256-entry real budget (`rtl/MILESTONE_PLAN.md`, re-confirmed this session
  against `rtl/veda_core.tlv:994`'s own literal `[7:0]` truncation) has room for a *third*
  program-lifetime `Object_ID` (the capability-table region itself, on top of the first draft's
  `.data+.bss`/`.rodata` pair) alongside whatever a realistic test program's own compartment ceremony
  already needs concurrently — three more entries is a much smaller ask than the first draft's
  rejected N-globals-worth of entries, but it has not been checked against `runtime/veda_rt.c`'s own
  allocator pool logic or a real multi-compartment test's own concurrent `Object_ID` usage, and should
  be before implementation, not assumed fine because three is a small number.
- **`-O2`/`-O3` were never tested** (only `-O0`/`-O1`, matching this pass's own established
  never-target-higher-optimization convention) — if a future change ever raises the target
  optimization level, both the ConstantExpr-GEP and GetElementPtrInst shapes this design depends on
  should be re-verified, not assumed stable. This revision depends on *both* shapes being handled
  correctly (a strictly larger surface than the first draft's single-shape assumption), making this
  risk slightly more consequential than before, not less.
- **The compiler-emitted tuple table's own exact IR/data shape is not yet designed.** Section 3 names
  the concept (a synthesized constant array, analogous in spirit to but not the same mechanism as
  CHERI's `__cap_relocs` section) but does not specify the real LLVM IR construct Phase B1 should
  emit it as (a `ConstantArray`-initialized internal `GlobalVariable`? A `ConstantStruct` array, one
  struct per global, matching the four-field tuple exactly?) or how `veda_rt_init_globals` locates it
  (a fixed, reserved symbol name the pass always emits, checked by the runtime at a known name?) — a
  real, concrete next design step, not yet resolved here.
- **Multi-compartment sharing of one global under the exclusive-by-default owner-hart Bind policy**
  (`VEDA_CORE_SPEC.md` §4.1) is named as deferred (Section 4) but not designed around at all — this
  revision's table-resident design likely makes *read*-side sharing simpler in principle (every
  compartment reads through the same reserved register, once bootstrap has run), but the three region
  `Object_ID`s' own Bind-time ownership under this policy, and what happens if two compartments are
  ever bootstrapped independently rather than sharing one program-wide bootstrap, is not designed
  around at all.
- **A newly surfaced question this reconciliation itself raises, not present in either the first draft
  or the CHERI research alone**: CHERI's own `__cap_relocs` minting happens *before* `main`, in a
  single-threaded, pre-any-compartment context, by construction (C-startup or the dynamic linker, both
  inherently "nothing else is running yet" contexts). This project's own bootstrap routine
  (`veda_rt_init_globals`) is likewise pre-`OCInvoke`, but this project also has a real, already-built
  scheduler/thread model (`runtime/veda_sched_asm.S`, TSC re-priming per thread switch, cited
  elsewhere in this project's own docs) that the first draft's design never had to interact with
  either. Whether `veda_rt_init_globals` must run exactly once ever (a real global, one-time
  minting, matching CHERI's own model, requiring the scheduler to guarantee it never re-runs per
  thread) or could safely be idempotent-and-re-run-per-thread (simpler to reason about, but wastefully
  re-minting identical capabilities) is a genuinely new question this reconciliation surfaces — neither
  the original draft (which had no bootstrap minting loop at all, only two static `Bind`s) nor the
  CHERI research (which is single-threaded/pre-scheduler by construction in every cited source) named
  this, and it is not resolved here.
