# Real-time / safety-critical systems audit -- embedded line (rva23-core)

**Date:** 2026-08-16. Follows directly from the R21 fix
(`MILESTONE_R21_DRAM_STALL_TRAP_FIX_RESULTS.md`), which this audit named as its own first,
most urgent item.

## Method

Official-source research (read in full, not fragments) plus direct re-derivation from
`rtl/veda_core.tlv`:

- The official RISC-V Instruction Set Manual, Privileged Architecture volume
  (`specs/riscv-spec.pdf`, pp.679-719): the full machine-level trap chapter -- interrupt-enable
  stack, `mip`/`mie`, interrupt/exception priority, trap-return, WFI.
- Wilhelm et al., "The Worst-Case Execution-Time Problem -- Overview of Methods and Survey of
  Tools," *ACM TECS* 7(3), 2008 -- the field's own canonical survey, read in full from the
  authors' institutional copy.
- Sha, Rajkumar, Lehoczky, "Priority Inheritance Protocols," *IEEE Trans. Computers* 39(9), 1990
  -- the seminal paper that named and formalized unbounded priority inversion, read in full.
- A complete, grep-confirmed, line-cited re-derivation of every `$pc`-holding /
  `$instr`-NOP-forcing mechanism in `veda_core.tlv`, and a direct opcode-encoding check closing
  the one residual uncertainty that re-derivation left open.

## 1. Architectural fit for WCET analysis -- a real, literature-grounded positive finding

Wilhelm et al.'s own central distinction is context-independence (instruction cost summable,
`ub_A;B = ub_A + ub_B`) versus context-dependence (cost varies with processor history) --  and
the paper's own worst category, **timing anomalies**, is specifically caused by caches,
speculation, and out-of-order scheduling, where "always taking the local worst-case transition...
[does not] produce the global worst-case execution time" (p.36:7). This core has none of those:
no cache (`veda_core.tlv:497`'s own comment states plainly "no address translation" is needed;
confirmed separately elsewhere that no cache structure exists at all), no speculation, no
out-of-order execution, single-cycle in fetch/decode/execute. The paper explicitly places
fixed-timing, in-order, scratchpad-memory designs (its own examples: simple 8/16-bit CPUs, ARM7,
Cortex-R, the Cell SPU's local-memory-not-cache design) at the *easy* end of WCET analyzability
(§11.2, p.36:47-48) -- architecturally, this line already sits in that category.

**Directly answers the DRAM-stall design question**: a fixed, compile-time-constant N-cycle stall
(`DRAM_EXTRA_CYCLES`, a `localparam`, not data- or history-dependent) has *neither* disqualifying
property Wilhelm et al. name -- it cannot vary with execution history and cannot produce a timing
anomaly (there is no "locally faster path" to invert, since N is the same every time). By this
literature's own criteria, `ub_A;B = ub_A + N + ub_B` stays exact, not merely a safe
over-approximation. **The Milestone 24 latency mechanism, even once shipped with a nonzero
default, is not a WCET-analyzability risk** -- a real, sourced answer, not an assumption.

## 2. RISC-V spec: what is and isn't mandated

- **No numeric interrupt-latency bound exists in the spec.** The only requirement is qualitative:
  interrupt-trap conditions "must be evaluated in a bounded amount of time from when an interrupt
  becomes... pending" (p.696-697) -- left entirely implementation-defined. **This means Veda-Core
  owes itself a computed, documented bound if it wants to make a real-time claim; the spec will
  not supply one for free.** Named as a real, open item below, not a spec violation.
- **Official interrupt priority** (simultaneous M-mode interrupts): MEI > MSI > MTI > SEI > SSI >
  STI > LCOFI (p.698); M-mode interrupts always outrank lower-privilege ones (p.697).
- **Official synchronous-exception priority** exists as a full ordered table (Table 105, p.704).
  **Not yet cross-checked**: whether Veda-Core's own `$veda_trap_taken` OR-list
  (`veda_core.tlv:2600-2607`, currently a flat, unordered OR with a separate priority-mux for
  `$veda_trap_cause`) is consistent with, or even needs to be reconciled against, this official
  table -- named as a real open item below, since Veda-Core's own causes are custom (not in Table
  105 at all) but its interaction with the *base* RV64I exceptions that table does cover
  (misaligned access, illegal instruction) was not audited this pass.
