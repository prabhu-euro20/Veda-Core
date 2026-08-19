# Veda-Core -- Next Steps: A Rigorous Roadmap

**Date:** 2026-07-23 (original analysis). Parts 1, 2, and 4 rewritten 2026-08-09.

**Status update, 2026-07-25**: Tier 1 item 1 (`OCL.C`/`OCS.C`, §2.1) is
now **done** in both Sail and RTL -- see `MILESTONE_7_RESULTS.md`. Tier 1
item 2 (Sail-side Veda-Atomic/`NMC_ADD.W` test-coverage parity, §2.2) is
also now **done** -- see `MILESTONE_V-B_RESULTS.md`'s 2026-07-25 addendum,
16/16 self-check tests passing. Tier 1 item 3 (RTL `Rebind`/`Bind-NoTrap`,
§2.3) is also now **done** -- see `rtl/MILESTONE_8_RESULTS.md`; along the
way it closed a real, previously-undetected gap (the bind-mode field was
decoded since RTL Milestone 1 but never actually checked, so every
non-zero mode silently executed as plain `Bind`), and proved `Rebind`'s
own real-relocation property against a real physical address, not just
capability metadata. **Tier 1 is now fully closed.** Tier 2 item 4 (real
RTL trap infrastructure, §2.4) is also now **done** -- see
`rtl/MILESTONE_9_RESULTS.md`: a real Zicsr-lite CSR file
(`mtvec`/`mepc`/`mcause`/`mtval`), real `CSRRW`/`CSRRS`/`MRET` (standard
RISC-V encoding), and a real PC redirect wired to every Sail
"use"-family violation, closing the largest remaining Sail/RTL
architectural divergence and finding five real, distinct bugs along the
way (spanning a stale Milestone-1 test assumption, a trap/resume PC
placement mistake repeated across three files, three unrelated tests
broken by the new trap infrastructure exposing their own latent
soft-fail assumptions, a register-naming collision, and a too-tight
cycle budget). Deliberately still deferred within this same item: plain
`Bind`'s own ODT-miss hard-trap, and `ODT-Populate`/`ODT-Destroy`'s own
`Illegal_Instruction` privilege trap (a distinct exception class) -- both
real, named, separate follow-ons, not silently folded in. **Tier 2 is
now fully closed.** Tier 3 item 5 (`CInvoke`-equivalent, §2.6) is also
now **done** -- see `rtl/MILESTONE_10_RESULTS.md`: `OCInvoke`, term-for-
term adapted from real CHERI's `CInvoke` (CHERI ISA spec p.209), in both
Sail and RTL. `c15` (the last CRF entry) serves as the fixed "IDC"
target, proportional to CHERI's own real `C31` convention (itself just
the last entry in CHERI's 32-register file, not a separate physical
register -- a real fact this milestone's own research corrected from an
earlier, vaguer assumption). Deliberately still deferred within this
same item, stated plainly: a real `PCC` register and real
instruction-fetch-time capability enforcement (`OCInvoke` redirects PC
directly to the resolved target address instead, achieving the real
"atomic unseal-and-jump" property without that storage) -- this would
require changes to the RVA23 base core's own fetch stage, out of bounds
for `veda_core.tlv`-only work, and remains a distinct, separately-scoped
future item. Tier 3 item 6 (capability-authority-gated
`ODT-Populate`/`ODT-Destroy`, §2.5) is also now **done** -- see
`rtl/MILESTONE_11_RESULTS.md`: `OSpecialRW` + the ODA (Object Descriptor
Authority), Veda-Core's own single Special Capability Register,
term-for-term adapted from real CHERI's own `CSpecialRW`/SCR model
(CHERI ISA spec §4.3.6). `ODT-Populate`/`ODT-Destroy` now legal via a
real OR -- ordinary privilege (unchanged since Milestone 4) **or** a
live, unsealed, `Permit_Access_System_Registers`-carrying capability
delegated into the ODA -- matching CHERI's own layered privilege model
exactly, activating `Permit_Access_System_Registers` for the first time.
Found and honestly worked around a real Sail-side scope limit along the
way: this project's own Sail test config has S/U-mode disabled, so
privilege can never actually drop below Machine there, making a
genuinely privilege-independent proof structurally impossible in Sail
with the existing config -- RTL's own independent `veda.droppriv`
supplied the one real, end-to-end proof instead. Zero design/Sail/RTL
bugs found this milestone, a first since Milestone 8. The owner-hart
hardware enforcement piece of Tier 3 item 7 is now **done** -- see
`rtl/MILESTONE_12_RESULTS.md`: a real `owner_hart` byte in every ODT
entry, checked and claimed at Bind/Rebind time in both Sail and RTL,
closing `VEDA_CORE_SPEC.md` §4.1's own long-named gap. **The remaining
half of Tier 3 item 7 -- real multi-hart RTL architecture and shared-ODT
arbitration between genuinely concurrent harts -- stays open**; it was
always the larger, separate undertaking, and owner-hart enforcement was
verified via direct ODT-state injection standing in for a second hart
(neither this project's single-process Sail simulator nor its
single-core RTL can produce one), not genuine concurrent execution.
**Milestone 13** (`rtl/MILESTONE_13_RESULTS.md`) then closed
`MILESTONE_9_RESULTS.md`'s own separately-named, deliberately-deferred
gap: plain `Bind`'s ODT-miss hard-trap (`cause = 0x05`) is now real in
RTL too (Sail already had it). A full grep of the existing test corpus
before writing any RTL found five pre-existing tests relying on plain
`Bind`'s old soft-fail behavior against a never-populated/destroyed
`Object_ID`; each was fixed by switching to `Bind-NoTrap` -- the
already-correct instruction for that purpose since Milestone 8 -- not a
workaround. Also closed a real, previously-unnoticed Sail-side
test-coverage gap (no self-check test had ever directly asserted this
trap's own `mcause`/`mtval`, despite the Sail behavior itself existing
for many milestones). Two more items were then resolved by research
rather than code: **`ODT-Destroy`'s own owner-hart gating question is
now permanently closed, not deferred** -- `VEDA_CORE_SPEC.md` §4.1 was
updated with the real reasoning (CHERI ISA spec §2.3.16's own object-
revocation precedent places that authority with a trusted handler,
independent of current ownership; `ODT-Destroy` was correctly designed
already and should stay privilege/ODA-gated, not owner-gated). **Tier 3
item 5's own long-named "PCC" gap has been rescoped and fully designed**
(`veda-core/PCC_COMPARTMENT_DESIGN.md`) but deliberately not yet
implemented: research found real CHERI's own PCC is a universal,
always-on fetch-time mechanism that doesn't fit Veda-Core's own hybrid,
opt-in architecture at all -- the actual, well-scoped gap is narrower,
`OCInvoke`'s own currently-incomplete compartmentalization bound (a
successful `OCInvoke` redirects PC but nothing constrains subsequent
execution to stay within the invoked capability's own bounds). The
design doc verifies real, concrete Sail extension hooks for this
(`ext_fetch_check_pc`/`ext_handle_fetch_check_error`, and new CSR
addresses `0x7C0`-`0x7C3` in the real RISC-V-spec-reserved custom M-mode
range) and a real, non-obvious finding along the way -- `xret_callback`
is declared `pure`, so automatic hardware save/restore of compartment
bounds across a trap isn't available the way it is for `mepc`; the
design instead makes restoration an explicit software step, consistent
with `mepc`'s own already-established explicit-advance-before-`mret`
convention. **That design is now implemented and verified on the Sail
side** (`veda-core/MILESTONE_14_RESULTS.md`) -- `OCInvoke` genuinely
narrows execution to the invoked compartment's own bounds, fetch outside
them genuinely hard-traps, and the full save/explicit-restore cycle
across a real trap and `mret` is proven end to end, 24/24 Sail tests
passing. Two real, concrete findings surfaced only by actually building
it: a module-ordering conflict (`core` compiles before `Veda`, so the
fetch-check hook's real body had to move to `postlude/step_ext.sail`,
which already requires `Veda_insts`) and a pre-existing Milestone 10
test whose own `Length` fixture needed widening now that the field is
genuinely checked rather than decorative. **The RTL mirror is now also
done** (`veda-core/rtl/MILESTONE_14_RESULTS.md`), the same day: `$instr`
is forced to a real NOP on a PCC violation -- a single, minimal change
that correctly suppresses every downstream write path at the source
rather than auditing each one individually, since this is the one check
in the whole file that's genuinely unconditional rather than gated on a
decoded opcode. Found and fixed two real bugs via an actual
cycle-by-cycle debug trace, neither in the trap mechanism itself (which
worked first try): a second real instance of the Milestone-13-taught
Object_ID-collision class, and two testbenches' own underestimated
cycle budgets. 25/25 RTL tests passing. **Tier 3 item 5 is now fully
closed, in both Sail and RTL.** With the two remaining named gaps
(`OSpecialRW`'s own capability-gating, blocked on a real `Perms`-on-`PCC`
consumer that doesn't exist yet; real multi-hart RTL, a large separate
undertaking) both genuinely not ripe for immediate work, this pass
instead closed a real, previously-unchecked verification gap found while
looking for what else was honestly left: the base RV64I ACT4 conformance
suite (51/51) had only ever been run against the separate, untouched
`rv64i_core.tlv`, never against `veda_core.tlv` itself -- the file
fourteen real RTL milestones have actually modified, including
Milestone 14's own new every-cycle check touching the central `$instr`
signal directly. **`veda-core/rtl/ACT4_CONFORMANCE_RESULTS.md`: 51/51,
0 failed, 0 timed out** -- real, additional confidence that Veda-Core's
own additions have not regressed base RV64I correctness, checked against
the actual file, not a proxy for it.
This document otherwise remains a point-in-time analysis. Parts 1, 2, and 4 below were fully
rewritten on 2026-08-09 to reflect real project state as of that date (Sail through Milestone 22,
RTL through Milestone 25, plus the entire Toolchain track and Minimal OS Kernel that didn't exist
when the paragraph above was written) -- see each section's own evidence rather than assuming this
2026-07-25 narrative alone is still current. Part 3's external-research citations (CHERI-RISC-V
draft status, confidential-computing landscape) were not re-verified in that pass and are dated
2026-07-23; treat them as aging and due for a re-check, not as settled facts.

**Status update, 2026-08-16**: seven days of real work landed since the 2026-08-09 rewrite above,
verified directly against all fourteen new/updated documents in full (not summarized from memory),
cross-checked against current `git log`/`git status` in both `rva23-core` and its Sail fork. This
is a genuine refresh, not a restatement -- Parts 1, 2, and 4 below are updated in place with dated
additions, following this document's own established convention (corrections stated as such, not
quietly folded in).

**Sail, three new/updated milestones beyond 22:** `MILESTONE_21_RESULTS.md` itself was hardened
("Generic-Trap PCC-Reset Hardening") -- ordinary (non-Veda) RISC-V exceptions taken from inside a
live `OCInvoke` compartment previously never reset `veda_pcc_base`/`_length` at all, a real bug
found via a live PoC that hung the simulator in an infinite fetch-fault loop; fixed by claiming the
previously-unused `handle_trap_extension` hook (41/41). `MILESTONE_21_TIMER_INTERRUPT_VERIFICATION_
RESULTS.md` then confirmed the fix also covers real timer interrupts, not just synchronous traps
(60/60, no new bug -- closes a previously-flagged but unverified gap). `MILESTONE_21_PCC_AUTO_
RESTORE_RESULTS.md` added automatic PCC restore-on-`mret`/`sret` (`veda_pcc_restore_on_xret()`,
self-consuming, gated on `!= VEDA_PCC_UNBOUNDED`) -- found and fixed 3 real regressions where
existing recovery tests wrote only the *live* compartment-state CSRs, never the *shadow* ones the
new auto-restore now consumes (61/61). `MILESTONE_27_MTVEC_CSR_GATE_RESULTS.md` closed a real
privilege-escalation vulnerability -- Milestone 20's ungated `mtvec` write, composed with
Milestone 21's universal PCC-reset-on-any-trap, let a bounded compartment rewrite `mtvec` with zero
trap and get attacker-chosen code running with fully unbounded PCC after any subsequent trap;
proven via live PoC (`s7 = 0xE5CA` ESCAPED marker) before the fix, closed by gating `mtvec` writes
on `veda_pcc_length == VEDA_PCC_UNBOUNDED` (62/62).

**RTL now mirrors both of the above, closing a real gap this document itself flagged as
outstanding in Part 2 below (2.4-class):** `rtl/MILESTONE_21_27_RESTORE_MTVEC_GATE_RTL_RESULTS.md`
ports both the auto-restore and the `mtvec` gate into `veda_core.tlv`, and found **two genuinely
new bugs that exist only in RTL and have no Sail counterpart** -- a nested-trap `mepcc` capture that
was unconditional (harmless until auto-restore started consuming it) and a real cross-context
ambiguity where a single global `mepcc` pair cannot distinguish an outer handler's restoring `mret`
from an inner/nested handler's own `mret`, requiring explicit software shepherding to resolve. Full
RTL smoke regression **51/51**, ACT4 **51/51**, all mutation tests correctly flip and revert
(including one demonstrating a real, live control-flow hijack via a `bogus_handler` when the mtvec
gate is pulled).

