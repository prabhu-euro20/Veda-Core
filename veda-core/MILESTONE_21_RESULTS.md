# Veda-Core Milestone 21 Results — Generic-Trap PCC-Reset Hardening (Sail)

**Date:** 2026-08-01
**Scope:** closes a real, empirically-confirmed functional-completeness bug found while writing `MILESTONE_20_RESULTS.md`'s own "Not yet built" section, then deliberately re-examined with fresh, careful architectural reasoning rather than accepted at face value: `veda_pcc_save_and_reset()` had exactly 3 real call sites (`veda_trap()`, `ext_handle_fetch_check_error`, `ext_handle_data_check_error`), all Veda-specific — an *ordinary*, non-Veda RISC-V exception taken from inside a live `OCInvoke` compartment never reset `veda_pcc_base`/`_length` at all.

## Re-deriving the real severity, not accepting the first framing

Milestone 20's own doc named this gap primarily as a *security/trap-state-integrity* concern (a compartment rewriting `mtvec` to reach a handler with stale state). Working through it more carefully before designing a fix, by tracing exactly what a compartment could and couldn't newly do:

- Any handler reached via a rewritten `mtvec` must itself be fetchable — and `ext_fetch_check_pc` applies unconditionally to every fetch (confirmed directly in `postlude/fetch.sail`: "assumes the external fetch checks are higher priority than the following alignment check"), including the handler's own first instruction. If `veda_pcc_length` is still narrowed, a handler placed **outside** the compartment's own bounds cannot be reached at all — it would immediately fetch-fault itself. So this gap does **not**, by itself, let a compartment jump to attacker-chosen code outside its own bounds; Milestone 14's fetch-check remains a robust backstop throughout.
- The actual, concrete, and far more certain consequence: **any realistic system-service handler — the normal, expected place for one, always outside whatever compartment happened to call it — becomes permanently unreachable from inside a compartment**, because reaching it requires exactly the fetch that the still-narrowed bounds block. This is not a security exploit; it is a basic functional break in the interaction between `OCInvoke` compartmentalization and the standard RISC-V trap/syscall mechanism.

**Empirically confirmed before designing any fix**, matching this project's own established discipline: a real PoC under `sail_riscv_sim` — a compartment narrowed to `Length=0x40`, `mtvec` pointed at a realistic handler placed outside it, an ordinary `ecall` executed from inside — hung indefinitely. Re-run bounded with `--inst-limit 200` to get safe, concrete evidence rather than a raw timeout: the program never completed within 200 instructions (the whole test is under 40 real instructions per pass), consistent with the hypothesized infinite loop — fetch-fault at the handler → redirect to `mtvec` (the same handler) → fetch-fault again, unboundedly.

## Design implemented

Rather than adding another special-cased hook enumerating one more trap type (the same piecemeal pattern that produced this gap — Milestones 14 and 19 each scoped their own hook narrowly to their own specific trigger, never intended to be exhaustive over every possible trap source), this fix targets the one real, universal chokepoint every trap already passes through regardless of source: **`handle_trap_extension`** (`exceptions/sys_exceptions.sail`) — a real, pre-existing, previously-unclaimed extension hook (confirmed via grep: called exactly once, unconditionally, from `sys/sys_control.sail`'s own `trap_handler()`, for every Machine-delegated exception *and* interrupt alike — the only real privilege-delegation path in this project's own test config, S/U-mode being disabled).

Its call site inside `trap_handler()` was confirmed by reading the function in full: it fires **after** `mepc`/`mcause`/`mtval` are already set, but **before** the trap-vector target is computed and control transfers there — so by the time the handler's own first instruction is fetched, `veda_pcc_length` has already been reset, closing the gap at its root rather than at each individual symptom.

`exceptions/sys_exceptions.sail`'s default body reduced to a forward `val` declaration (the identical split-declaration-and-move-body technique already established for `ext_fetch_check_pc`/`ext_data_get_addr` — confirmed the same module-ordering constraint applies: `Veda_insts` itself `requires exceptions`, so a Veda-referencing body could never live there). Real body added to `postlude/step_ext.sail`:

```sail
function handle_trap_extension(_p : Privilege, _pc : xlenbits, _ext : option(unit)) -> unit = {
  if veda_pcc_length != VEDA_PCC_UNBOUNDED then veda_pcc_save_and_reset()
}
```

Conditional, not unconditional — matching this milestone series' own established style — since the overwhelming majority of real traps in this project's own test corpus occur outside any compartment, and there is no reason to touch `veda_mepcc_base`/`_length` (whose stated purpose is specifically "the compartment bounds live at trap time") when no compartment was ever active.

**A real design property worth naming explicitly, not left implicit**: this fix does not force a compartment to be permanently "abandoned" after an ordinary trap the way a genuine PCC bounds violation is (Milestone 14's own established convention). Because `veda_mepcc_base`/`_length` are saved with the compartment's real original bounds before the reset, and because Milestone 20's own gate already permits writing `0x7C0`/`0x7C1` once `veda_pcc_length == VEDA_PCC_UNBOUNDED` (true immediately after this fix runs), a legitimate handler *can* explicitly restore the narrow bounds from the saved values and `mret` back into a still-compartmentalized continuation — a real, usable pattern for a future syscall-return implementation, consistent with this project's own already-stated "explicit software action, not automatic hardware" restoration philosophy (`MILESTONE_14_RESULTS.md`). This milestone does not build or test that restore-and-resume pattern itself — only that the handler can run at all — named honestly as a real, natural extension point for future OS/runtime work on top of Veda-Core, not built here.

## Test plan and result

**`vc_pcc_generic_trap_reset.S`** — the permanent regression test for the empirically-confirmed PoC: a real `OCInvoke` compartment (`Length=0x0040`) executes an ordinary `ecall`; `mtvec` points at a realistic handler placed outside the compartment. The handler's own successful execution is itself the primary proof (it is only fetchable at all if `veda_pcc_length` was already reset before that fetch); the load-bearing assertion inside it additionally confirms `mcause == 11` (`E_M_EnvCall`, verified against the real encoding in `core/types.sail` rather than assumed) and `veda_pcc_length == 0xFFFF` (`VEDA_PCC_UNBOUNDED`) directly, then explicitly advances `mepc` and `mret`s back into the compartment's own resuming flow, which completes normally.

`run_veda_selfcheck_tests.sh` — **41/41 passed** (40 pre-existing + 1 new), zero regressions on the first run.

## Not yet built

**RTL mirror** — deliberately not attempted this pass, matching this project's own established Sail-first sequencing; combined with Milestones 19 and 20's own still-pending RTL work as one named future RTL pass covering all three together.

**Interrupt-path coverage** — CLOSED, 2026-08-09, see `MILESTONE_21_TIMER_INTERRUPT_VERIFICATION_RESULTS.md`. `handle_interrupt` (`sys/sys_control.sail`) routes through the identical `trap_handler()` body this fix hooks into, and was reasoned to be covered by the same real mechanism, but was **not verified by a real test** at the time this section was originally written -- no real interrupt source had ever been fired in this project's own test config. A real, genuine timer interrupt (via the base Sail model's own already-existing, spec-compliant CLINT/mtime/mtimecmp/mie/mip machinery -- not new Veda-side hardware) now confirms `handle_trap_extension` fires correctly for an asynchronous interrupt landing inside a live `OCInvoke` compartment, verified positively (`vc_timer_intr_pcc_reset` passes) and via mutation test (skipping the hook for interrupts flips the same test to a real `FAILURE`, confirming non-vacuity).

**The restore-and-resume-inside-compartment pattern** (this doc's own "real design property" section above) — a real, usable extension this fix enables but does not itself build or test. A natural candidate for a future milestone once real OS/runtime work on top of Veda-Core needs it.
