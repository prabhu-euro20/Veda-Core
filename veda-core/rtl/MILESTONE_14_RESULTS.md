# Veda-Core RTL Milestone 14 Results — PCC Compartment Bounding

**Date:** 2026-07-26
**Scope:** the RTL mirror of `veda-core/MILESTONE_14_RESULTS.md` (Sail) / `PCC_COMPARTMENT_DESIGN.md` — bounding execution inside an `OCInvoke`-entered compartment, now real in RTL too.

## The one genuinely new kind of check this milestone required, and how it was kept minimal

Every prior check in `veda_core.tlv` is gated on a specific *decoded* opcode — it only ever runs when `$is_veda_ocl`/`$is_veda_bind`/etc. is true. A PCC bounds check is different in kind: it must run **every cycle, unconditionally**, against whatever `$pc` the core is about to fetch from, regardless of what instruction (if any) turns out to live there. This raised a real correctness question before any RTL was written: if `$pc` is out of bounds, the fetched `$instr` bits are arbitrary — decoding and executing them as if legitimate (as every other violation-suppression path in this file only ever partially prevents, one write-family at a time) risked real, uncontained side effects from garbage bytes.

**Resolution**: rather than auditing and individually gating every GPR/capability-register/memory write path in this ~2600-line file, `$instr` itself is forced to a real, standard NOP (`0x00000013`, `ADDI x0,x0,0`) whenever `$veda_pcc_violation` is true, computed once, right where `$instr` is assembled from `$instr_rom`/`$instr_elf`. A NOP decodes as nothing Veda-specific and its only GPR target is `x0` (hardwired to discard writes, the same real RISC-V convention already governing every other instruction in this core) — so every downstream write path in the file is automatically, correctly inert on a violating cycle, with one targeted change instead of many. The real trap itself (`mcause`/`mepc`/`mtval`/PC-redirect) is delivered entirely independently, through the same `$veda_trap_taken` family every other Veda-Core hard-trap already uses.

## Two real bugs found by actually running the tests, not assumed safe from the design alone

1. **A real, second instance of the exact Object_ID-collision class Milestone 13 already taught this project to watch for.** The first draft of `veda_smoke_m14_neg.S` minted its compartment fixture at Object_ID 60/61/62 — but Object_ID=60 is Milestone 12's own reset-seeded, pre-owned (`owner_hart=0x63`) fixture, and `ODT-Populate` never touches the `owner_hart` byte (only Milestone 12's own owner-claim logic, tied to `Bind`, does). The result was a real, observed hard-trap at the very first `Bind` (`cause=0x06`, Owner Violation) instead of the intended PCC-bounds trap — caught via a real cycle-by-cycle debug trace, not assumed. **Fixed** by re-grepping the full RTL test corpus's own `Object_ID` usage (including Milestone 12/13's own added fixtures, 60 and 70) and moving to 80/81/82, confirmed genuinely unused.
2. **Both new testbenches' own cycle budgets were real, plain underestimates.** `tb_veda_smoke_m14.sv` (55 cycles) never reached the second `OCInvoke` at all; `tb_veda_smoke_m14_neg.sv` (55 cycles) correctly triggered and delivered the real trap (confirmed via the same debug trace — `mcause=0x18`/`mtval=0x201`/`mepc` all exactly correct on the first real attempt) but ran out of budget partway through the handler's own multi-CSR verification sequence. **Fixed** by widening both budgets (75 and 90 cycles respectively) after directly observing, via the debug trace, how many real cycles each test actually needs — not by guessing a larger round number.

Both are process/test-authoring lessons, not RTL logic bugs — the underlying trap mechanism itself (bounds check, `mcause`/`mtval`/`mepc` capture, save-into-`mepcc`, `MRET`-redirect) worked correctly on the very first real simulation once the test programs themselves were correct.

## Implementation, mirroring the Sail design field-for-field

- `$veda_pcc_base[31:0]`/`$veda_pcc_length[15:0]` (live compartment) and `$veda_mepcc_base[31:0]`/`$veda_mepcc_length[15:0]` (saved copy across a trap) — new persistent signals, the same real idiom `$mtvec`/`$mepc` already established (Milestone 9). Reset to `VEDA_PCC_UNBOUNDED` (`16'hFFFF`) — a real correctness requirement (not styling): left at the SystemVerilog default of 0, the very first fetch would bounds-check against an empty window at address 0 and hard-trap on cycle one.
- Four new CSRs at `0x7C0`-`0x7C3` (the real RISC-V-spec "Machine-level Custom read/write" range, identical addresses already chosen and verified on the Sail side), wired into the existing Milestone 9 `$csr_addr`/`$csr_rdata`/`$csr_write_en` mechanism with zero new instruction decode.
- `OCInvoke`'s own existing RTL success path gains one real side effect: `$veda_pcc_base`/`$veda_pcc_length` narrow to `$veda_rs1cap_base`/`$veda_rs1cap_length` (`cs1`'s own fields, already computed and shared with `OCL`/`OCS`), the identical mechanism the Sail side uses.
- `$veda_pcc_violation` joins the existing `$veda_trap_taken` family. Its own `cap_idx`/`cause` contribution is built directly into `$mtval`'s own construction (`cap_idx=5'b10000`/`cause=5'b00001`) rather than routed through `$veda_trap_cap_idx[3:0]` (only 4 bits wide — cannot carry the 5-bit sentinel value 16 without widening every existing call site) — the identical "built inline, not through the typed interface" choice already made on the Sail side.
- Save-and-reset on any trap, explicit software-driven restore before `MRET` (via the four new CSRs) — the identical real design and reasoning as the Sail side (`MILESTONE_14_RESULTS.md`).

## Result

Both new RTL tests (`veda_smoke_m14`/`veda_smoke_m14_neg`) passed after the two fixes above — `veda_smoke_m14` proves the real unbounded→narrow→unbounded round trip via the live CSRs; `veda_smoke_m14_neg` proves the genuine hard-trap on a real compartment-escape attempt, correct `mcause`/`mtval`/`mepc`/`mepcc` capture, and the full explicit-restore-and-recover cycle across a real `MRET`.

## Full regression: zero net impact after the two understood, fixed issues above

`run_veda_smoke_test.sh` — **25/25 passed** (23 prior tests + `veda_smoke_m14`/`veda_smoke_m14_neg`), zero regressions, including the base RV64I core's own unmodified 81-instruction smoke test and every pre-existing `OCInvoke` test (Milestone 10's own fixture needed no adjustment here, unlike the Sail side's `vc_ocinvoke.S` — RTL's own `landing_pad` code is short enough to fit inside its existing `Length=0x40` fixture without modification, confirmed by the regression, not assumed).

## Not yet built

`Perms`-on-`PCC`, real physical multi-hart RTL, and `OSpecialRW`'s own privilege-only gating all remain exactly as named in prior milestones' own "Not yet built" sections — none touched or affected by this milestone. With this milestone, Veda-Core's own PCC-equivalent compartment bounding is real and verified in both Sail and RTL.