**Toolchain, Milestones 18-20 -- the SoftBound-style shadow-propagation pass was audited for real
gaps and mostly hardened, with two confirmed-real gaps deliberately left open:**
`TOOLCHAIN_MILESTONE_18_CONTAINER_OF_RESULTS.md` empirically proved the existing pass already
handles Linux's `container_of()` pattern correctly (backward pointer reconstruction via negative
GEP), zero code changes needed. `TOOLCHAIN_MILESTONE_19_SCOPE_LIMIT_AUDIT_RESULTS.md` then ran a
4-agent adversarial audit and found four real, till-then-undocumented gaps: `uintptr_t` round-trips
silently losing shadow tracking with **no trap and no signal**; a tracked pointer returned from a
function call losing its shadow at the caller (no return-value propagation existed at all); global
arrays-of-structs left completely unrewritten by a single-level-only GEP resolver; and a real,
deterministic LLVM compiler crash (`SIGABRT`) on any function-pointer/indirect-call use.
`TOOLCHAIN_MILESTONE_20_*` then closed all four across four sub-passes -- silent-bind-failure fixed
by switching the compiler-generated path to a real trapping `veda.bind` (previously non-trapping);
return-value shadow propagation added (found and fixed a second, independent off-by-one bug in
existing parameter-shadow-seeding while implementing this); the indirect-call crash fixed by
excluding such functions from rewriting entirely (found and fixed a real follow-on regression this
introduced -- an old fallback path was wrongly redirecting even ordinary untracked pointers);
global multi-level GEP made recursive; `uintptr_t` round-tripping fixed via explicit
`PtrToIntInst`/`IntToPtrInst` dispatch. A sixth pass, `TOOLCHAIN_MILESTONE_20_KERNEL_GAPS_RESULTS.md`,
fixed union type-punning (a real gap, found and fixed) and **corrected an earlier, overstated claim
about RCU** (the real kernel `rcu_assign_pointer`/`rcu_dereference` macros are NOT opaque and were
already handled correctly) -- but confirmed **two real, still-open gaps, deliberately not fixed**:
struct assignment/`memcpy` silently drops shadow tracking on any pointer field it copies (the
subsequent dereference hits a raw, unrelated fetch fault instead of a Veda-Core capability trap --
or, on a real flat address space with no MMU, potentially **no trap at all** if that raw address
happens to be otherwise valid memory), and the Linux-style per-CPU addressing idiom
(`RELOC_HIDE`-equivalent inline-asm pointer round-trip) hits the identical code path as the
indirect-call crash and is unsupported by construction. Current toolchain regression floor across
this whole track: `run_veda_demo_tests.sh` 8/8, `run_veda_shadow_prop_tests.sh` 8/8, all
compartment/alloca/global/scheduler suites PASS, `runtime/run_veda_rt_tests.sh` 2/2, Sail
self-check **63/63**.

**Minimal OS Kernel gained a real syscall layer.** `MINIMAL_OS_KERNEL_DESIGN.md`'s switcher-pattern
foundation (TSC register, `OSpecialRW` selector) reached 44/44, and on top of it,
`SYSCALL0_MILESTONE_RESULTS.md` built a genuine KERNEL ecall dispatcher -- `sys_write`(64)/
`sys_exit`(93) dispatched on `a7`, with the caller-supplied Object_ID validated entirely in
**hardware** via a trapping `veda.bind` (zero software-side check anywhere in the syscall path), a
real compiled-C `hello_world.c` running through the unmodified toolchain, and a forged-Object_ID
negative test proving the hardware rejection. Sail 65/65. This was then mirrored into RTL end to
end (Task #297/#299's own RTL parity, four parts, all mutation-tested): **final RTL smoke regression
53/53, ACT4 51/51, zero regressions.** Three real bugs were found and fixed along the way (a
too-narrow compartment `Length` cutting off its own post-ecall check code; a full-GPR-restore sweep
that clobbered the syscall's own return value in `a0`; and a structural compiler-pass limit --
`VedaShadowPropagation.cpp` only rewrites function *definitions*, never declarations, ruling out a
pointer-parameter hand-written syscall shim -- worked around with a scalar out-parameter instead).

**Net effect on Part 2's gap list below:** the two CSR-escape vulnerabilities (compartment-state
self-escape, `mtvec` rewrite) are now **CLOSED on both Sail and RTL** -- see the updated 2.4 note.
Two new, real, confirmed-open gaps are added as 2.11 and 2.12. Part 4's Tier list is re-evaluated
below in light of all of this, not left standing unexamined.

## Why this document exists

Requested explicitly, in these terms: *"complete and rigorous analysis,
research, analytical thinking and logical approach... how much we can
extend it... read complete content... of any research paper or web
content, don't just piece of content or relevant section."* This document
is the output of that pass: (1) a complete re-read of every planning/
results document this project has produced (2,000+ lines, all read in
full, not grepped for fragments), cross-checked against the actual current
RTL/Sail source rather than assumed from memory; (2) fresh external
research, reading complete primary sources -- the ratified RVA23 profile
spec, the current live CHERI-RISC-V draft spec, a real CHERI-RISC-V
standardization-status talk, and a full peer-reviewed paper on Arm CCA --
not search-result summaries alone. Findings that overturn or sharpen
earlier assumptions are stated as such, not quietly folded in.

---

## Part 1 -- Where we actually are (verified against source, not memory)

### Sail formal model -- Milestones 1 through 22, plus lettered V-A/V-B/V-C, A, B, C, and C-GPR-context-save, all done

Everything the previous version of this section described is still there (the capability struct --
`Object_ID`(23)/`Base`(32)/`Length`(16)/`Offset`(16)/`Perms`(16)/`otype`(16)/`Reserved`(8), 128 bits
plus out-of-band Tag -- the 16-entry CRF, the flat system-wide ODT, all three Object-Bind modes,
`OCL.{D,C}`/`OCS.{D,C}`, `NMC_ADD.{W,D}`, all 9 Veda-Atomic ops, `OCA`, the query family,
`CSetBounds`/`CSetBoundsExact`, `CSeal`/`CUnseal`) -- but the numbered-milestone track has moved
nine milestones further and added a real, second dimension: purecap enforcement, a compartment-jump
primitive, and a minimal cooperative OS kernel, none of which existed when this section was last
written.

`MILESTONE_19_RESULTS.md` added a real `veda_mode` CSR (`0x7C5`) and a genuine purecap enforcement
hook (`ext_data_get_addr`/`ext_handle_data_check_error` in `core/addr_checks.sail`), with a new
`VEDA_CAUSE_PURECAP_VIOLATION` cause code -- ordinary `LD`/`SD` can now be forced to hard-trap when
purecap mode is active, not just Veda-Core's own capability-width instructions. `MILESTONE_20_RESULTS.md`
then gated writes to the compartment-state CSR range (`0x7C0`-`0x7C3`, `0x7C5`) on live compartment
state, closing a self-escape route a compartment could otherwise have used to write its own way out.
`MILESTONE_21_RESULTS.md` made PCC reset universal on any trap (not just the traps that were already
compartment-aware), via `handle_trap_extension`. `MILESTONE_22_RESULTS.md` (2026-08-01) is a
directed audit against CHERI's own real, verified-from-source pillars (spatial safety,
Veda-Core's own temporal-safety claim, compartmentalization) -- no gap found in the first two, and
one real, new compartment-boundary scope finding in the third: `OCJALR` (`MILESTONE_17_RESULTS.md`'s
own sentry-style unseal-and-jump, already built to close a separate, earlier stack-protection gap
documented in `STACK_FRAME_CALL_RETURN_ANALYSIS.md`) does not itself reset PCC bounds, so it cannot
cross a compartment boundary on its own -- confirmed with a real PoC under `sail_riscv_sim`, closed
by documentation and a permanent test, not by changing `OCJALR`'s own deliberately narrow scope.

