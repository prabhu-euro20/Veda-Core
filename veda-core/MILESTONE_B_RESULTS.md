# Veda-Core Minimal OS Kernel Milestone B Results — the Reserved-Otype Sentry Mechanism

**Date:** 2026-08-05
**Scope:** the real, cheap, cross-compartment-boundary-crossing primitive Milestone A's own
`MINIMAL_OS_KERNEL_DESIGN.md` (Finding 2) deferred as "Milestone B" — real CHERI's reserved-otype
"sentry" mechanism, term-for-term adapted for Veda-Core, plus a new instruction (`OCRETURN`) that
composes it with Veda-Core's own already-built PCC-bounding architecture. Fully implemented and
verified on the Sail side; RTL mirror explicitly deferred, per this project's unbroken
Sail-then-RTL sequencing.

## The central finding this pass surfaced, before any code was written

A rigorous, complete re-read of the CHERI ISA spec's own `CSeal`/`CSealEntry`/`CJAL`/`CJALR`
instruction-reference pages (pp.198–203, 214–215) plus Veda-Core's own current
`VEDA_CSEAL`/`VEDA_CUNSEAL`/`VEDA_OCJALR` Sail code, cross-checked independently by a Plan agent,
surfaced a real correction to Milestone A's own Finding 2: **`veda_pcc_base`/`veda_pcc_length` —
the compartment-bounding window Milestone 14 built and Milestone 22 proved `OCJALR` cannot
escape — is narrowed exclusively by `OCInvoke`**, the only site in the entire Veda instruction set
that writes those registers. PCC narrowing and jump-target verification are two independent
operations that merely happen to be co-located inside `OCInvoke`. A bare "teach `OCJALR` to accept
a sentry" extension would therefore be architecturally inert for the actual goal: it would still
leave the compartment window unchanged, so a cheap verified jump would only ever land successfully
*inside* the caller's current window (checked unconditionally on the very next instruction fetch
by `ext_fetch_check_pc`, regardless of which instruction produced the new PC). A real cross-
compartment cheap exit required a **new** instruction that verifies a sentry **and** narrows PCC —
not an `OCJALR` extension. The full design reasoning, findings, and citations are recorded in the
approved plan and reproduced in `MINIMAL_OS_KERNEL_DESIGN.md`'s own companion sections.

## What was built (Sail side)

**`veda_types.sail`**: `VEDA_OTYPE_SENTRY : bits(16) = 0xFFFE`, the exact proportional analog of
real CHERI's `2^XLEN-2`, sitting immediately below the existing `UNSEALED_OTYPE = 0xFFFF`.

**`veda_cap_insts.sail`**, three changes:

1. **`VEDA_CSEAL` hardened**: `& (cs2.Offset != VEDA_OTYPE_SENTRY)` added to its authorization,
   alongside the existing `!= UNSEALED_OTYPE` exclusion — the load-bearing security property,
   mirroring real `CSeal`'s own `cursor <= cap_max_otype` bound. Verified this is the only place
   needing the change: `VEDA_CUNSEAL`'s own check (`cs2.Offset == cs1.otype`) already reduces to
   the same forgery point, and no other instruction writes `otype` from software-chosen data.
2. **New `VEDA_CSEALENTRY(cd, cs1)`** (funct7 `0010101`): term-for-term real `CSealEntry` — `cd =
   cs1` sealed with the fixed `VEDA_OTYPE_SENTRY` constant, no authorizing capability operand,
   `Perms` (including `Permit_Execute`) carried through unchanged.
3. **New `VEDA_OCRETURN(cs1)`** (funct7 `0010110`), deliberately a new opcode rather than a branch
   folded into `OCJALR` (fixed encoding-field semantics; this codebase's own convention already
   gives each distinct security-relevant behavior its own `funct7` — `OCJALR` itself is completely
   unmodified, a direct, load-bearing preservation of RTL Milestone 22's "OCJALR cannot cross a
   compartment boundary" finding). Checks — reusing `OCJALR`'s own three checks and cause codes
   exactly — tag (`0x02`), `isSealedCap(cs1) & cs1.otype == VEDA_OTYPE_SENTRY` (`0x03`, no second
   operand to "mismatch" against, so "not a valid sentry" reuses the seal-validity cause class),
   and `Permit_Execute` (`0x11`); `Permit_Invoke` deliberately not checked, matching real CHERI's
   own sentry/`CJALR` mechanism. On success: `veda_pcc_base := cs1.Base; veda_pcc_length :=
   cs1.Length` (mirroring `OCInvoke`'s own identical assignment, in the same narrow-then-jump
   order), then jumps to `cs1.Base + cs1.Offset`. `IDC`/`c15` is left untouched — matches real
   `CJALR` never touching `IDC` (only `CInvoke` does).

**Security property, stated explicitly**: `OCRETURN`'s guarantee is identical in kind to
`OCInvoke`'s — bounded by whatever capability the caller already legitimately possesses (valid
tag, genuine `Permit_Execute`, and an otype only ever produced by minting, never by forgery) — it
is a cheaper mechanism for exercising pre-existing authority, not a new source of authority. Any
compartment can mint its own sentries via `CSealEntry` with no special permission (matching real
CHERI exactly), but a sentry only lets its holder cheaply jump to a target it could already reach
through a capability it genuinely held.

