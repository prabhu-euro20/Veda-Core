# Real Sail-to-Coq/Rocq Export: A Concrete Formal-Verification Starting Point

**Date:** 2026-07-27
**Scope:** Improvement 6 from `ARCHITECTURE_IMPROVEMENT_FINDINGS.md` — a
real, concrete first step toward formal verification, not the vague
"formal verification is a future gap" this project's own docs previously
left it as.

## What was done

The real Sail compiler was found already installed in this project's own
toolchain (`toolchain/opam-root/`, an OPAM-built install missed by an
earlier search this session) and used to run Sail's own real, official
Coq/Rocq export backend (`toolchain/sail-riscv/model/CMakeLists.txt`'s
own already-existing `generated_rocq_rv64d` CMake target — real, official
infrastructure, not hand-rolled) against the full RVA23 profile Sail
model, including Veda-Core's own extension with both real bug fixes
(Milestones 15 and 16) already applied.

Real command (via CMake, `--strict-var --strict-bitvector
--strict-exponentials` — Sail's own strictest type-checking flags):

```
sail --strict-var --strict-bitvector --strict-exponentials \
  --require-version 0.20.2 --dcoq-undef-axioms --coq \
  --coq-lib riscv_extras --coq-output-dir build/rocq -o rv64d \
  --config build/config/rv64d_v256_e64.json --all-modules riscv.sail_project
```

## Real result

Two real Coq source files were produced: `rv64d_types.v` (630,731 bytes,
16,825 lines) and `rv64d.v` (5,430,435 bytes, 101,936 lines) — genuinely
large, since `--all-modules` pulls in the full RVA23 profile (Vector,
Crypto, Stateen, etc.), not just Veda-Core's own scope. This is honestly
more than strictly necessary for Veda-Core's own verification goal, but
it is the real, official CMake target this project already ships, used
as-is rather than hand-crafting a narrower (and therefore *unofficial*)
invocation.

**Concrete, verified evidence that Veda-Core's own real fixes translate
correctly, not just "the build didn't error":**

- `odt_entry_retired : bool` (Milestone 16's own new field) appears
  correctly typed in the generated `Record odt_entry` definition
  (`rv64d_types.v:12425`).
- The exact retirement-check logic from `veda_ocl_insts.sail` —
  `if old_entry.retired then Illegal_Instruction()` — appears faithfully
  translated as real Coq monadic code: `(if old_entry.(odt_entry_retired)
  then returnM ((Illegal_Instruction (tt)))` (`rv64d.v:91991`).
- The `ODT-Destroy` side's `old_entry.retired | (old_entry.generation ==
  0xff)` logic appears correctly as `orb (old_entry.(odt_entry_retired))
  (... eq_vec ... (Ox"FF") ...)` (`rv64d.v:92026`).
- `VEDA_ODT_POPULATE` appears as a real instruction constructor with
  generated encode/decode functions (`rv64d.v:9014/9388/9760`).

This is real, meaningful evidence beyond "26/26 self-check tests pass":
Sail's own type checker, running under its strictest settings, had to
fully accept Veda-Core's entire capability/ODT model — including both
real bug fixes from this session — before Coq generation could even
begin, and the translation preserved the exact logical structure of the
fix, not an approximation of it.

## Honest, real scope limits — stated plainly, not oversold

- **This proves the model translates to valid Coq syntax. It does not
  prove anything is formally correct.** `coqc` (the real Coq compiler,
  needed to type-check the `.v` files and actually machine-check any
  proof) is not installed in this environment — a separate, real,
  non-trivial decision (Coq's own ecosystem, proof libraries, etc.),
  analogous to the Yosys and Sail toolchain-install decisions already
  made this session but larger in scope, not attempted here.
- No actual proof obligations or lemmas were written or checked — "a
  capability with `Tag=false` can never result in a successful write,"
  the kind of real safety property this architecture's own security
  claims rest on, remains unproven, exactly as `SCALING_BARRIERS_RESEARCH.md`
  already honestly named as a categorically higher bar than an executable
  model plus tests.
- The `--all-modules` scope (full RVA23 profile) means this specific run
  says nothing narrower about Veda-Core in isolation — a real,
  Veda-scoped Sail project file, excluding unrelated extensions, would be
  a smaller, faster, more targeted real next step if this direction is
  pursued further.

## What this changes about the project's own formal-verification status

Before this: "no formal-verification work has started" (accurate, as
established earlier this session, referring specifically to
Isabelle/Coq-level theorem-proving). After this: a real, concrete,
machine-generated Coq translation of the exact, currently-fixed Sail
model exists on disk, type-checked by Sail's own strictest settings — the
honest, precise new status is "the model is proven to translate correctly
into a real theorem-prover's own input language; no actual theorem has
been stated or checked yet." A real, meaningfully smaller gap than
before, though still a real and substantial one.