On top of the numbered track, `MINIMAL_OS_KERNEL_DESIGN.md`'s three lettered milestones are also
done in Sail: Milestone A (`rtl/MILESTONE_A_RESULTS.md`'s Sail counterpart) built the switcher
pattern; Milestone B added a reserved-otype sentry mechanism; Milestone C
(`MILESTONE_C_RESULTS.md`) built a real cooperative scheduler, `vc_scheduler_cooperative_yield.S`,
that actually switches between two threads via trap-and-resume. A follow-on,
`MILESTONE_C_GPR_CONTEXT_SAVE_RESULTS.md`, then widened that scheduler's context save from 3
dwords to the full x1-x31 GPR file across a yield. Separately, SSC (Stack-Spill Capability, its own
design doc plus a Sail/RTL implementation) extended `OSpecialRW` with a third SCR selector and gave
`OCInvoke` a save/swap side effect, so callee-saved spills inside a compartment route through a
per-compartment capability rather than the caller's own stack -- verified for cross-thread isolation
under the scheduler.

Self-check test count has grown accordingly: `MILESTONE_C_GPR_CONTEXT_SAVE_RESULTS.md` reports the
full `sail_tests/run_veda_selfcheck_tests.sh` suite at **59/59 passed** (58 pre-existing plus the one
modified test for that change), zero regressions elsewhere in the corpus -- up from the 14/14 this
section originally cited for the V-A/V-B/V-C baseline alone.

### RTL -- Milestones 1 through 25, plus lettered A, B, C, all done

The RTL layer has closed most of the divergence from Sail that this section previously called out.
It is no longer true that this RTL "has no CSRs, no privilege modes" -- `rtl/veda_core.tlv` now
decodes a real, if intentionally narrow, Zicsr-lite CSR file at the standard RISC-V M-mode addresses
(`mtvec` `0x305`, `mscratch` `0x340`, `mepc` `0x341`, `mcause` `0x342`, `mtval` `0x343`, plus
Veda-Core's own `0x7C0`-`0x7C3`/`0x7C5` compartment-state range), real trap-taken PC redirect
(`MILESTONE_9_RESULTS.md`), and a real purecap enforcement path with its own
`VEDA_CAUSE_PURECAP_VIOLATION` cause and CSR-write gating mirroring Sail Milestones 19-21. `mscratch`
is the newest addition (RTL Milestone 25, this file's own header comment previously scoped CSR
recognition to exactly 4 addresses; it now names 5), added specifically to support the RTL mirror of
the full-GPR-context-save scheduler.

`rtl/MILESTONE_25_RESULTS.md` is the current latest numbered milestone: a byte-for-byte structural
port of Sail's `mscratch`-based trap-and-resume scheduler into `rtl/sim/veda_smoke_m23_scheduler.S`
and `veda_core.tlv`, widening the save/restore path from 3 dwords to the full 31-register GPR file.
Verification: a standalone `mscratch` round-trip smoke test passed first try; the full scheduler port
passed, including a mutation test (deliberately removing one save instruction, confirming the test
fails cleanly, then reverting); the full RTL smoke-test regression, `rtl/run_veda_smoke_test.sh`,
reports **49/49 passed**; the ACT4 RV64I conformance suite, `rtl/run_act4_tests.sh`, reports
**51/51 passed** -- both zero regressions. One real bug was found and fixed during this milestone's
own implementation (missing `gpr_ok` marker initialization in both thread-entry points, masking a
correct bounds check behind an uninitialized-register false negative), caught by the same
disciplined trace-and-bisect method this project has used since its earliest RTL milestones.

Below the numbered track, RTL's own lettered milestones mirror Sail's: `rtl/MILESTONE_A_RESULTS.md`
and `rtl/MILESTONE_B_RESULTS.md` (both dated 2026-08-05) port the switcher pattern and sentry
mechanism; `rtl/MILESTONE_C_RESULTS.md` (2026-08-06) ports the cooperative scheduler itself. RTL
Milestone 23 (`rtl/MILESTONE_23_RESULTS.md`) added real `ecall` decode and trap wiring -- a
prerequisite the scheduler mirror needed -- verified at 40/40 smoke tests (38 pre-existing plus 2
new) and 51/51 ACT4, with EBREAK, general illegal-instruction trapping, and misaligned-access
detection explicitly still out of scope. RTL Milestone 24 (`rtl/MILESTONE_24_RESULTS.md`, 2026-08-08)
is the other major addition since this section was last written: a real TCM/DRAM latency-tiering
fast path, closing the linearly-scaling DRAM-latency cost a repeated-rebind access pattern was shown
to incur (`DRAM_TCM_LATENCY_STUDY.md`, `CAPABILITY_REGISTER_PRESSURE_STUDY.md`). It adds a real
DRAM-latency stall FSM, ODT tier routing (`$veda_odt_tcm_hit`), and a genuinely separate
`tcm_scratch[]` array for capability-spill traffic, built and verified in five stages, each
independently confirmed before layering the next; it ships with `DRAM_EXTRA_CYCLES` (`E`) defaulting
to 0 to avoid breaking existing tests' cycle budgets, with the nonzero-`E` behavior of the stall FSM
itself verified separately via mutation-tested temporary builds. The milestone's own "What this
milestone does not show" section is explicit about real remaining limits: no physically-separate
SRAM bank was built (TCM here is a latency classification plus a separate array, not a distinct
memory technology); TCM-scratch access is currently `OCL.C`/`OCS.C`-only, with plain `OCL.D`/`OCS.D`,
`NMC_ADD`, and Veda-Atomic against a TCM-backed object explicitly unsafe and unenforced by hardware;
and Object_ID placement in the TCM-eligible range is a manual software convention, not yet enforced
or automated by any compiler backend.

Two things this section previously called absent remain genuinely absent, confirmed by direct source
inspection rather than assumption. There is still no MMU or address translation of any kind --
`veda_core.tlv` line 497's own comment states plainly that "no address translation" is needed in the
datapath, and no page-table or virtual-memory logic exists anywhere in the file. And real multi-hart
RTL is still not built: `rtl/MILESTONE_24_RESULTS.md` states outright that "Multi-hart TCM
contention is out of scope by construction, not solved" -- this core is single-hart with `MHARTID=0`
fixed, and the real, measured cross-hart TCM-contention covert channel from the literature
(Wrisley et al., NordSec 2025, up to 68 kbps) is recorded as a forward-declared constraint for a
future multi-hart core, not something this milestone addresses. The base RVA23 core underneath all
of this (`rtl/rv64i_core.tlv`) remains bare RV64I, single-cycle, with the same 51/51 ACT4 conformance
this section originally cited.

### Toolchain -- 17 numbered milestones plus the Minimal OS Kernel's software layer, all done

This subsection did not exist the last time Part 1 was written, because this track did not exist yet.
It now spans `TOOLCHAIN_MILESTONE_1_RESULTS.md` through `TOOLCHAIN_MILESTONE_15_RESULTS.md` (15
results-style documents; `16_EXTERN_GLOBALS_DECISION.md` and
`17_UNATTRIBUTED_ACCESS_POLICY.md` are decision docs, not full results docs, confirmed by their own
filenames and content), and it is real, working software, not a design exercise.

An LLVM backend is built and self-hosting for this ISA: Toolchain Milestones 1-2 eliminated
hand-written `.insn` hex encodings from the test corpus and stood up the LLVM dev environment;
Milestones 5a and 5b/6 (`TOOLCHAIN_MILESTONE_5a_RESULTS.md`, `TOOLCHAIN_MILESTONE_5b_M6_RESULTS.md`)
added a real LLVM assembler for the pure-GPR ODT instructions and then a full CRF register class
covering all 33 CRF-touching instructions. A debugger exists: Milestone 3
(`TOOLCHAIN_MILESTONE_3_RESULTS.md`) is a minimal GDB stub for the standard GPRs, and Milestone 4
(`TOOLCHAIN_MILESTONE_4_RESULTS.md`) extends it with real capability-register visibility. A software
runtime exists: Milestone 7 (`TOOLCHAIN_MILESTONE_7_RESULTS.md`) is `veda_rt`, a real
malloc/free-equivalent C library (`veda_rt_init`, `veda_malloc`, `veda_free`, plus
`veda_ocl_d`/`veda_ocs_d` wrappers), verified against 48 full malloc-write-read-free cycles across
its object slots. A compiler-enforced memory-safety pass exists: Milestones 8-9
(`TOOLCHAIN_MILESTONE_8_RESULTS.md`, `TOOLCHAIN_MILESTONE_9_RESULTS.md`) are a SoftBound-style LLVM
IR pass, phase 1 (shadow Object_ID propagation) and phase 2 (dereference codegen), with a real
end-to-end compiled-C demo. A compartmentalization attribute exists: Milestone 11
(`TOOLCHAIN_MILESTONE_11_RESULTS.md`) adds a `veda_compartment` Clang attribute that reserves CRF
`c15` and routes callee-saved-register spills through SSC automatically, with a follow-on nested-call
test proving it composes when one compartment calls another. Hardware-checked stack-locals (Milestone
12, `TOOLCHAIN_MILESTONE_12_RESULTS.md`) and hardware-checked globals/statics (Milestone 13, refined
by Milestones 14-15 for CRF-pressure and compiler-pass-sizing reasons) extend the same SoftBound-style
protection to C variables the original phase-1/phase-2 work didn't cover. And a C-callable
cooperative scheduler API exists: Milestone 10 (`TOOLCHAIN_MILESTONE_10_RESULTS.md`) wraps the
Sail/RTL-proven scheduler mechanism in `veda_sched.h`/`veda_sched_asm.S`/`veda_sched.c`, demonstrated
with a real two-thread demo built and run through the actual toolchain pipeline, not a hand-assembled
test.

Taken together with the Minimal OS Kernel's Sail/RTL milestones above, this is a full vertical slice
-- compiler, debugger, runtime, compiler-enforced safety pass, compartmentalization attribute, and a
schedulable concurrency primitive -- none of which existed when this document's Part 4 originally
told the project not to start "software/compiler/OS ecosystem" work as "a distant, named, unstarted
cost." That recommendation has been overtaken by what was actually built and verified since; it is
corrected here, not left standing alongside the evidence that contradicts it.

### Everything above is genuinely real -- verified via actual compilation, actual simulation, actual trace output, and in the toolchain's case actual LLVM/GDB builds exercised through the real pipeline -- not asserted from source review alone. The Sail/RTL architectural gap this section used to describe (no CSRs, no privilege, no trap infrastructure in RTL) is now largely closed; what remains open is narrower and more structural: no MMU in either layer, and no genuine multi-hart RTL, both confirmed absent by direct source inspection above, not inferred from silence.

---

## Part 2 -- Real, already-flagged gaps, re-audited and re-prioritized

Cross-checked against `MILESTONE_PLAN.md`, every `rtl/MILESTONE_*_RESULTS.md` (1 through 25, plus
lettered A/B/C), `MILESTONE_V-{A,B,C}_RESULTS.md`, `MILESTONE_B_RESULTS.md`/`MILESTONE_C_RESULTS.md`/
`MILESTONE_C_GPR_CONTEXT_SAVE_RESULTS.md`, the full `TOOLCHAIN_MILESTONE_1` through `_17` track, and
`FORMAL_VERIFICATION_PLAN.md` -- every item from the original nine re-verified directly against the
real files on disk as of 2026-08-09, not restated from memory of the last pass.

### 2.1 -- CLOSED: capability-width memory access (`OCL.C`/`OCS.C`)

Done, both Sail and RTL -- see `rtl/MILESTONE_7_RESULTS.md`. See the 2026-07-25 status update above
for the full story.

### 2.2 -- CLOSED: Sail-side test-coverage parity gap

Done -- see `MILESTONE_V-B_RESULTS.md`'s 2026-07-25 addendum, 16/16 self-check tests passing. See
the 2026-07-25 status update above for the full story.

### 2.3 -- CLOSED: RTL/Sail parity, `Rebind`/`Bind-NoTrap`

Done -- see `rtl/MILESTONE_8_RESULTS.md`. See the 2026-07-25 status update above for the full story.

### 2.4 -- CLOSED: real trap infrastructure in RTL

Done -- see `rtl/MILESTONE_9_RESULTS.md` (Zicsr-lite CSR file, real `CSRRW`/`CSRRS`/`MRET`, a real
PC redirect wired to every Sail "use"-family violation). See the 2026-07-25 status update above for
the full story.

### 2.5 -- CLOSED: capability-authority-gated `ODT-Populate`/`ODT-Destroy`

Done -- see `rtl/MILESTONE_11_RESULTS.md` (`OSpecialRW` + the ODA, term-for-term adapted from real
CHERI's `CSpecialRW`/SCR model). See the 2026-07-25 status update above for the full story.

### 2.6 -- CLOSED: `CInvoke`-equivalent domain transition

Done -- see `rtl/MILESTONE_10_RESULTS.md` (`OCInvoke`, both Sail and RTL). The narrower "PCC" follow
-on this item's own deferral named is also now closed in both layers, see `MILESTONE_14_RESULTS.md`
and `rtl/MILESTONE_14_RESULTS.md`. See the 2026-07-25 status update above for the full story.

### 2.7 -- Still open: multi-hart RTL / concurrent-hart shared-ODT arbitration

Re-verified directly against the newest relevant milestone, `rtl/MILESTONE_24_RESULTS.md` (2026-08,
the TCM-latency-tier work), which states this in its own words, unprompted, in a "What this milestone
does not show" section: *"Multi-hart TCM contention is out of scope by construction, not solved. This
core is single-hart (`MHARTID=0` fixed); the real, measured cross-hart TCM-contention covert channel
(Wrisley et al., NordSec 2025, up to 68 kbps) is a forward-declared constraint for any future
multi-hart Veda-Core, requiring per-hart-private banks or a real static time-partitioned arbiter
(Wang/Ferraiuolo/Suh, HPCA 2014) before this security property could be trusted again in that
setting."* Fourteen more RTL milestones (11 through 24) have shipped since this gap was first named,
including a real `owner_hart` byte and owner-hart enforcement (`rtl/MILESTONE_12_RESULTS.md`) --
but every one of them, including Milestone 12's own owner-hart proof, was verified via direct
ODT-state injection standing in for a second hart, not genuine concurrent execution, because neither
this project's single-process Sail simulator nor its single-core RTL can produce one. `MHARTID` is
still a fixed RTL `localparam`, not a real per-instance parameter. This remains the single largest
undertaking on this list, unchanged in scope since the original assessment, now with one additional
concrete, cited security consequence (the TCM covert-channel bound) attached to it.

### 2.8 -- Still open: `Length`/`Offset` 16-bit cap

Re-verified directly against `VEDA_CORE_SPEC.md`'s own capability-field table: `Length` and `Offset`
are still both 16 bits, the field-table note is unchanged, still stating the same honest trade-off --
"16 bits caps a single object's size at 65,536... growing past this later would need either a wider
capability register... or a CHERI-style compressed encoding." No compressed-bounds design or
implementation work exists anywhere in the milestone corpus checked for this pass (Sail Milestones
15-22, RTL Milestones 15-25, the full toolchain track). Still a stated, honest, load-bearing limit,
not free to lift.

### 2.9 -- Still open, but narrower than before: formal-verification maturity gap

Re-verified against `SAIL_COQ_EXPORT_RESULTS.md` (commit `6b85cf4`, 2026-07-27), read in full rather
than assumed closed by its existence. The real work done: Sail's own official Coq/Rocq export
backend was run against the full RVA23 profile Sail model including Veda-Core's extension, producing
two real Coq source files (`rv64d_types.v`, 16,825 lines; `rv64d.v`, 101,936 lines), with concrete,
line-level evidence that Veda-Core's own fixes (the Milestone 15/16 ODT-aliasing and generation
-retirement logic) translate faithfully -- not just "the build didn't error." The document's own
"Honest, real scope limits" section states plainly why this does not close the gap: `coqc`, the real
Coq compiler needed to type-check the `.v` files and machine-check any proof, is not installed; no
actual proof obligations or lemmas were written or checked; the safety property this architecture's
own claims rest on ("a capability with `Tag=false` can never result in a successful write") remains
unproven. The document's own conclusion is the accurate one to carry forward: "the model is proven to
translate correctly into a real theorem-prover's own input language; no actual theorem has been
stated or checked yet" -- a real, meaningfully smaller gap than the original `SCALING_BARRIERS_
RESEARCH.md` §8 finding (51.3% Isabelle / 45.9% Rocq/Coq / 2.6% executable Sail for the mature
`sail-cheri-riscv` effort), but still a real and substantial one. No `coqc` install, no lemma, no
theorem exists in this project as of 2026-08-09.

### 2.10 -- Re-examined, found already closed: protected-stack / return-address calling convention

`ROP_JOP_MITIGATION_FIT_ANALYSIS.md` originally identified exactly the gap this item was expected to
be: Veda-Core had no `csp`-equivalent convention, so a corrupted return address on the ordinary RISC-V
stack would be read and used by a plain `JALR`, completely outside the capability system's field of
view. That document's own later "Update" section, and the fuller `STACK_FRAME_CALL_RETURN_ANALYSIS.md`
it points to, show this was subsequently closed, not left open. A "Frame-object per call" design was
considered and rejected on three independent, quantified grounds (the Intel iAPX 432 precedent's
real 300us/`CALL` cost, this project's own measured per-call-vs-amortized instruction-count math, and
RTL Milestone 16's 255-reuse ODT-generation-retirement ceiling). In its place, a real, working
`csp`-equivalent convention was built entirely from already-existing instructions (`OCA`+`CSeal` at
the call site, `OCL.C`+`CGetTag`+`CUnseal`+`CGetAddr` on return) and tested against three real
programs on the actual, unmodified, committed `veda_core.tlv`: the traditional convention was
confirmed cleanly hijackable (`x30=0xbad1`) in 10 cycles, the protected convention caught the
identical corruption (`x30=0xca11`) via a real `CGetTag` check, and a third variant with that check
deliberately omitted (`prot_gap`) proved the protection was, at that point, a software discipline
(the check could be silently forgotten), not a hardware guarantee. That specific residual gap was
then closed structurally, not by discipline, by `rtl/MILESTONE_17_RESULTS.md`: `OCJALR`, a lighter,
hard-trapping sibling of `OCInvoke` adapted from real CHERI's `CJALR` (CHERI ISA spec p.213), merges
unseal-verification and jump into one atomic instruction, re-running `prot_gap`'s own exact corruption
scenario with the vulnerable tail replaced by a single `ocjalr` and landing in a real, controlled
hard-trap instead of an undefined jump -- 28/28 Sail self-check tests, 31 real RTL smoke tests (zero
regressions), 51/51 ACT4, zero regressions in either layer. A real, narrower scope boundary was found
afterward by Milestone 22's own CHERI-pillar audit (`OCJALR` does not reset PCC bounds, so it cannot
itself cross a live compartment boundary -- a documented, tested design boundary, not an escape: a
compartment exit must use a second `OCInvoke`), and the measured per-call cost of the protected
convention itself (`STACK_FRAME_CALL_RETURN_ANALYSIS.md`: `+6 cycles/call` sustained versus the
traditional convention, not amortized) is real and worth carrying forward as a stated cost, not a
gap. Net: this is not an open item to add to this list. If anything remains here, it is adoption --
this convention exists as a proven, tested pattern, not yet a mandatory ABI enforced project-wide --
a policy/toolchain question closer to `TOOLCHAIN_MILESTONE_17_UNATTRIBUTED_ACCESS_POLICY.md`'s own
open diagnostic-tooling gap than a new architectural hole.

No other genuinely new, concrete, still-open gap was found while checking the most recent milestone
and domain-fit documents (`rtl/MILESTONE_24_RESULTS.md`, `rtl/MILESTONE_25_RESULTS.md`,
`MILESTONE_C_GPR_CONTEXT_SAVE_RESULTS.md`, `TOOLCHAIN_MILESTONE_15_RESULTS.md` through `_17`) beyond
what 2.7-2.9 already cover. The one minor, real item surfaced in passing --
`TOOLCHAIN_MILESTONE_17_UNATTRIBUTED_ACCESS_POLICY.md`'s own named future work, a compile-time
diagnostic for an unattributed function reaching a global from inside a compartment (today a runtime
hard-trap, not a build-time error) -- is a usability improvement on an already-safe behavior, not a
correctness or security gap, and is left where that document already places it rather than
force-numbered here.

### 2.11 -- NEW since 2026-08-09, now CLOSED on both layers: compartment-state CSR self-escape + `mtvec` compartment-escape

Two real vulnerabilities, neither present in the original nine-item list because both were found
*during* Milestones 20/27 themselves, not before. (a) Code inside a live compartment could rewrite
its own compartment-state CSRs (`veda_pcc_base`/`_length`, `veda_mepcc_base`/`_length`, `veda_mode`)
with an ordinary `CSRRW`/`CSRRS`, undoing its own bounding with zero trap -- closed in Sail
(`MILESTONE_20_RESULTS.md`, 40/40) by requiring `veda_pcc_length == VEDA_PCC_UNBOUNDED` before any
write to those five CSRs succeeds. (b) A bounded compartment could rewrite `mtvec` itself (ungated),
then trigger any ordinary trap and get attacker-chosen code running with fully unbounded PCC --
closed in Sail (`MILESTONE_27_MTVEC_CSR_GATE_RESULTS.md`, 62/62) by the same style of gate. **Both
are now also closed in RTL** (`rtl/MILESTONE_21_27_RESTORE_MTVEC_GATE_RTL_RESULTS.md`, 2026-08-11,
51/51 smoke + 51/51 ACT4) -- this document's own 2.4 above already flagged real trap infrastructure
as the closed item; these two CSR-write gates are the natural, now-also-closed extension of that
same infrastructure. Nothing open remains here.

### 2.12 -- NEW since 2026-08-09, genuinely OPEN: `memcpy`/struct-assignment silently drops shadow tracking

Found by `TOOLCHAIN_MILESTONE_20_KERNEL_GAPS_RESULTS.md`'s own adversarial audit, confirmed and
deliberately NOT fixed (a probe file, `veda_demo_struct_copy.c`, exists specifically to demonstrate
the gap and is NOT registered in the passing regression suite). `dst = *src` for a struct containing
a pointer field compiles, even at `-O0`, to an opaque `llvm.memcpy` intrinsic the shadow-propagation
pass does not look inside. The pointer field's raw bits copy correctly, but its shadow does not, so
a subsequent dereference through the copied field is entirely unrewritten -- it hits an ordinary
RISC-V fetch/access fault if the raw address happens to be unmapped, but **on this project's own
flat, MMU-less address space, an unrelated valid address would produce no trap at all**, a genuine,
silent out-of-object access with zero capability enforcement. This is a **very common C idiom**
(`struct` assignment, `memcpy` of any struct with a pointer field) -- more common in ordinary code
than the multi-level-GEP or `uintptr_t` patterns Milestone 20 already closed. The document's own
words on what a real fix needs: "the pass would need to trace back to the GEP/alloca/malloc call
that established `dst`'s and `src`'s real struct TYPE ... a genuinely new, type-aware analysis pass
component" -- this is a real design undertaking, not a bounded patch, and has not had its own design
pass yet.

### 2.13 -- NEW since 2026-08-09, genuinely OPEN but lower priority for THIS (embedded) line: per-CPU addressing pattern

Also found by the same audit. The Linux-kernel `RELOC_HIDE`/`this_cpu_ptr`-style idiom (a pointer
round-tripped through an opaque, empty inline-asm statement specifically to defeat compiler hoisting
across context switches) hits the identical unrewritten code path as the already-fixed indirect-call
crash (`CallInst` to an `InlineAsm` value, `getCalledFunction()` returns null). Two fix directions
are named, neither attempted: fragile pattern-matching on the specific idiom, or a Veda-Core-native
per-CPU primitive (the document's own stated preference, matching this project's hardware-first
philosophy). **Scoped explicitly as lower priority for this document specifically**: per-CPU
addressing is a multi-hart/OS-hosting concern, and this line (`rva23-core`) is confirmed genuinely
single-hart in both Sail and RTL (§2.7) -- the concern is real but its natural home is the
Linux-line's own roadmap, not this one, unless multi-hart work here changes that calculus.

---

## Part 3 -- Fresh external research: reframing "how far can we extend, and toward what"

### 3.1 -- RVA23 is ratified, and its real requirement list is enormous

Read in full from the official ratified spec
([docs.riscv.org/reference/rva23](https://docs.riscv.org/reference/rva23/v1.0/rva23-profiles.html)):
RVA23 was **ratified 2024-10-21**. Its mandatory list for just the
user-mode profile (`RVA23U64`) is ~35 extensions beyond bare RV64I: `M`,
`A`, `F`, `D`, `C`, `B`, `Zicsr`, `Zicntr`, `Zihpm`, `Ziccif`, `Ziccrse`,
`Ziccamoa`, `Zicclsm`, `Za64rs`, `Zihintpause`, `Zic64b`, `Zicbom`,
`Zicbop`, `Zicboz`, `Zfhmin`, `Zkt`, **`V` (the full Vector extension, now
mandatory, was optional in RVA22)**, `Zvfhmin`, `Zvbb`, `Zvkt`,
`Zihintntl`, `Zicond`, `Zimop`, `Zcmop`, `Zcb`, `Zfa`, `Zawrs`, `Supm`. The
supervisor-mode profile (`RVA23S64`) adds a **mandatory Hypervisor
extension** (`Sha`, itself a bundle of 7 sub-extensions), a mandatory
**Sv39 MMU**, mandatory supervisor timers (`Sstc`), counters, and pointer
masking.

**Direct, quantified answer to this project's own earlier question ("what
do we still need to be RISC-V compatible")**: the current core (bare
RV64I, zero privilege architecture, zero MMU, zero vector unit) implements
roughly 1 of ~40 required pieces of `RVA23U64` alone, and zero of
`RVA23S64`'s additional privileged/MMU/hypervisor requirements. This is not
a "few milestones away" gap -- it is a categorically different scale of
undertaking than anything built so far, and every one of those ~40 pieces
is **already fully specified, already implemented by multiple real
vendors** (SiFive, Ventana, and others already ship real RVA23-class
silicon). There is close to zero novel research value in re-implementing
them -- the entire value would be in the exercise of implementing them, not
in any new idea they'd embody.

### 3.2 -- CHERI-RISC-V itself -- Veda-Core's real, closest precedent -- is still in draft, a year past its own target

Two real, current primary sources, read in full:

- The **live spec repository** ([riscv.github.io/riscv-cheri](https://riscv.github.io/riscv-cheri/)),
  fetched today: version **v0.9.9-draft**, dated **2026-07-21** (two days
  before this document), status **"Stable"** -- RISC-V's own maturity model
  defines "Stable" as "assume anything could still change, but limited
  change should be expected," one stage before "Frozen" and two before
  "Ratified."
- A **real conference talk abstract** by Tariq Kurd (Codasip) and Ben
  Laurie (Google), *"Standardizing CHERI-RISC-V,"* RISC-V Summit Europe,
  May 2025, read in full (PDF): the CHERI Task Group was **officially
  formed October 2024**. Its own agreed ratification plan targeted
  **"late summer 2025."** Real industry backing is substantial and named:
  Google chairs the SIG/TG; Microsoft Research built CHERIoT (an embedded
  variant with a hardware garbage collector); Codasip ships an X730 core
  meeting the draft base standard; lowRISC ships the SONATA FPGA dev
  board; ICENI silicon based on open-source CHERIoT was planned for 2025.
  The talk's own words: *"This comes late for existing silicon projects,
  risking a defacto standard forming."*

**Cross-referencing these two sources directly**: the "late summer 2025"
target has now been missed by well over ten months -- the spec is still
"Stable"-draft, not ratified, as of this week. **This is the single most
important calibration point this research pass produced**: a RISC-V
Task-Group-chartered effort, backed by Google, Microsoft Research,
Cambridge, and multiple silicon vendors, with a concrete ratification plan
and real committed hardware, has still taken *at minimum* 21 months
(October 2024 → now) without reaching ratification. Veda-Core is a
single-contributor research project pursuing a *more* novel design (fully
address-less and object-table-based, versus CHERI's address-based
tagged-pointer model -- `SCALING_BARRIERS_RESEARCH.md` §7 already made this
exact comparison for the software-ecosystem question; it applies equally
here to the standardization-timeline question). This isn't a reason to
stop -- it's a real, evidence-based reason not to frame any near-term work
here as "on the path to being a standardized, shippable extension soon."
The honest framing is: this is research-stage work in a space where even
the best-resourced comparable effort is still years from that bar.

### 3.3 -- Confidential computing (Arm CCA / Intel TDX / AMD SEV-SNP) is a different problem, not a competitor

Read in full: Bertschi & Shinde (ETH Zürich), *"OpenCCA: An Open Framework
to Enable Arm CCA Research"* (2025, full paper via `arXiv:2506.05129`), plus
a real, current technical comparison search across TDX/SEV-SNP/CCA
sources. **Real, precise technical finding, not assumed**: Arm CCA's
actual mechanism is the Realm Management Extension (RME) -- Granule
Protection Checks/Tables at each core, splitting execution into four
*worlds* (Normal, Secure, Realm, Root), with a firmware Realm Management
Monitor managing whole *Confidential VMs*. Intel TDX and AMD SEV-SNP do the
analogous thing via a signed TDX module / per-VM memory encryption+
integrity, respectively. **All three operate at VM/tenant granularity**:
their job is protecting an entire guest VM from an untrusted hypervisor or
cloud host. The paper states plainly, as of its writing: *"no public Arm
CPU supports CCA yet."*

**This is categorically not what CHERI or Veda-Core do.** CHERI/Veda-Core
target *intra-process and inter-process* memory safety and fine-grained
compartmentalization -- protecting a program from its own bugs (buffer
overflows, use-after-free) and enabling sub-process sandboxing (Milestone
6's `CSeal`/`CUnseal` sealed-token model is exactly this), a completely
different granularity and threat model than "protect this whole VM from
the hypervisor." **Direct, evidence-based answer to this project's own
earlier question ("compete with whom, on which domain")**: Veda-Core's
real comparison set is CHERI-RISC-V (same problem: deterministic memory
safety/compartmentalization; different mechanism: address-based+compressed-
tag vs. address-less+object-table), not the confidential-computing
vendors, who are solving an adjacent, complementary problem at a different
layer. A real system could plausibly use both together (a CCA/TDX-style
confidential VM, internally memory-safe via a CHERI/Veda-Core-style
capability model) -- they are not substitutes.

---

## Part 4 -- Recommendation, reasoned, tiered

**Tier 1 -- near-term, high leverage, closes a real, cited gap with a bounded, well-understood scope. Recommended as the actual next milestone.**
1. `Length`/`Offset` compressed-bounds encoding -- §2.8. Of everything still open, this is the
   only item that is both small in design surface and already precisely specified: the honest
   16-bit cap documented in `VEDA_CORE_SPEC.md`'s own field table (`0`-`65,535` per object) has
   sat unchanged since the field was split from the old 32-bit `Limit`, and nothing in Sail
   Milestones 15-22, RTL Milestones 15-25, or the toolchain track has touched it. It does not
   require new hardware ports the way multi-hart does, and it does not require external tooling
   the way the Coq gap does -- it is a self-contained encoding change (CHERI-style compressed
   bounds, or a narrower fixed-point widening) against a field table this project already
   understands precisely, with regression suites (59/59 Sail self-check, 49/49 RTL smoke, 51/51
   ACT4) already in place to catch breakage immediately. Recommended as the actual next milestone
   on leverage-per-effort grounds: it removes a stated, load-bearing limit without waiting on any
   other open item.

**Tier 2 -- medium-term, substantial, dual-purpose, but each blocked on real external dependencies this project does not control alone.**
2. Formal-verification maturity -- §2.9. `SAIL_COQ_EXPORT_RESULTS.md` (commit `6b85cf4`,
   2026-07-27) already did the real, hard infrastructure step -- Sail's own official Coq/Rocq
   export backend runs cleanly against the full RVA23 profile plus Veda-Core's extension,
   producing `rv64d_types.v` (16,825 lines) and `rv64d.v` (101,936 lines), with concrete,
   line-level evidence that Veda-Core's own Milestone 15/16 ODT-aliasing and generation-retirement
   fixes translate faithfully. What remains is not a research question anymore, it is an
   installation-and-labor question: `coqc` is not installed in this environment, and no lemma or
   theorem has been written or checked, including the one this architecture's entire tagged-memory
   claim rests on ("a capability with `Tag=false` can never result in a successful write"). This
   is a smaller gap than it was when `SCALING_BARRIERS_RESEARCH.md` §8 measured the mature
   `sail-cheri-riscv` effort's own proof corpus at 51.3% Isabelle / 45.9% Rocq/Coq / 2.6%
   executable Sail, but "smaller" does not mean "near-term": it still needs dedicated
   theorem-proving time this project has not yet spent, on top of a toolchain install this
   project has not yet done. Sequenced behind Tier 1 because a compressed-bounds change would
   itself need re-verification against whatever Coq obligations eventually get written, so
   doing the encoding change first avoids re-deriving proof obligations twice.
3. Real multi-hart RTL / concurrent-hart shared-ODT arbitration -- §2.7. Fourteen RTL milestones
   (11 through 24) have shipped since this gap was first named, including a real `owner_hart`
   byte and owner-hart enforcement (`rtl/MILESTONE_12_RESULTS.md`), and every one of them was
   verified via direct ODT-state injection standing in for a second hart, not genuine concurrent
   execution -- `MHARTID` is still a fixed RTL `localparam`, not a per-instance parameter, and
   `rtl/MILESTONE_24_RESULTS.md` says outright, unprompted, that "Multi-hart TCM contention is out
   of scope by construction, not solved." This is placed in Tier 2, not Tier 1, for the same
   reason it was placed below the near-term items in the original assessment: it remains the
   single largest undertaking on this list, requiring either a second real hart instance or a
   credible multi-hart testbench harness before the exclusive-ownership policy this project
   already designed can be exercised for real rather than simulated by injection. What is new
   since the original assessment is a second, concrete, cited cost attached to leaving it open --
   the measured cross-hart TCM covert channel (Wrisley et al., NordSec 2025, up to 68 kbps) that
   `rtl/MILESTONE_24_RESULTS.md` names as a forward-declared constraint -- which raises this item's
   priority within Tier 2 without changing its Tier.
4. **NEW (2026-08-16): `memcpy`/struct-assignment type-aware shadow propagation -- §2.12.** A real,
   confirmed, currently-open security gap in a very common C idiom -- more common in ordinary code
   than any pattern Toolchain Milestone 20 already fixed. Placed in Tier 2, not Tier 1, on the same
   ground Tier 1 itself is defined by: this needs "a genuinely new, type-aware analysis pass
   component" (the document's own words) -- a design undertaking, not a bounded encoding change --
   exactly the property that keeps multi-hart RTL and the Coq gap out of Tier 1 too. Ranked here
   ahead of the pre-existing Tier 2 items on urgency grounds (it is the only Tier 2 item that is a
   live, exploitable-in-principle memory-safety hole today, not a scaling limit or a proof-maturity
   gap), without being promoted to Tier 1, because promotion would require this document to abandon
   its own stated Tier-1 criterion (bounded, well-understood scope) for a single case -- see "What I
   decided" below for how this tension was actually resolved, not just noted.

**Tier 3 -- real, but adoption/tooling work rather than new architecture; sequenced after Tier 1-2 close.**
4. Protected-stack (`csp`-equivalent) calling convention as a mandatory, project-wide ABI --
   re-examined against §2.10 and found already built and verified, not open. `ROP_JOP_MITIGATION_
   FIT_ANALYSIS.md`'s own "Update" section, cross-checked against `STACK_FRAME_CALL_RETURN_
   ANALYSIS.md` and `rtl/MILESTONE_17_RESULTS.md`, shows the mechanism exists end-to-end: a
   `csp`-equivalent convention built from `OCA`+`CSeal` at the call site and
   `OCL.C`+`CGetTag`+`CUnseal`+`CGetAddr` on return, tested against three real programs on the
   actual, unmodified `veda_core.tlv` (the unprotected convention was cleanly hijacked in 10
   cycles; the protected convention caught the identical corruption via a real `CGetTag` check;
   a deliberately-broken `prot_gap` variant proved the check itself could be silently omitted),
   with that residual gap then closed structurally by `OCJALR` (`rtl/MILESTONE_17_RESULTS.md`,
   28/28 Sail, 31 RTL smoke tests with zero regressions, 51/51 ACT4). What is left is not a
   design or verification task, it is adoption: this convention is a proven pattern available to
   any compartment, not yet a default the toolchain enforces for every function the way
   `TOOLCHAIN_MILESTONE_11_RESULTS.md`'s `veda_compartment` attribute enforces SSC-routed spills.
   That is a toolchain-integration item closer in kind to
   `TOOLCHAIN_MILESTONE_17_UNATTRIBUTED_ACCESS_POLICY.md`'s own named compile-time-diagnostic
   future work than a new architectural gap, and is listed here only to state explicitly that it
   is not being carried forward into Tier 1 or Tier 2 as an open item.

**Tier 4 -- explicitly not recommended as a near/medium-term priority, with reasoning stated plainly, including one correction to this document's own prior recommendation:**
- **CORRECTION to this document's own prior Tier 4 entry on "software/compiler/OS ecosystem"** --
  the original text called this "not a milestone to start casually... the single largest real
  -world adoption barrier of anything in this document, correctly left as a distant, named,
  unstarted cost." That claim is wrong as stated today and is corrected here, not quietly
  edited. Since it was written, this project built and verified exactly that category: an LLVM
  backend self-hosting for this ISA (Toolchain Milestones 1-2, 5a, 5b/6), a GDB debugger with
  capability-register visibility (Milestones 3-4), a working C runtime library (`veda_rt`,
  Milestone 7, 48 malloc-write-read-free cycles verified), a SoftBound-style compiler-enforced
  memory-safety IR pass (Milestones 8-9, 12, 13-15), a `veda_compartment` Clang attribute with
  automatic SSC-routed spilling (Milestone 11, plus a verified nested-call case), and a
  C-callable cooperative scheduler API (Milestone 10) sitting on top of a real Sail/RTL minimal
  OS kernel (Milestones A/B/C, 53/53 regression, RTL-mirrored). This is real, working software
  exercised through the actual toolchain pipeline, not a design exercise -- "unstarted" is
  false. What still genuinely holds from the original claim is narrower and should be stated
  precisely rather than thrown out along with the false part: ecosystem *scale* comparable to
  real CHERI's decade-plus, DARPA-and-UK-government-funded, dozen-committer install base and
  package corpus remains a real, distant gap. This project has one backend, one debugger stub,
  one runtime library, and no external contributors -- breadth and maturity of *use*, not
  existence of the pieces, is the part of the original warning that is still true.
- **Chasing broad RVA23 compliance** (§3.1) -- unchanged from the original assessment, re-checked
  against §3.1's own count and against the milestone corpus for this pass: still roughly forty
  already-fully-specified, already-multiply-implemented standard extensions with near-zero novel
  research value for this project's actual differentiated work. Nothing in Sail Milestones 15-22,
  RTL Milestones 15-25, or the toolchain track changes this calculus. **Recommendation unchanged:
  do not adopt "become RVA23-compliant" as a goal**; take standard extensions only where they
  directly serve Veda-Core's own needs, the same justification that made `Zicsr` (closed, RTL
  Milestone 9) and `ecall` (closed, RTL Milestone 23) legitimate targeted exceptions rather than
  steps toward the broader list.
- **Full Isabelle/Rocq-level formal proofs** -- folded into Tier 2 item 2 above rather than
  restated as a separate Tier 4 entry, since `SAIL_COQ_EXPORT_RESULTS.md` has moved this from "an
  aspiration with no concrete first step" to "a scoped, partially-complete task with a named
  installation blocker and named unwritten lemmas." It is real and it is not near-term, but it no
  longer belongs in the same bucket as "not started" -- Tier 2 is the accurate placement now,
  not Tier 4.
- **NEW (2026-08-16): per-CPU addressing pattern -- §2.13.** Real and structurally understood (same
  code path as the already-fixed indirect-call crash), but deliberately not promoted to Tier 2 here:
  its actual motivating use case is multi-hart/OS-hosted code, and this line is confirmed
  single-hart by construction (§2.7). It belongs on the Linux line's own roadmap, where multi-hart
  and OS-hosting are already the stated direction, not on this document's -- re-raise here only if
  real multi-hart work ever lands on `rva23-core` itself.

## What I decided, in one sentence, and why

Build the `Length`/`Offset` compressed-bounds encoding next (Tier 1, item 1): it is the only
still-open item that is both fully scoped by this project's own existing spec table and free of
external dependencies -- unlike multi-hart RTL, which needs a second real hart instance or
credible concurrency harness this project does not yet have, and unlike the formal-verification
gap, which needs a `coqc` install and theorem-proving labor this project has not yet committed to
-- and closing it removes a stated, honest, load-bearing limit (`VEDA_CORE_SPEC.md`'s own 65,536
-byte per-object cap) using the same regression discipline (Sail self-check, RTL smoke, ACT4) that
has caught every real bug in this project's 25 RTL and 22 Sail numbered milestones so far, rather
than opening a new, larger front before either of the two genuinely harder Tier 2 items is even
staffed.

**Re-examined, 2026-08-16, in light of everything since (the CSR/`mtvec`-escape closures, the
toolchain hardening pass, syscall-0, and -- most relevant to this specific decision -- the newly
found `memcpy`/struct-assignment shadow-tracking gap, §2.12).** The honest tension: this project's
own standing philosophy prioritizes hardware/security fixes over convenience or capacity work
whenever hardware can solve the problem, and §2.12 is a live, confirmed memory-safety hole in
ordinary C code, not a scaling ceiling -- a real argument for building it first instead. **Decision:
`Length`/`Offset` compressed bounds still ships first, and §2.12 is deliberately not promoted to
Tier 1 -- but not because it is less important. It is because it is not yet buildable at all.**
§2.12's own words on what it needs are the deciding fact, re-read literally: "a genuinely new,
type-aware analysis pass component." There is no design for that component yet -- no chosen
approach, no scoped interface, nothing this project could start writing code against tomorrow.
Compressed bounds, by contrast, has been fully specified in `VEDA_CORE_SPEC.md`'s own field table
since before this document's first version. **Sequencing "spec exists" before "spec does not exist
yet" is not deprioritizing security -- it is refusing to let this document quietly skip the design
step §2.12 explicitly still needs**, the same discipline this project applied to Milestone 13
(globals) and Milestone 25 (full-GPR-context-save), both of which got their own Plan-Mode design
pass before any code, not an improvised fix mid-implementation. **Concrete next action, therefore,
is two-staged, not single-tracked: (1) build `Length`/`Offset` compressed bounds now, per the
2026-08-09 decision, unchanged; (2) run a dedicated design pass for §2.12's type-aware shadow
propagation -- scoping it, not implementing it, is the next real step for that gap -- before it
can honestly be called "ready," at which point it becomes the next Tier-1-eligible item on this
list.** This is a decision, not a deferral disguised as one: it commits to starting §2.12's design
work now, in parallel, rather than letting "we'll get to it" stand unstated the way the original
Tier 4 software-ecosystem entry was left standing (and later corrected) in the 2026-08-09 pass.

## DECIDED, 2026-08-16: field widening, not CHERI-Concentrate-style compression

Tier 1 item 1 above left the encoding choice open ("CHERI-style compressed bounds, or a narrower
fixed-point widening"). That choice is now made, after reading the official CHERI ISA specification
(`specs/cheri-architecture.pdf` -- Section 2.3.11 p.58, Sections 3.5.3/3.5.4 pp.90-105, Section 9.23
"Semantic Goals"/"Precision Effects for Compressed Capabilities" pp.333-345, Section 11.2
"Compressed Capability Optimizations" pp.354-365, Appendices D/E pp.523-541) in full, the official
CHERI Concentrate paper (Woodruff et al., IEEE Trans. Computers 2019, read in full from the authors'
own Cambridge CL open-access copy, not a third party), a search for independent security critique of
this specific mechanism, and this line's own current `veda_core.tlv`/`VEDA_CORE_SPEC.md`.

**Decision: widen `Length`/`Offset` in place. Do not adopt CHERI Concentrate's compressed
(exponent+mantissa) bounds encoding for this line.**

**Reasoning, security first (this project's stated main goal):**

1. **CHERI's own spec discloses a real, named residual risk that applies directly to this project,
   not hypothetically.** Section 9.23.2 (p.334-335), quoted verbatim: *"128-bit CHERI can provide
   precise subsetting for smaller subsets, but may experience precision effects for larger subsets.
   These are accepted in our programmer model, and **could permit buffer overflows between
   subsets**, which would be prevented in the 256-bit model."* This risk is specific to
   `CSetBounds`-based narrowing of an already-live capability (as opposed to a fresh allocation) --
   and `CSetBounds`/`CSetBoundsExact` are not hypothetical here, they are this line's own real,
   already-shipped instructions (RTL Milestone 3). Adopting compression would import this exact,
   self-disclosed CHERI risk class into a mechanism this project already exposes to software today.

2. **The mitigation CHERI's own spec requires for this risk (`CSetBoundsExact` + `CRAM`/`CRRL`
   allocator cooperation, p.334-335, p.335 S9.23.3) is real and workable, but it is a mitigation for
   a risk that widening does not create in the first place.** Choosing not to import a risk class
   beats importing-then-mitigating it, when a working alternative already exists (see point 4).

3. **Compression's real hardware cost assumes pipelining this line does not have.** The spec states
   decompression "generally require[s] the majority of a cycle" (p.357) and that real
   implementations resolve precise bounds checks "usually in the next pipeline stage" (p.357) --
   i.e. the cost is real and is hidden by pushing it downstream in a pipeline. `rva23-core` is
   single-cycle by design, a core identity trait of this specific line, not an incidental
   implementation detail -- there is no "next stage" to push this into. The CHERI Concentrate
   paper's own positive hardware result (FPGA synthesis on a Stratix V, "achieves the same [max]
   frequency as the original 256-bit implementation") was measured on a pipelined design; it is not
   evidence this holds for a single-cycle core, and no synthesis-based check of that specific
   question exists yet for this project.

4. **A real, already-verified widening precedent exists inside this project already.** The Linux
   line ([[veda-core-linux-line]], a separate initiative on the same codebase) hit essentially the
   same problem at larger scale and chose widening, not compression -- growing the capability from
   128 to 256 bits (`Base` 56, `Length` 40), Sail 70/70 and RTL verified. That work is a real,
   working reference to adapt, not a green-field design. It also confirms this project's own
   precedent leans towards widening when the option is available, independent of this decision.

5. **New, complex logic is where this project's own real bugs have hidden, repeatedly.** CHERI's
   `SetBounds` algorithm (Appendix D.5, pp.529-532, ~135 lines) computes a new exponent via
   leading-zero-count, derives rounded base/top mantissa fields, and speculatively pre-computes both
   the rounded and unrounded paths before a late select (p.357) -- substantial new combinational
   logic. Widening is comparatively low-novelty: bit-slice re-positioning across roughly 81 lines of
   `veda_core.tlv` already touching `OCL.C`/`OCS.C` (grep-confirmed), plus CRF/field-read
   re-slicing -- mechanical work this project's own mutation-testing and regression discipline (RTL
   smoke + ACT4) is well-suited to catch mistakes in, not new security-relevant arithmetic.

**What this decision is NOT saying:** CHERI Concentrate is real, working, hardware-proven
engineering -- HOL4 machine-checked correctness proof for the compression arithmetic (over-approximates
requested bounds by a bounded error, per the 2019 paper), validated on real FPGA silicon at parity
clock frequency with an uncompressed baseline. No CVE or independent security critique of this
specific mechanism was found in a real search -- the disclosed risk above is CHERI's own honest
self-assessment, not an external finding. It was examined rigorously and rejected for *this line's*
specific constraints (single-cycle, already-exposed `CSetBounds`, an existing simpler alternative),
not dismissed.

**What this decision does NOT yet settle:** the exact new widths for `Length`/`Offset` (and the new
total capability width). Blindly matching the Linux line's 256-bit/40-bit choice would likely
over-widen for this line's own stated philosophy (modest, data-structure-sized objects, not
Linux-class allocations) at unnecessary hardware cost. **Next concrete step, not yet started:** a
short design pass (lighter than a full Plan-Mode cycle, since the encoding *kind* is now decided) to
(a) pick the actual new bit width informed by this line's own real object-size needs rather than
copying the Linux line's number by default, and (b) run a synthesis-based critical-path check
(matching this project's own established practice, e.g. the prior Yosys-based area/critical-path
study) confirming a wider `OCL.C`/`OCS.C` datapath does not itself threaten single-cycle Fmax --
a real but much smaller and lower-risk version of the same question compression would have raised.

## DECIDED, 2026-08-16 (same day): the exact widths, and a real synthesis check

**Widths chosen: `Length` and `Offset` both grow 16 -> 24 bits** (max object size 65,536 ->
16,777,216 bytes). Grounded in this line's own real constants, not the Linux line's numbers:
`TCM_SCRATCH_SIZE` = 4,096 bytes (`veda_core.tlv:546`) and `ELFMEM_SIZE` = 524,288 bytes
(`veda_core.tlv:500`, the real simulated-memory ceiling this project's own testbenches run against
today). 16 MiB is ~32x that current simulation ceiling -- generous headroom without matching the
Linux line's 256-bit/40-bit format, which this document already named as likely over-widening for
this line's own "modest, data-structure-sized object" philosophy. `Base` (32 bits, up to 4 GiB)
is untouched -- not the bottleneck. New capability total: 127 (current named-field sum) + 8 + 8 =
143, +1 pad = **144 bits (18 bytes)** -- not a power of two, and that is a deliberate, accepted
trade (`OCL.C`/`OCS.C` move 18 explicit bytes instead of 16; mechanical, not a blocker -- there is
no architectural requirement that a capability register be a power-of-two byte count, only that
`veda_core.tlv`'s per-byte pack/unpack arms enumerate the real count, which they will).

**Real synthesis check, same methodology as `SYNTHESIS_CRITICAL_PATH_STUDY.md`** (Yosys 0.58,
`proc; opt; techmap; opt; abc -g AND,OR,NAND,NOR,XOR,MUX; stat; ltp -noff`, no PDK -- generic
technology-independent gate analysis, not absolute picoseconds). Three real expressions faithfully
transcribed from `veda_core.tlv` (not approximated), 16-bit-current vs 24-bit-widened, everything
else byte-identical between the two: (A) `OCL.C`/`OCS.C`'s real address (`:1772`) + bounds check
(`:1797`) -- the highest-frequency per-access path; (B) `CSetBounds`'s window check, `Offset` +
new-length vs `Length` (`:1920`) -- a real, already-shipped instruction; (C) the
`OCInvoke`/`OCJALR`/`OCReturn`-style target address, `Base+Offset` (`:2072`, identical pattern at
`:2140`/`:2205`) -- a control-flow-critical path feeding the next fetch address.

| | Longest topological path (gate levels) | Total mapped cells |
|---|---|---|
| Current (16-bit `Length`/`Offset`) | **62** | **740** |
| Widened (24-bit `Length`/`Offset`) | **68** | **921** |

**Honest reading: the cost is real, not free** (contrary to a first-pass guess that an
already-64-bit-wide comparator would absorb the width change for nothing) -- roughly +10% depth,
+25% cell count on this isolated per-access logic cone. One real methodological caveat, stated
plainly rather than glossed over: both designs' longest path is reported as terminating at a
`real_addr` output bit even though `real_addr = Base + rs2_data` does not itself reference
`Length`/`Offset` in either version -- Yosys's `opt`/`abc` passes restructure logic across a
module's shared inputs (here, `rs2_data` feeds both the address add and the bounds-check add), so
this measures the real combined per-access logic cone as a whole, not a perfectly isolated single
expression. That is a real, disclosed limit on precision, matching the prior study's own "first
signal, not a final answer" framing -- not a reason to distrust the measured depth/area numbers
themselves.

**What settles the Fmax question, and why it settles it:** `SYNTHESIS_CRITICAL_PATH_STUDY.md`
already measured, on this same core, with the same methodology, two paths that are real, shipping,
and already proven to complete within one cycle today: a plain RV64I load address (114 gate
levels) and `OCL.D`'s full five-check chain (95 gate levels). The widened 24-bit path (68 gate
levels) sits comfortably below **both** of those already-working numbers -- it does not even
approach the depth this exact core has already empirically shown it can absorb in a single cycle.
This does not prove Fmax is safe (no PDK, no place-and-route, same honest limit the prior study
named), but it is real, comparative, same-methodology evidence pointing away from the worst-case
assumption, not merely an unverified hope.

**Status: encoding kind decided (widening), exact widths decided (16->24 bits), Fmax risk
meaningfully de-risked by real synthesis evidence. Not yet done: the actual Sail respec and RTL
implementation -- both remain real, separately-scoped implementation work with their own positive/
negative tests, mutation tests, and full regression, following this project's own standing
discipline, not silently folded into this design pass.**

## DECIDED, 2026-08-19: the widening's real blast radius, and three architectural breaks the
## "mechanical" framing above did not anticipate

Before touching Sail or RTL, every real touch point for the 16->24-bit `Length`/`Offset` widening
was mapped directly against the current source (not assumed): the full capability pack/unpack path
in both `veda_types.sail` and `veda_core.tlv`, every zero-extension/sentinel site, the ODT's own
Length storage, both ODT-Populate encodings, the capability tag-store's granule arithmetic, and the
C-emulator GDB-stub support that also serializes the 16-byte capability format. The 2026-08-16
decision above correctly settled the encoding *kind* and *widths*; this pass settles the
*implementation-level* consequences, three of which are real architectural breaks, not bit-slice
edits, and were not visible until the full source was actually read end to end.

**Correction to the 2026-08-16 entry's own arithmetic, found in the process:** that entry's Part-1
description of the *current* register ("128 bits plus out-of-band Tag") is stale -- the real
field sum is `23+32+16+16+16+16+8 = 127` bits (`veda_types.sail:59-67`, `veda_core.tlv`'s own `/vreg`
declarations agree), not 128; the widening math the same entry does later (line ~929) already and
silently uses the correct 127. New total, unchanged from that entry: `127 + 8 + 8 = 143`, `+1` pad
bit = **144 bits (18 bytes)**.

**Break 1 -- the tag-store's granule arithmetic assumes a power-of-two capability width, and 18
bytes is not one.** `tag_mem`/`tcm_scratch_tag` are sized `ELFMEM_SIZE/16`/`TCM_SCRATCH_SIZE/16` and
indexed by `addr >> 4` (`veda_core.tlv:516,548,1871,1887,1904,3152` and the Sail-side tag-store,
`model/core/mem_metadata.sail:34,40-76`, built the same way) -- a right-shift, which is only correct
because 16 is a power of two and evenly divides the current 16-byte capability. 18 does not have that
property (`18 = 2 x 3^2`; its only power-of-two factor is 2). Three options were weighed, not
guessed between:
- Real division by 18 for the granule index -- rejected: this is exactly the "new, complex
  arithmetic" the 2026-08-16 decision's own Reason 5 named as the thing widening was chosen *to
  avoid* (constant-divisor division still synthesizes to a real multiply/shift network, not a bare
  shift); adopting it here would undercut that decision's own stated reasoning.
- Pad the capability to the next power of two (32 bytes / 256 bits) so the granule trick needs no
  change -- rejected: doubles the register's real, moved-on-every-`OCL.C`/`OCS.C`/SSC-spill width
  for 14 bytes of pure padding, a much larger, more pervasive cost than the 2026-08-16 decision's own
  accepted 18-byte trade, and inconsistent with `Object_ID`/`Base`/`Perms`/`otype` all staying exactly
  as they are today.
- **Shrink the tag-store's own granule to the largest power of two that evenly divides 18 bytes,
  which is 2 bytes.** `18 / 2 = 9` exactly, so an aligned capability-store never partially overlaps a
  granule shared with unrelated adjacent data (the real security property the granule trick exists to
  protect -- a partial/shared final granule would let unrelated bytes silently inherit a valid tag from
  a neighboring real capability, or vice versa). This keeps the indexing a bare shift (`>>4` -> `>>1`),
  keeps the capability's own serialized width at exactly 144 bits with no padding, and costs a real but
  bounded 8x growth in tag-array *entry count* (each entry is 1 bit) -- for `ELFMEM_SIZE=524288`:
  32,768 tag bits (4 KiB) today -> 262,144 tag bits (32 KiB) widened; `TCM_SCRATCH_SIZE=4096`: 256
  bits (32 B) -> 2,048 bits (256 B). Both are simulation-scale behavioral arrays in this project's
  current no-PDK stage, not real tag-SRAM, so this is judged the right trade: smallest real hardware
  cost that still satisfies both the "no real division" and "no shared/partial granule" requirements
  simultaneously, and the *only* one of the three options that does both without also either adding new
  complex arithmetic or padding the register itself.

  **Decided: tag-store granule = 2 bytes.** Every `>>4` in the tag-granule path becomes `>>1`;
  `ELFMEM_SIZE/16`/`TCM_SCRATCH_SIZE/16` become `/2`; a capability-store's tag-set/-clear logic moves
  from writing 1 granule bit to writing a fixed, compile-time-known 9 granule bits per store (18 bytes
  / 2-byte granule, exact, no remainder, fully unrollable -- still mechanical, not a loop over a
  runtime-variable count).

**Break 2 -- `VEDA_ODT_POPULATE_FAST`'s `veda_attr` CSR overflows.** `veda_attr` packs
`Length[31:16](16) @ Perms[15:0](16)` into exactly 32 bits (`veda_core.tlv:2916`,
`veda_regs.sail:227-235,317`); at 24-bit `Length` that pair needs 40 bits, which does not fit.
**Decided: widen `veda_attr`'s own declared width from 32 to 40 bits** (`Length[39:16] @
Perms[15:0]`) -- both the Sail scan and direct reading of the CSR-read path confirm `veda_attr` is
already `zero_extend`-read into a 64-bit CSR value on every read, so this needs no change to the CSR
mechanism itself, only the register's own declared width and the two pack/unpack slice expressions.
No instruction-encoding change follows from this -- `.fast` itself never packed `Length` into a GPR
operand, only into this CSR, so the fix is fully contained to the CSR's own declaration.

**Break 3 -- plain `VEDA_ODT_POPULATE`'s single-GPR descriptor overflows, and cannot be widened at
all.** `veda.odt.populate` (not `.fast`) packs `Base[63:32](32) @ Length[31:16](16) @
Perms[15:0](16)` into one 64-bit `rs2` GPR, exactly filling it today (`veda_core.tlv:1441-1454`,
mirrored in `veda_cap_insts.sail`). At 24-bit `Length` the needed total is `32+24+16 = 72` bits --
this is not a slice that can widen, because a RISC-V GPR is fixed at 64 bits by the base ISA itself;
there is no wider register to grow into, unlike `veda_attr`. Two real alternatives were weighed: (a)
split plain `POPULATE` across two instructions/registers, mirroring how `.fast` already splits
Length-staging (via `veda_attr`) from the per-call `Base`, or (b) leave plain `POPULATE`'s own
encoding completely unchanged and accept an explicit, named scope limit on it specifically.
**Decided: (b) -- plain `VEDA_ODT_POPULATE` keeps its exact current encoding, unchanged, and
therefore can only directly create objects up to 65,536 bytes (its own `Length[31:16]` slice stays
16 bits, always zero-extended into the ODT's now-24-bit Length field).** Reasoning: this is a
strictly smaller, zero-risk, zero-behavior-change footprint than redesigning a second, already-shipped
instruction's calling convention, `VEDA_ODT_POPULATE_FAST` already exists specifically as the
higher-capability path (Milestone 18) and, per Break 2, already carries a 24-bit-capable `Length` once
`veda_attr` widens -- so no real capability is lost, only re-homed onto the instruction that already
existed to hold it. Software needing an object above 64 KiB must use `.fast` (or `Rebind` against an
ODT entry populated some other way); this is recorded here as an explicit, permanent scope statement
about plain `POPULATE`, not a silent gap -- symmetric with how this project already treats every other
named "not yet done."

**ODT entry's own Length field:** widens 16->24 bits using its own two already-spare bytes
(`odt_mem[]` offsets 14-15, confirmed spare by the byte-budget audit against the ODT's own header
comment) rather than shifting `Perms`/generation/`valid`/`owner_hart`/`id_hi`/retired-bit down by a
byte -- the smaller-blast-radius option of the two real choices found (the alternative would touch
roughly a dozen `odt_mem[$veda_odt_addr+N]` sites across the file for no benefit).

**The "unbounded" sentinel invariant, made explicit for the first time:** every one of the 8
`veda_pcc_length`/`veda_mepcc_length` "unbounded" comparisons (`veda_core.tlv:628-630,2714,2876,
2871-2878,2900-2906,3140`, and the Sail-side `VEDA_PCC_UNBOUNDED`) hard-codes the literal `16'hFFFF`
without the underlying rule ever being written down as a named invariant anywhere in the file.
**Decided, and now recorded as an explicit invariant: the unbounded sentinel is always "all-ones of
the field's current declared width."** This is not a new rule -- it is the same rule every existing
site already encodes -- but widening forces every literal to be re-derived, and doing that
consistently requires the rule to be named once rather than independently re-inferred at each of the
eight sites. Concretely becomes `24'hFFFFFF`.

**GDB-stub / C-emulator support is in scope for the same milestone, not deferred.**
`c_emulator/riscv_model_impl.{h,cpp}`'s `pack_veda_capability_reg` (hard-coded 16-byte output buffer)
and `c_emulator/gdbstub.cpp`'s register-read loop and target-description XML (`count="16"`,
`bitsize="128"`) all serialize the capability register for a connected debugger. Left unwidened
alongside the Sail-side change, these would silently truncate every capability register a developer
reads over GDB post-widening -- a real, silent regression in a tool this project's own
`DEVELOPER_WORKFLOW_GUIDE.md` documents as load-bearing. **Decided: update these in the same
implementation pass as the Sail model, not as separately-scoped follow-on work**, since the risk is
silent corruption of debugger output, not a missing feature.

**What this changes about the two "Not yet done" implementation items above:** both are still real,
separately-scoped work with their own tests -- but "the actual Sail respec" now names five concrete
sub-changes (struct/pack-unpack widths, `veda_attr` widening, ODT Length using its spare bytes, the
sentinel becoming `24'hFFFFFF`, the GDB-stub serialization), and "the actual RTL implementation" now
additionally includes the tag-store granule change (Break 1), which is the one item in the whole scan
that needed a real design decision rather than a mechanical edit, and is judged the single highest-risk
piece of this whole milestone -- it directly gates the tag mechanism's own correctness, the primitive
this entire architecture's memory-safety claim rests on. Sail work is sequenced first (this project's
own established Sail-before-RTL pattern, restated explicitly here since the 2026-08-16 entry did not
commit to an order), each of the two layers gets its own positive/negative tests and mutation test for
the widened bounds behavior specifically (not just a re-run of existing tests with wider literals),
and a dedicated adversarial test targets Break 1 directly: constructing a capability store adjacent to
unrelated poisoned data and confirming the poisoned bytes' tag is never spuriously set.

