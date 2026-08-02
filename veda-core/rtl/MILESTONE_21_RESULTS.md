# Veda-Core RTL Milestone 21 Results: Generic-Trap PCC-Reset Hardening — Audited, Not Yet Applicable

**Date:** 2026-08-02
**Scope:** the intended RTL mirror of the Sail-side Milestone 21
(`veda-core/MILESTONE_21_RESULTS.md`), which closed a real
functional-completeness bug: an *ordinary*, non-Veda RISC-V exception
(`ecall`, illegal-instruction, misaligned-access) taken from inside a
live `OCInvoke` compartment never reset `veda_pcc_base`/`_length`,
because Sail's own generic `handle_trap_extension` chokepoint had no
Veda-aware body wired into it. This document is the result of a
genuine attempt to mirror that fix, not a code change — the real
finding, confirmed by direct inspection rather than assumed, is that
**the vulnerability class this milestone closes does not currently
exist in RTL, because RTL has no generic (non-Veda) exception-taking
mechanism at all.**

## Real investigation, before writing any code

Grepped `veda_core.tlv` for every real RISC-V exception source Sail's
own fix targets:

```
grep -n 'ecall\|is_ecall\|E_M_EnvCall\|illegal.*instr\|misaligned' veda_core.tlv
```

Zero matches beyond this document's own comment. Confirmed directly:
RTL decodes no `ECALL` encoding, has no general "this opcode/funct
combination is unrecognized" illegal-instruction trap, and performs no
alignment check on any load/store address. A genuinely unrecognized
instruction word simply matches none of the `$op_is_*`/`$is_veda_*`
predicates and is silently treated as a no-op (no `$reg_write`, no
memory write, PC just advances) -- not trapped at all, in either
direction, today.

Traced every real write to `$mcause`/`$mepc`/`$mtval` and the trap-side
half of `$pc_src`/`$alt_pc` (the only signals that can redirect
control flow to a trap handler) to confirm there is exactly **one**
real chokepoint, not several:

```
$pc_src = $veda_trap_taken || $is_mret || ... ;
$alt_pc[63:0] = $veda_trap_taken ? $mtvec : $is_mret ? $mepc : ... ;
$mcause[63:0] = ... (>>1$veda_trap_taken) ? (...) : >>1$mcause;
$mepc[63:0]   = ... (>>1$veda_trap_taken) ? >>1$pc : (...) ;
$mtval[63:0]  = ... (>>1$veda_trap_taken) ? (...) : >>1$mtval;
```

`$veda_trap_taken` is the single, unconditional OR-chain every real
trap in this file -- OCL/OCS/OCL.C/OCS.C/NMC_ADD/Atomic/OCInvoke/
OCJALR/plain-Bind/PCC-fetch/purecap (Milestone 19)/CSR-self-escape
(Milestone 20) -- already flows through, and it is the identical
signal `$veda_pcc_base`/`$veda_pcc_length`/`$veda_mepcc_base`/
`$veda_mepcc_length`'s own save-and-reset branches already key on
(`(>>1$veda_trap_taken) ? <reset/save value> : ...`, their own
*highest-priority* branch, confirmed in Milestones 19 and 20's own
implementation work this same pass). There is no second, parallel
trap path anywhere in this file that could bypass this reset the way
Sail's own generic `trap_handler()` (a structurally separate function
from the Veda-specific hooks) could.

## Conclusion

**RTL is closed-by-construction against this exact gap, for every
trap type that exists today** -- not because a dedicated Milestone 21
-style hook was added, but because RTL's own trap architecture never
had Sail's structural split (Veda-specific hooks vs. a separate,
generic `trap_handler()`) that made the original gap possible in the
first place. Every real RTL trap already goes through the one real
save-and-reset chokepoint.

**This is not the same as "no RTL work is needed."** It means the real
risk has shifted from "fix an existing gap" to "prevent a future one
from being reintroduced": if and when a future milestone adds `ecall`,
general illegal-instruction detection, or misaligned-access trapping
to RTL (plausible, real future work -- e.g. as part of the OS-kernel
initiative this security-audit series is itself sequenced ahead of),
that work **must** wire its own new violation signal into the existing
`$veda_trap_taken` OR-chain -- the same pattern already used three
times this pass (Milestones 19's purecap violation, 20's CSR-escape
violation, and every prior milestone's own family) -- rather than
inventing a second, parallel, disconnected trap/PC-redirect mechanism.
Doing so would automatically and correctly get PCC-reset for free, by
construction, exactly as every existing family already does. Doing the
opposite -- adding a second redirect path outside `$veda_trap_taken` --
would silently reintroduce the identical class of bug Sail's own
Milestone 21 found and fixed. **This warning is the real, concrete
deliverable of this pass**, not a placeholder.

## Verification

No RTL source change was made (there is nothing to change -- see
above), so no new test is needed and none was added.
`run_veda_smoke_test.sh` (33/33) and `run_act4_tests.sh` (51/51),
both already re-confirmed as part of Milestone 20's own verification
earlier this same pass, remain the current, accurate baseline.

## What remains open, honestly

- Real `ecall`/illegal-instruction/misaligned-access support does not
  exist in RTL at all -- a genuine, much larger, separate future
  initiative (not scoped or attempted here), relevant groundwork for
  any future OS/runtime work on top of Veda-Core, which will need real
  syscall entry and will then need to follow this document's own
  explicit warning above when it's built.
- Interrupt-path coverage: Sail's own Milestone 21 named this
  unverified (no real interrupt source in either layer's test
  config). RTL has no interrupt/CLINT/timer wiring at all (confirmed
  in earlier project research), so the same honest "unverified, not
  silently assumed safe" status applies here too, unchanged.
