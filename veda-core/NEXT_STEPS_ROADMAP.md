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