## DECIDED, 2026-08-19 (same day): a thorough pre-implementation audit -- explicitly requested,
## because "widen two fields" was still hiding real unknowns

The 2026-08-19 entry above was itself audited before writing any code -- not out of process for its
own sake, but because a direct question was asked: does treating this as "mechanical" understate a
change to a time-critical, deterministic-performance, embedded-line core's own core format? It did.
Six real findings, each changing or hardening a decision above.

**Completeness re-scan found real touch points the first pass missed, one of which forces a genuinely
new decision:**
- **CSeal writes `cs2.Offset` directly into `otype`** (`veda_cap_insts.sail:288`, RTL
  `veda_core.tlv:1730`) -- a real cross-field-width coupling, not a copy-fix, once `Offset` grows past
  `otype`'s unchanged 16 bits. Widening `otype` too was considered and rejected -- it was never named
  as changing in the 2026-08-16 decision, has its own established 16-bit sentinel scheme
  (`0xFFFF`/`0xFFFE`) used extensively elsewhere, and widening it would itself open new touch points
  for no benefit. Silently truncating `cs2.Offset` to 16 bits on the way into `otype` was also
  rejected: two different `Offset` values differing only in bits above 15 would alias to the same
  `otype`, a real type-confusion risk in the exact mechanism (`CSeal`/`CUnseal`) that exists to
  authenticate types -- and per this project's own standing discipline, a silent failure here is
  strictly worse than a loud one. **Decided: CSeal requires `cs2.Offset`'s bits above 15 to be zero as
  an explicit precondition, trapping (reusing the existing CSeal-authorization violation path) if
  violated, rather than truncating.** Legitimate existing uses (anything that only ever used values a
  16-bit `Offset` could hold) are unaffected byte-for-byte; only a newly-possible, previously-unreachable
  input is newly, loudly rejected.