**Build**: `sail_riscv_sim` rebuilt clean after one real, caught-before-shipping bug — an
off-by-one bit-width error in `VEDA_CSEALENTRY`'s/`VEDA_OCRETURN`'s encoding (an unused 5-bit
register-field hardcode accidentally written as `0b0 @ 0b00000` = 6 bits instead of `0b00000` = 5
bits, producing a 33-bit instead of 32-bit total pattern) — caught immediately by Sail's own type
checker (`Vector concatenation pattern does not have the correct width. Expected width 32, found
33`) before any test was run, fixed, rebuilt clean.

## Tests and results

Eight new `sail_tests/vc_*.S` files, modeled on the closest existing analogues
(`vc_cseal.S`/`vc_cseal_unauth_neg.S`/`vc_ocjalr.S`/`vc_ocjalr_neg.S`/
`vc_ocjalr_compartment_boundary_neg.S`/`vc_switcher_register_clear.S`):

| Test | Proves |
|---|---|
| `vc_cseal_entry` | `CSealEntry` mints a tagged, `otype=0xFFFE` sentry from an arbitrary executable capability |
| `vc_ocreturn_basic` | A sentry minted before entry, used via `OCRETURN` from inside a narrow compartment, genuinely lands at its target **and** `veda_pcc_base`/`veda_pcc_length` read back as the sentry's own `Base`/`Length` — direct proof of a real compartment-boundary crossing |
| `vc_switcher_register_clear_fast_return` | End-to-end integration: the Milestone A switcher pattern with its return leg replaced by `OCRETURN`, chained twice (target→switcher, switcher→unbounded) — proves the mechanism composes into a real multi-hop call chain, and that a minimal, self-contained trampoline (2 instructions) is sufficient |
| `vc_cseal_sentry_forge_neg` | The single most important negative test: an authority capability walked to `Offset=0xFFFE` via `OCA` and used with ordinary `CSeal` soft-fails (`Tag==0`) — the hardened exclusion genuinely blocks forgery |
| `vc_ocreturn_untagged_neg` | `OCRETURN` through an untagged capability traps `TAG_VIOLATION` (`mtval=0xA2`) |
| `vc_ocreturn_wrong_otype_neg` | `OCRETURN` through an ordinary-`CSeal`-sealed, non-sentry capability traps `SEAL_VIOLATION` (`mtval=0xA3`) |
| `vc_ocreturn_no_execute_neg` | A sentry minted from a non-executable capability (`CSealEntry` carries `Perms` through unchanged) traps `PERM_EXECUTE_VIOLATION` at `OCRETURN` (`mtval=0xD1`) |
| `vc_ocreturn_via_ocjalr_neg` | A genuine sentry attempted through the *old* `OCJALR` path still traps `TYPE_VIOLATION` (`mtval=0xC4`) — the two mechanisms don't accidentally interoperate |

`vc_ocjalr_compartment_boundary_neg.S` (Milestone 22's own regression proof) reran unmodified as
part of the same full suite and still passes — direct, non-regression confirmation that `OCJALR`'s
own "cannot cross a compartment boundary" property is untouched by this milestone.

```
$ bash run_veda_selfcheck_tests.sh
...
PASS      vc_cseal_entry
PASS      vc_cseal_sentry_forge_neg
PASS      vc_ocjalr_compartment_boundary_neg
PASS      vc_ocreturn_basic
PASS      vc_ocreturn_no_execute_neg
PASS      vc_ocreturn_untagged_neg
PASS      vc_ocreturn_via_ocjalr_neg
PASS      vc_ocreturn_wrong_otype_neg
PASS      vc_switcher_register_clear_fast_return
...
---
52/52 passed
```

All 44 pre-existing tests pass unchanged (zero regressions), all 8 new tests passed on the first
run.

## Not yet built

**RTL mirror** — explicit, separate follow-on, per this project's own unbroken Sail-then-RTL
sequencing; not started this pass.

**A real scheduler/allocator compartment using this mechanism in production** — this milestone
builds and proves the sentry *primitives* (`CSealEntry`/`OCRETURN`) and one composed, multi-hop
integration test; a real minimal-OS scheduler compartment that mints trusted-stack-anchored
sentries as part of actual thread dispatch is the next, not-yet-started layer on top.

**`vc_switcher_register_clear.S` itself** — deliberately left unmodified, a permanent regression
proof that the original, symmetric double-`OCInvoke` switcher path (Milestone A) still works
unchanged alongside the new, cheaper alternative.
