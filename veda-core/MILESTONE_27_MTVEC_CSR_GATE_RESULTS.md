# mtvec Compartment-Escape Fix (Sail)

**Date:** 2026-08-10
**Scope:** closes a real, empirically-confirmed privilege-escalation vulnerability -- a bounded `OCInvoke` compartment could rewrite `mtvec` (the standard RISC-V trap-vector CSR) with zero gating, then trigger any ordinary trap, and have attacker-chosen code execute with fully unbounded PCC. Found while explaining `MILESTONE_21_PCC_AUTO_RESTORE_RESULTS.md`'s own mechanism to the user, not from a dedicated audit pass -- traced from first principles, then empirically confirmed with a live PoC before any fix was designed, matching this project's own standing discipline.

## How this was found

`MILESTONE_20_RESULTS.md` (2026-08-01) already discovered and documented that `mtvec` has zero compartment-aware gating, and reproduced a compartment rewriting it with a plain `csrw`, zero trap. At the time that doc judged the gap **not independently exploitable**, reasoning that an *ordinary* trap left `veda_pcc_length` narrowed across the trap, so a handler placed outside the compartment's own bounds would immediately fetch-fault itself -- quoting that doc directly: *"this gap does not, by itself, let a compartment jump to attacker-chosen code outside its own bounds; Milestone 14's fetch-check remains a robust backstop throughout."*

`MILESTONE_21_RESULTS.md` (2026-08-01, later the same day) then shipped `handle_trap_extension` -- universal PCC-reset-on-any-trap, for good, independent functional reasons (making any real system handler reachable at all after an ordinary trap; without it, a realistic handler placed outside a compartment was permanently unreachable, verified via a real infinite-fault-loop PoC at the time). Its own opening paragraph reused Milestone 20's exact reasoning to argue the *fetch-check-as-backstop* premise still held -- but that premise is conditional on live PCC staying narrowed at the moment the redirected handler is fetched, and Milestone 21's own fix is precisely to make that no longer true, for every trap, unconditionally.