- **`OCRETURN` writes `veda_pcc_length` independently of `OCInvoke`** (`veda_cap_insts.sail:647-648`,
  RTL `veda_core.tlv:2873/2880`) -- both narrow the live compartment from a capability's `Length`; both
  copy sites need the same width change, tracked together now, not just OCInvoke's.
- **The `VEDA_PCC_UNBOUNDED`/`0xFFFF` sentinel is a ~15-site family, not the CSR plumbing alone**:
  fetch-time enforcement (`veda_core.tlv:628-630`, the real security boundary), purecap data-access
  gating (`3139-3140`), CSR-escape gating (`2711-2714`), the mtvec-gate itself
  (`veda_regs.sail:219`), and the mret-restore mux (already known) all independently hardcode the
  same all-ones comparison. All ~15 sites move to the new sentinel together in the same change, or the
  fetch-bounds check, the purecap gate, the mtvec-gate, and the mret-restore mux go inconsistent with
  each other silently -- exactly the class of cross-mechanism drift this project's own R21 was.
- **Veda-Atomic (9 AMO ops) is a real, separate touch point** (`veda_atomic_insts.sail:72`, RTL
  `veda_core.tlv:2445/2456`) -- its own bounds-check call site and its own `{48'b0,...}` zero-extension
  literal, sharing the underlying mechanism with OCL.C/OCS.C but not the same code path.