- **WFI may legally be a NOP** (p.715) provided the hart still resumes/traps promptly on any
  locally-enabled pending interrupt, "regardless of the global interrupt enable" (p.715). This
  core does not implement WFI as anything beyond ordinary instruction decode (not separately
  audited this pass; named below).
- **mstatus MIE/MPIE stack** (p.684-685) is the standard save-on-trap/restore-on-return
  mechanism; Veda-Core's own trap/`mret` handling was built to this shape in earlier milestones
  (M9 trap infrastructure) -- not re-audited line-by-line this pass, flagged for the same reason.

## 3. R21-class exhaustive audit -- confirmed complete, only one mechanism exists

Direct re-derivation (grep for `busy|stall|freeze|hold|wait`, every `$pc[63:0]` assignment, every
`32'h00000013` NOP-forcing site) found **exactly one** register-backed hold mechanism in the
entire file: `$veda_dram_busy` (Milestone 24). The `$pc` mux has exactly one definition
(`veda_core.tlv:604-608`); `$instr` is forced to NOP at exactly one site
(`veda_core.tlv:667`), gated on `$veda_pcc_violation || >>1$veda_dram_busy` -- both terms
correctly cannot suppress a trap that should fire that cycle (the pcc-violation term is
decode-independent; the busy term holds `$pc` frozen so `$veda_pcc_violation` reads identically
every held cycle, and every *other* term in `$veda_trap_taken` requires decoding a real,
non-NOP opcode, which cannot happen while `$instr` is forced to NOP). **R21's fix is therefore a
complete closure of this bug class for this file** -- not partial, because there is no second
mechanism to have the same gap.

## 4. FIX 2's own concern -- re-examined and closed for this core, not merely deferred

The Linux-line's own R21 write-up named a second, correctness-only concern: the same `$pc` mux
could in principle also swallow an ordinary taken branch/JAL/JALR/`mret`/OCInvoke/OCReturn, not
just a trap, and deliberately left it unfixed pending its own `$pc`-mux redesign. This audit's
own RTL re-derivation could not construct a live path for that on *this* core, and flagged one
specific gap in its own reasoning: opcode disjointness between the stall-triggering Veda custom
opcode and the jump/branch/`mret` decode signals had not been independently confirmed.

**Confirmed directly, this pass**: `$op_is_custom0 = ($opcode == 7'b0001011)` (0x0B) is the
single shared opcode for every Veda-specific instruction, including all three that can trigger
the DRAM stall (Bind-family, OCL.C, OCS.C). `$op_is_jal` (0x6F), `$op_is_jalr` (0x67), and
`$op_is_branch` (0x63) are three distinct opcode values, and `$is_mret` is a *full 32-bit
instruction match* (`32'h30200073`) that cannot equal the forced-NOP encoding (`32'h00000013`).
RISC-V's fixed opcode field means a single instruction has exactly one opcode -- **a
stall-triggering instruction structurally cannot simultaneously be a jump/branch/`mret`**, and
during the additional held cycles `$instr` is unconditionally NOP, so no real jump/branch/`mret`
is ever decoded (hence never "swallowed") during a stall -- it is delayed, correctly, until the
stall clears and the pipeline resumes fetching it on its own real cycle. **Verdict: FIX 2's
scenario is not reachable on this core, confirmed by direct opcode-encoding inspection, not
assumed by extension from the Linux line's more complex (region/domain-bearing) fork.** This is
a genuine, sourced closure -- not a re-statement of "deferred."

## 5. Priority inversion -- the bounded/unbounded distinction, applied (this project's own
synthesis, not a literal claim from the source paper)