Nobody went back and re-examined the `mtvec` gap once Milestone 21 shipped. The two independently-true, independently-documented facts compose into a real escape: `handle_trap_extension` now resets PCC to unbounded *before* `prepare_trap_vector` computes and fetches the trap-vector target (confirmed directly in `sys/sys_control.sail`'s `trap_handler`: `handle_trap_extension(...)` at line 221/247, `prepare_trap_vector(...)` afterward) -- so a handler reached via an attacker-redirected `mtvec` is now fetchable regardless of where it lives, with unbounded PCC once it runs.

## Empirical confirmation (before any fix existed)

`sail_tests/vc_pcc_mtvec_escape_neg.S`: a compartment (`Length=0x40`) rewrites `mtvec` to point at `evil_target`, an address outside its own bounds, then executes a plain `ecall`. Traced with `--trace-instr --trace-exception --use-abi-names` against the unfixed model:

```
[41] csrrw zero, mtvec, t3   landing_pad+8    <- succeeds, ZERO trap
[42] ecall                   landing_pad+12
[43] lui s7, 0xe             evil_target+0    <- fetched from OUTSIDE [landing_pad, landing_pad+0x40), no fetch fault
[45] s7 = 0xE5CA (ESCAPED marker)
```

`evil_target`'s own instructions fetch and execute successfully despite living outside the compartment's bounds -- direct, unambiguous proof PCC was already unbounded at fetch time, exactly as hypothesized. Test result: `FAILURE` (the test asserts the secure outcome as PASS; pre-fix, that assertion is violated -- the correct, expected result to see before a fix exists).

## Research (official documents only, read in full, not fragments)

Two parallel research passes before any implementation, using this project's own local, canonical copies -- not remembered/assumed text:

**Base mechanism** (`toolchain/sail-riscv/model/`, read directly): `write_CSR(0x305, value)` lives in `exceptions/sys_exceptions.sail:141`, delegating to `set_mtvec`/`legalize_tvec` (`core/sys_regs.sail:499-528`). `legalize_tvec` only legalizes `Mode`/`Base`-alignment -- **no privilege check anywhere in the mtvec write path**. `is_CSR_accessible(0x305,_,_) = true` (`sys_exceptions.sail:131`) unconditionally, ignoring the `Privilege` argument entirely. The only gate applied is the generic, address-encoded M-mode requirement (`check_CSR_priv`, from `csr[9:8]`) that every M-mode CSR gets uniformly -- nothing mtvec-specific.

**Established gating idiom in this exact codebase**: this checkout already implements Smstateen (`model/extensions/Stateen/`, 377 lines, read in full). Its `stateen_allows_CSR_access(csr, priv, access_type)` is a dedicated, independent hook -- **not** folded into `is_CSR_accessible` -- ANDed as its own conjunct directly in `check_CSR` (`sys/sys_control.sail:54-58`). Its own header comment states why: folding it into each CSR's own `is_CSR_accessible` clause would create a circular module dependency between Core and Stateen, so it's centralized as a separate hook instead. A second real precedent (`satp` gated on `mstatus[TVM]`, `sys/vmem.sail:219-233`) shows the simpler "just add an `is_CSR_accessible` clause" idiom is used **only** when the condition doesn't cross that same module boundary.

For this fix, `is_CSR_accessible(0x305,_,_)` already has exactly one clause, defined in the base file `sys_exceptions.sail` -- Sail's scattered-function mechanism does not allow a second clause for the same literal CSR address elsewhere, so a Veda-side `is_CSR_accessible`/`write_CSR` clause for `0x305` was never an option (unlike the previously-unclaimed `0x7C0-0x7C5` range Milestone 20 gated directly). Editing the existing base-file clause to reference `veda_pcc_length` would put Veda-specific state into a base-model file -- the exact circular-dependency problem Stateen's own comment names as its reason for existing as a separate hook. **The Stateen pattern is therefore not just a nicer option here, but the only one that fits both Sail's constraints and this project's own established "build only in extensions/Veda/" boundary.**

**Official RISC-V Privileged spec** (`specs/riscv-spec.pdf`, Section 3.1.7, read in full, verbatim): mtvec is `MRW` (Machine read/write), WARL, and explicitly *may be implementation-defined read-only* -- the ratified text names no further conditional-write mechanism for mtvec itself.

**Official CHERI-RISC-V spec** (`specs/cheri-architecture.pdf`, Section 4.3.5/4.3.6/Table 4.3, read in full, verbatim): CSR/SCR access is whitelist-gated by a single capability permission, `PCC.perms.PERMIT_ACCESS_SYSTEM_REGISTERS` ("ASR"). Table 4.3 lists MTCC ("extends mtvec") with Access = `ASR` (not `ASR*`) -- meaning real CHERI gates **both reads and writes** of mtvec/MTCC on this permission. A missing-permission access raises a precise capability exception, RISC-V-level cause `0x1C`, with the specific reason (`0x18`, `PERMIT_ACCESS_SYSTEM_REGISTERS Violation`) recorded in `xtval`, at Priority 1 (highest) among capability exceptions.

## Design decision and why

New function `veda_allows_CSR_access(csr, priv, access_type)` in `extensions/Veda/veda_regs.sail`, mirroring `stateen_allows_CSR_access`'s exact shape, matched only against `csr`:

```sail
function veda_allows_CSR_access(csr : csreg, priv : Privilege, access_type : CSRAccessType) -> bool =
  match csr {
    0x305 => (access_type == CSRRead) | (veda_pcc_length == VEDA_PCC_UNBOUNDED),
    _     => true,
  }
```

ANDed into `check_CSR` (`sys/sys_control.sail:54-58`) as a new conjunct, alongside `stateen_allows_CSR_access` -- identical wiring pattern, same call site. A forward `val` declaration lives in `exceptions/sys_exceptions.sail` (the same file already hosting `handle_trap_extension`'s and `veda_pcc_restore_on_xret`'s own forward declarations, for the identical module-visibility reason: `sys_control.sail` doesn't itself require `Veda`).

**Deliberate divergence from the CHERI precedent, stated explicitly rather than silently copied:** real CHERI gates both reads and writes of mtvec/MTCC. This fix gates **writes only**. Reasoning: this project's own already-established, twice-applied principle (Milestone 20's `veda_pcc_*`/`veda_mode` CSRs, and the capability query-family instructions before them) is that capability/control *metadata* is always inspectable -- only *mutation* is restricted, because reading it back grants no new capability a compartment doesn't already have from its own bounds. Reading `mtvec` tells a compartment where the current handler lives, which is not by itself exploitable once the write path (the actual escape vector) is closed. Diverging from official precedent here is a considered choice consistent with this project's own stated design philosophy, not an oversight -- named explicitly per this project's own "if you make a decision, say why" discipline.

## Verification

**PoC re-run against the fix**, traced: the compartment's own `csrw mtvec, t3` (instruction 41) now hard-traps immediately (`Illegal_Instruction`, `mcause=2`), redirecting to the *legitimate*, original `trap_handler` -- `evil_target` is never reached. `SUCCESS`.

**Full regression**: `run_veda_selfcheck_tests.sh` -- **62/62 passed** (61 pre-existing + 1 new), zero regressions on the first run. No pre-existing test writes `mtvec` from inside a live compartment, so nothing needed migration this time (unlike Milestone 21's own auto-restore fix, which broke three pre-existing tests).

**Mutation test**: temporarily replaced the new conjunct in `check_CSR` with a bare `true`, rebuilt, re-ran the PoC in isolation -- **`vc_pcc_mtvec_escape_neg` correctly flipped to a real `FAILURE`** (non-vacuous: the escape genuinely succeeds again without the gate). Reverted, rebuilt, re-ran the full suite -- back to **62/62**.

## Files changed

`toolchain/sail-riscv` (Sail fork): `model/extensions/Veda/veda_regs.sail` (+`veda_allows_CSR_access`), `model/exceptions/sys_exceptions.sail` (+forward `val`), `model/sys/sys_control.sail` (+1 conjunct in `check_CSR`). `veda-core`: new `sail_tests/vc_pcc_mtvec_escape_neg.S`, this results doc.

## Not yet built

**RTL mirror** -- deliberately not attempted this pass, matching this project's established Sail-first sequencing. RTL's own `veda_core.tlv` has never mirrored Milestone 20's CSR-gating either yet, so this exact same class of gap (any CSR write ungated by compartment state) likely exists there too -- a named, combined future RTL pass (Milestones 20+21+this fix together), not scoped here.

**Read-side gating** -- deliberately scoped out, see "Design decision and why" above; a considered choice, not an oversight.

**Not committed or pushed yet**, matching this session's established pattern.