- **OSpecialRW's privilege gate and the U-mode compartmentalization gate itself are confirmed clean**
  -- read directly, neither references `Length`/`Offset` anywhere (tag/otype/perms only); ruled out by
  evidence, not by not looking.
- **Three real toolchain-layer hardcodes, outside Sail/RTL entirely**: `veda_rt.h`'s
  `veda_rt_init(uint16_t length, uint16_t perms)` packs the `veda_attr` CSR in C and needs a real
  signature/packing change once `Length` exceeds 16 bits; `VedaShadowPropagation.cpp`'s
  `kVedaCapTableSlotBytes = 16` (Toolchain M13/M15's per-global capability table sizing) must track the
  new byte count; and a `slli ..., 16` descriptor-packing pattern recurs in 9 real, already-shipped
  bootstrap `.S` files (`veda_global_protect_entry.S` and 8 others) that construct plain
  `VEDA_ODT_POPULATE`'s `Base|Length|Perms` GPR descriptor by hand. **This last one turns out to need
  zero changes**, precisely because of this same date's Break-3 decision (plain `POPULATE` keeps its
  exact current 16-bit-`Length`-slice encoding, unchanged) -- these 9 files never construct a
  descriptor wider than 16-bit `Length` today and will keep working byte-for-byte identically.
  `container_of`'s demo and `veda_rt_asm.S`'s `csetbounds` calls were checked and confirmed clean (no
  capability-byte-count assumption in either).