Sha, Rajkumar, Lehoczky's own precise distinction: inversion is **unbounded** when a resource
holder's release depends on an uncapped, unrelated chain of intermediate-priority preemptions
("the blocking period... can be arbitrarily long," p.1176); it is **bounded** once the worst case
reduces to a fixed, computable quantity (their own fix: "at most the duration of one critical
section," p.1177). The paper itself is scoped to OS-level task scheduling and does not address
single-hart microarchitecture at all -- applying its principle here is this project's own
extension, stated as such.

Applied: Veda-Core's DRAM-stall delay to a pending trap is a **fixed, compile-time-constant**
`DRAM_EXTRA_CYCLES`, not something that grows with an external, uncapped event stream (there is
no re-triggering mechanism -- once `$veda_dram_stall_cnt` starts counting down, nothing can
extend or restart it before it reaches zero, confirmed by its own definition,
`veda_core.tlv:1029-1032`). By the paper's own bounded/unbounded test, this is **bounded** -- the
worst-case delay to any pending trap is `DRAM_EXTRA_CYCLES` cycles, a fixed, known, documentable
number, the architectural analogue of "one critical section," not an open-ended chain. No
established literature was found framing single-hart internal stall/trap arbitration in
priority-inversion terms specifically (the real hardware-priority-inversion literature that
exists -- MemGuard, Kim et al. -- addresses multicore shared-memory-bandwidth contention, a
different problem); this mapping is offered as sound reasoning grounded in the seminal paper's
own definitions, not as an existing citation for this exact scenario.

## 6. What remains genuinely open (named, not silently assumed clean)

- **No computed, documented worst-case interrupt/trap latency exists for this core.** The RISC-V
  spec does not require a number; a real safety-critical adoption would want one. Concretely
  computable from what already exists (the fixed `$pc`-mux depth plus the bounded
  `DRAM_EXTRA_CYCLES` cap) -- not attempted this pass, named as the natural next step.
- ~~Veda-Core's own custom trap causes have not been cross-checked against RISC-V's official
  synchronous-exception priority table~~ -- **CLOSED, see §7 below.**
- ~~WFI's own real behavior on this core was not audited this pass~~ -- **CLOSED and fixed, see §7
  below.**
- **This audit covered the embedded line's single-hart, single-stall-mechanism reality only.**
  None of it transfers automatically to the Linux line's own multi-hart, region/domain-bearing
  fork, which has its own, separate, already-partially-addressed version of this same bug class.

## 7. Follow-up pass, same day: Table 105 cross-check, WFI, and a fresh out-of-the-box security
   literature search

**Table 105 cross-check -- real bug NOT found, but a real scope gap named.** Direct re-derivation
of `$veda_trap_taken`/`$veda_trap_cause`'s actual decode logic confirms every Veda-specific cause
and the two base-RV64I causes this core implements (`is_ecall`, the CSR-escape's forced Illegal
Instruction) are pairwise mutually exclusive by opcode/funct3 field disjointness or by
`$veda_pcc_violation`'s own NOP-substitution before decode -- verified against the real decode
signals, not the inline comments alone. Since no two causes can ever be simultaneously true, the
if-else *order* of the priority muxes is currently inert (there is no tie for it to break). Table
105 itself grants custom causes implementation-defined priority and explicitly leaves
misaligned-vs-fault ordering implementation-defined too -- Veda-Core owes it nothing further there.
**Real, honest gap, not a bug**: generic illegal-instruction, misaligned-address, and EBREAK (the
base-ISA codes Table 105's own tier 4 groups together) are entirely unimplemented in this core, so
the overlap scenarios the table actually exists to arbitrate (e.g. a misaligned `OCL.D` address
racing a bounds violation) have no code path on either side to check yet -- named for whenever those
land, not fixed here.

**WFI -- found accidentally-correct, made deliberately-correct.** No `$is_wfi` decode existed;
every gating list WFI could touch (`$reg_write`, `$veda_trap_taken`, `$pc_src`) is an explicit
named allow-list, so WFI fell through to a plain `pc+4` advance -- externally indistinguishable
from the RISC-V spec's own explicitly-permitted "implement WFI as a NOP" (p.715), but **fragile**:
nothing marked it intentional, and this project's own established pattern (adding a new
unconditional-trap term to `$veda_trap_taken` as each milestone lands, most recently ECALL) means a
future "unrecognized SYSTEM-opcode word -> illegal instruction" hardening pass -- a reasonable step,
given this core still has no generic illegal-instruction path at all -- would have silently started
faulting WFI, with no TW-bit mechanism behind it to make that legal. **Fixed**: added an explicit
`$is_wfi = ($instr == 32'h10500073)` decode, deliberately left unwired into any control signal (its
only job is to exist as a named exclusion any future catch-all must consult), with a `BOGUS_USE`
matching this file's own convention for intentionally-unconsumed signals. New permanent regression
test, `veda_smoke_wfi_nop.S`/`tb_veda_smoke_wfi_nop.sv`, confirms both that `$is_wfi` fires exactly
once (proving the decode itself works, not just that nothing crashed) and that execution correctly
falls through with no trap and no register write. Full regression **55/55** (54 pre-existing + this
one), ACT4 **51/51**, zero regressions.

**Two quick, targeted checks prompted by real CVE precedent (CVE-2021-1104, an RTCA-disputed
mtvec-reset-value ambiguity; CVE-2026-29642/29643, a real, current XiangShan CSR/illegal-instruction
trap-dispatch hang) -- both confirmed already safe, not fixed because nothing needed fixing.**
`$mtvec` resets to a defined `64'b0` (`veda_core.tlv:2700`), not an undefined/garbage value -- a
trap taken before software installs a real handler redirects deterministically to address 0, not an
attacker-influenced or undefined location, directly avoiding CVE-2021-1104's exact concern. CSR
reads to any unrecognized address fall through to a defined `64'b0` (`$csr_rdata`'s own final
`:` arm) rather than propagating an undefined value -- unlike XiangShan's real bug, which was a
control-flow failure to reach `mtvec` at all, not a data-value issue, so the failure *class* differs
even setting the value-safety point aside.

**Fresh, out-of-the-box literature search -- one well-established real channel class, assessed
honestly for whether it opens anything new here; one DoS class named as forward-looking, not
current-hardware-relevant.** Van Bulck/Piessens/Strackx, "Nemesis" (ACM CCS 2018) is the real,
canonical primary source for trap-*latency* itself (as opposed to the trap's own reported cause or
value) leaking information about the interrupted instruction, because delivery only happens after
the current instruction retires. Assessed against this core specifically: every ordinary
instruction here is single-cycle and constant-time by construction (no cache, no speculation), so
there is no "how long did this take" signal to leak *except* via the R21-fixed DRAM-stall path
itself -- and that path's own timing (TCM-hit vs. TCM-miss) is already directly, legitimately
readable via `CGetBase` (an object's placement is not secret), the identical closure this project's
own R20 finding already established for the physically-analogous question. **No new leak found; not
because the Nemesis mechanism is fictitious, but because this core's own architecture and R20's own
prior closure already remove the precondition it needs.** Mergendahl et al., "The Thundering Herd"
(IEEE RTAS 2022, seL4) is a real, rigorous precedent for exception-rate-based interference attacks,
but it operates at the OS/scheduler level (IPC/budget-accounting abuse across many threads) -- this
core has no OS or multi-threading built into the hardware itself yet (the Minimal OS Kernel's own
cooperative scheduler is a separate, much smaller software layer); named as real, relevant context
for that layer's own eventual design, not a finding against the hardware audited here.

## Files

- `rtl/veda_core.tlv` -- the explicit `$is_wfi` decode (documented no-op, `BOGUS_USE`-marked).
- New: `rtl/sim/veda_smoke_wfi_nop.S` + `tb_veda_smoke_wfi_nop.sv`.
- `rtl/run_veda_smoke_test.sh` -- registers the new test.

The prior fix this document builds on and closes out the reachability question for is
`MILESTONE_R21_DRAM_STALL_TRAP_FIX_RESULTS.md`.