**Tag-granule decision (Break 1) reversed, on real evidence, not preference.** Real primary-source
research (the CHERI ISA specification, the CHERI Concentrate paper, ARM's own Memory Tagging Extension
whitepaper, and Oracle SPARC M7 ADI documentation) found a **unanimous real-hardware pattern**: every
shipped or heavily-cited tagged-memory design uses a **fixed, power-of-two tag granule** and handles
objects that don't divide evenly into it by **rounding the storage slot up to the granule boundary and
accepting the padding as a known, quantified cost** -- ARM's own MTE whitepaper states this explicitly
and measures it ("the increase is usually small"). No real design was found that subdivides a single
tag's coverage into a finer granule to fit an odd object size -- the one paper gesturing that direction
(Multi-Tag, AsiaCCS 2023) still uses coarse, stacked granules, not sub-object tracking, per what was
retrievable of it. This directly weighs against the earlier 2-byte fine-granule choice, which had no
real precedent behind it.

A real, both-designs Yosys synthesis check (same methodology as every other check in this document)
confirmed the literature's implication with real numbers: a 9-write fine-granule tag-write module (the
2-byte-granule design) costs **540 mapped cells** against a 2-write coarse-granule design's **75** --
**7.2x more area** -- while both designs show the **identical 15-gate-level critical path** (writes are
parallel, not serial, so more ports cost area, not depth -- a real, reassuring, non-obvious result for
Fmax specifically). A real usage-pattern check found the current test corpus has never exercised more
than 1-2 concurrently-spilled capabilities in TCM scratch or SSC storage against 256 slots available
today -- halving that to 128 slots under a coarser, 32-byte-aligned scheme leaves 64-128x real headroom,
not a live constraint.

**Decided: reverse Break 1. Keep the tag-store's granule at exactly 16 bytes, completely unchanged --
`>>4` stays `>>4`, `ELFMEM_SIZE/16`/`TCM_SCRATCH_SIZE/16` stay as they are, zero code touched in the
existing tag-index computation. Require capability-store addresses to remain 32-byte aligned (the
next granule boundary up from today's 16-byte alignment); one capability-store now sets/clears exactly
2 adjacent, always-contiguous granule bits (never 9, never a runtime-variable count) in the same single
clock edge the existing 16-byte write already uses -- confirmed against the real RTL
(`veda_core.tlv:3711-3746`) to be the same single-`always_ff`-block, single-cycle pattern OCS.D and
ODT-Populate already use at other widths, so this does not, by construction, introduce a new
register-backed hold/stall mechanism.** This is simultaneously the option with real hardware precedent,
the cheapest by a wide margin, equally fast, and the smallest possible blast radius (the entire granule
mechanism itself is now untouched code).

**Real-time audit cross-check: two clean, one open item, named honestly.** Re-derived against the live
`REALTIME_SAFETY_CRITICAL_AUDIT_RESULTS.md` reasoning, not just its headline conclusions: the
WCET-analyzability argument depends on the DRAM-stall being a fixed, data-independent constant, never
on capability size, so widening cannot touch it; the DRAM-stall's own cycle formula
(`$veda_dram_stall_req`/`$veda_dram_stall_cnt`) contains no width term and is physically grounded in a
DDR4 row-access cost that doesn't scale with an 18-vs-16-byte transfer either, so no interaction there
either. **The one genuinely open item, not resolved by reasoning alone**: the audit's own "exactly one
hold/stall mechanism in the whole file" claim is a snapshot fact about the file as it exists today, and
the chosen 2-granule-write design does not by construction need a new one -- but this must be
**re-verified against the real, changed RTL once it exists**, using the audit's own method (grep every
`busy|stall|freeze|hold|wait` and `$pc`/NOP-forcing site), not presumed to still hold from this
document's reasoning alone. This re-verification is added as an explicit, required step of the RTL
milestone's own test/results doc, not assumed.

**Embedded-domain fit: the 16 MB target itself is reconsidered, on real evidence, independent of the
widen-vs-compress choice.** Real, named embedded/MCU datasheets (Nordic nRF52, ST STM32F2/H7, Microchip
SAM4S/D51) show on-chip SRAM topping out around 1 MB even on the largest, most expensive Cortex-M7-class
parts available; RFC 7228's own constrained-device taxonomy tops its largest class at ~50 KB RAM. Against
this real data, a 16 MB single-object ceiling is not "modest, data-structure-sized" (this line's own
stated philosophy) -- it exceeds the *entire* on-chip SRAM of nearly every real embedded target, several
times over even the largest ones, and was in fact sized against this project's own 512 KB *simulation*
memory constant (`ELFMEM_SIZE`), not real target hardware, when first decided. Separately, real research
into CHERIoT (MICRO'23, the closest real published embedded-CHERI precedent) confirms it uses a
*compressed* capability (65 bits total: 32-bit metadata + 32-bit address + tag, via a floating-point-style
B/T/E encoding) specifically to get large dynamic range cheaply -- but CHERIoT's own reference
implementation is the Ibex core, which is pipelined, not single-cycle, so this does not weaken this
project's own single-cycle-specific reasoning for rejecting compression (2026-08-16 entry, Reason 3) --
it is evidence about *range-per-bit*, not about *pipelining*, and the two decisions are separable.

**Decided: reduce the target from 24-bit to 20-bit `Length`/`Offset` (max object size 64 KB -> 1 MiB,
not 16 MiB).** 1 MiB is a real, evidence-grounded ceiling -- it matches, almost exactly, the largest
on-chip SRAM found on real high-end embedded targets (STM32H7-class), rather than an internal
simulation constant, and is still a real 16x increase over today's 64 KB ceiling, not a token change.
This does not reopen the widen-vs-compress decision (unaffected, still single-cycle-specific) and does
not change the tag-granule decision above (the resulting total width -- 127 - 32 + 40 = 135, +1 pad =
**136 bits (17 bytes)** -- still falls in the 17-32-byte range the 2-granule/32-byte-alignment design
already covers without modification; 17 bytes needs exactly 2 granules exactly as 18 bytes did). The
24-bit/68-gate-level/921-cell synthesis numbers in the 2026-08-16 entry were measured for the
now-superseded 24-bit target; a 20-bit path is expected to be strictly cheaper (narrower adders/muxers
throughout) but this is stated as an expectation, not asserted as measured -- **a fresh synthesis check
at the real 20-bit width is a required step before the RTL milestone is called done**, not inherited
by assumption from the 24-bit numbers.

**Updated total: 136 bits (17 bytes), not 144 (18).** Every site catalogued in the 2026-08-19 entry
above is unchanged in *kind*, only in the concrete widths substituted at implementation time (20-bit
slices and an all-ones sentinel of `20'hFFFFF`, not 24-bit/`24'hFFFFFF`).

## CLOSED, 2026-08-16 (same day): R21 -- DRAM-stall could swallow a real trap redirect

Found on the Linux line while adversarially refuting an unrelated timing claim, then independently
re-derived and confirmed still live *here* by direct inspection of this line's own current
`$veda_dram_stall_req` -- not assumed by extension. Milestone 24's stall request gated only on
`!$veda_pcc_violation` (fetch-side); a DRAM-tier `OCL.C`/`OCS.C`/plain-`Bind` access that also
violated could still fire the stall, and the `$pc` mux ranks `$veda_dram_busy` above the trap
redirect -- discarding it while trap state effects still fired. Real, both-directions proof at a
temporarily nonzero `DRAM_EXTRA_CYCLES=10` (the shipped `E=0` default makes the path structurally
unreachable): pre-fix, `x20=0xE5CA` (escaped); post-fix, `x20=0x600D` (correctly trapped). Fixed by
gating the stall's two arms on the real, already-existing violation/trap signals for this arm
(`!$veda_bind_trap`, `!$veda_oclc_violation && !$veda_ocsc_violation`) -- strictly monotone, can only
remove a stall on a path that traps anyway. Full regression 54/54 (53 pre-existing + new
`veda_smoke_r21_dram_stall_trap_neg`), ACT4 51/51, zero regressions. See
`rtl/MILESTONE_R21_DRAM_STALL_TRAP_FIX_RESULTS.md`. **The correctness-only follow-on (FIX 2-
equivalent: ordinary branches/jumps/`mret` also silently swallowed during a stall) remains real,
named, and explicitly not attempted** -- needs its own `$pc`-mux redesign and its own test, matching
the Linux line's own identical scoping choice.

This was the first, most urgent item of a broader real-time/safety-critical systems audit
(determinism/WCET, bounded interrupt latency, no unbounded blocking, and a grep-audit for this same
"stall outranks trap" pattern class elsewhere in the file) -- not yet started as of this entry.

## DONE, 2026-08-16 (same day): the broader real-time/safety-critical audit

See `rtl/REALTIME_SAFETY_CRITICAL_AUDIT_RESULTS.md` for the full write-up. Headline findings, each
grounded in an official/canonical source read in full: (1) this core's own single-cycle, in-order,
cache-less, speculation-free design places it in WCET analysis's own *easiest* category (Wilhelm
et al. 2008), and its fixed-`localparam` DRAM-stall specifically does NOT threaten WCET-analyzability
by that literature's own criteria; (2) the R21-class bug is exhaustively confirmed closed -- direct
re-derivation found exactly one hold/stall mechanism in the whole file, so R21's fix is complete,
not partial; (3) the Linux-line's own deferred "FIX 2" concern (ordinary branches/jumps/`mret`
swallowed during a stall) is confirmed **not reachable on this core** via direct opcode-encoding
inspection (the stall-triggering Veda custom0 opcode is structurally disjoint from
jal/jalr/branch/`mret`'s own opcodes) -- a real closure, not a restatement of "deferred"; (4) the
seminal priority-inversion paper's bounded/unbounded distinction (Sha/Rajkumar/Lehoczky 1990),
applied as this project's own extension, classifies the DRAM-stall's delay to a pending trap as
bounded (a fixed, known cycle cap), not the unbounded/unpredictable kind real-time systems must
avoid.

**Genuinely still open, named honestly, not assumed clean:** no computed/documented worst-case
interrupt-to-handler latency number exists yet for this core (RISC-V's own spec leaves this
implementation-defined, so nothing supplies one for free); Veda-Core's own custom trap-cause
priority has not been cross-checked against RISC-V's official synchronous-exception priority table
(Table 105) where they overlap; WFI's real behavior on this core was not itself audited this pass.

## DONE, 2026-08-19 (same day): Length/Offset widening implemented in Sail, 70/70 regression

Full write-up: `MILESTONE_LENGTH_OFFSET_WIDENING_RESULTS.md`. Implements both same-day "DECIDED"
entries above -- `capability.Length`/`.Offset`/`odt_entry.Length`: `bits(16)` -> `bits(20)`; packed
capability 128 -> 136 bits (17 bytes); `VEDA_PCC_UNBOUNDED` sentinel `0xFFFF` -> `0xFFFFF`; `veda_attr`
CSR widened 32 -> 36 bits (Perms kept at its original `[15..0]`, only Length's own span grew); every
touch point the prior audit named, across `veda_types.sail`/`veda_regs.sail`/`veda_cap_insts.sail`/
`veda_ocl_insts.sail`/`veda_bind_insts.sail`, plus the GDB stub's own 17-byte capability-register
XML/buffer.

**Three real findings beyond the mechanical bit-slice work, all fixed this pass:** (1) CSeal's own
`otype = cs2.Offset` assignment is a genuine narrowing truncation now (otype deliberately did NOT
widen) -- fixed with an explicit "upper 4 bits must be zero" precondition on the one real mint site,
and a `zero_extend(cs1.otype)`-based comparison (mathematically equivalent, simpler) on CUnseal/OCJALR's
own compare-only sites; (2) OCL.C/OCS.C now hard-require 32-byte-aligned store addresses (new cause
`VEDA_CAUSE_ALIGNMENT_VIOLATION=0x08`) -- real Sail/RTL parity with the already-decided 2-granule RTL
tag-write design, not something Sail's own tag mechanism strictly requires, but needed so Sail's
reference behavior doesn't diverge from what RTL will enforce; (3) `mem_metadata.sail`'s own tag-store
implementation had a real, previously-undiscovered single-granule bug (verified only against a
synthetic RTL-mockup synthesis check in the prior audit, never against this file's own real logic) --
a 17-byte capability's own 17th byte always spills into a second granule the old code never touched
at all, meaning that byte's data reached RAM unprotected by the tag mechanism; fixed to touch/check
both of an access's real granules.

Also found and fixed, not part of the original touch-point map: ~20 pre-existing `sail_tests/*.S`
files hardcoded the OLD `0xFFFF` sentinel literal at sites meaning "the real unbounded PCC value,"
now silently wrong (one produced a genuine multi-minute simulator hang before being caught and fixed);
and one existing OCL.C/OCS.C-spill test's own SPILL object was sized for the old 16-byte capability
exactly, correctly `BOUNDS_VIOLATION`-trapping until re-sized.

**Verification:** 70/70 full regression (65 pre-existing + 5 new: widened-bounds positive/negative,
CSeal-offset-high-bits negative, OCL.C/OCS.C alignment negative, and a dedicated adversarial
granule-adjacency test proving no spurious tag-sharing beyond the real 2-granule span). Mutation-tested
all three new mechanisms (CSeal precondition, alignment gate, multi-granule tag write) -- each
correctly flips its own new test to `FAILURE` when disabled, reverts cleanly to 70/70.

**Not yet built, named honestly:** the RTL mirror (`rtl/veda_core.tlv` still has the old 128-bit/
16-byte format throughout -- CRF fields, pack/unpack, `tag_mem` sizing, the `16'hFFFF` sentinel family,
~15 sites per the prior audit), a fresh Yosys synthesis check at the *real* 20-bit width (the prior
audit's 540-vs-75-cell numbers were measured on synthetic mockups for comparing granule strategies in
the abstract, not this real width), the required re-verification of
`REALTIME_SAFETY_CRITICAL_AUDIT_RESULTS.md`'s "exactly one hold mechanism" claim against the actual
changed RTL, and the toolchain layer (`veda_rt.h`'s `veda_rt_init` signature,
`VedaShadowPropagation.cpp`'s `kVedaCapTableSlotBytes`). Not committed or pushed yet.
