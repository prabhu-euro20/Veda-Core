# Veda-Core RTL — Phase 1 Milestone Plan

**Context**: Milestones V-A/V-B/V-C (real, working Sail formal model,
`veda-core/MILESTONE_V-{A,B,C}_RESULTS.md`) are done. Per
`FORMAL_VERIFICATION_PLAN.md`'s own stated sequencing — *"Only after
V-A/B/C does it make sense to start real Veda-Core RTL... catching spec
bugs in Sail first, before hardware exists to debug against, is the
entire point"* — that work is no longer blocking. This is Phase 1 of real
Veda-Core RTL, layered onto the already-verified RVA23 base core
(`rtl/rv64i_core.tlv`, 51/51 real ACT4 RV64I conformance).

## Milestone 1 scope: the same subset already proven in Sail V-A

**Capability Register File, Object-Bind, `OCL.D`/`OCS.D` only** — not the
full ISA built across Sail V-A/V-B. This isn't an arbitrary cut: it's the
same "minimal, provable vertical slice first" discipline already validated
twice in this project (RTL Milestone A for the base core itself: "enough
to prove fetch→decode→execute→writeback"; Sail Milestone V-A: identical
scope, identical reasoning). `NMC_ADD`, Veda-Atomic, `OCA`, the query
family, `CSetBounds`/`CSeal`/`CUnseal`, and `ODT-Populate`/`ODT-Destroy`
are real, deferred, later RTL milestones — not silently dropped, just not
attempted in one pass the way the Sail work eventually was.

## Three real architectural decisions this milestone forces

### 1. The ODT is memory-mapped, not a register array

Sail's `veda_odt : vector(8388608, odt_entry)` was a convenience
abstraction appropriate for a *functional ISA-semantics simulator* —
`FORMAL_VERIFICATION_PLAN.md` itself already draws this exact line
("Sail is a sequential ISA-semantics language, not a cycle-accurate
microarchitecture simulator"). It does not dictate a hardware realization,
and a 8.4M-entry flip-flop array would be absurd in real silicon.
`VEDA_CORE_SPEC.md` §5.1 already states the real design intent plainly:
the ODT is "memory-resident, not on-chip SRAM... not a compromise forced
by table size." This milestone makes that concrete for the first time: a
real, byte-addressable `odt_mem[]` array, read/written exactly like
`elfmem`/`dmem` already are in this file, not a new register file.

**Real, honest scope boundary, stated plainly**: sized to 256 entries for
this milestone (real silicon-area consciousness), not Sail's own 8.4M —
`Object_ID` is masked to its low 8 bits for indexing. Scaling this to
anything near the real ID-space width is explicitly deferred, later work,
not attempted here.

### 2. Violations suppress writes; they do not trap — because there is
nothing to trap into yet

The base core's own RTL (`rv64i_core.tlv`) has **no privileged
architecture at all** — no `mcause`/`mtval`, no trap vector, no exception
mechanism of any kind; it is a bare, unprivileged single-cycle core. Sail's
real hard-trap behavior (`mcause=0x18`, `mtval` encoding cause+`cap_idx`)
has no RTL infrastructure to land in yet. Building a full CSR/trap
subsystem now, just to make Veda-Core's own violations "trap" the way Sail
does, would be real, disproportionate scope creep for this milestone —
exactly the kind of ungrounded addition this project's own discipline
rules out elsewhere.

**Real, honest, proportionate choice**: a capability check violation
(`Tag`, bounds, permission — sealing has no RTL meaning yet, since no
instruction can seal a capability in this milestone) suppresses the
write — `OCL.D`'s destination register write-back is gated off, `OCS.D`'s
memory write is gated off — with a new `$veda_violation` signal exposed so
the actual security property (an illegal access cannot corrupt state) is
real and testable now, even though the *signaling* mechanism (an actual
trap) isn't built yet. This is the honest floor: less than Sail's real
behavior, but a real, verifiable property, not a placeholder that does
nothing.

### 3. The generation-staleness check is included from the start, not
deferred to be rediscovered as a gap

Milestone V-A in Sail shipped *without* the generation re-check — it was a
real security gap found and fixed in Milestone V-B, documented as such.
Since that fix is already known, real, and verified, reproducing the same
gap here — now that it's a known mistake, not an honest scope boundary —
would be a real regression in judgment. The RTL comparison is included
from the start: `Object-Bind` caches the ODT's `generation` field into the
capability register, and `OCL.D`/`OCS.D` re-read the live ODT entry and
compare. **Real, honest caveat**: with no `ODT-Populate`/`ODT-Destroy`
instruction in this milestone (deferred, same as Sail V-A → V-B), this
check has nothing to go *stale* against yet — it's structurally present
and correct, but not independently testable until Milestone 2, exactly
mirroring how Sail's own end-to-end proof of this same mechanism had to
wait for `ODT-Destroy` to exist.

## Test-seed scaffold, explicitly temporary

`odt_mem[]` is preloaded at reset via an `initial` block — the same real,
already-used mechanism `ROM[]` already relies on in this file, not a new
idiom — seeding `Object_ID=1` (`Base=0x80010000`, inside the same
ELF-loaded RAM region ACT4/`elfmem` uses; `Length=0x40`; `Perms=0x100C`;
`generation=0`; `valid=1`), mirroring Sail V-A's own `veda_test_seed_odt()`
scaffold field-for-field. Explicitly temporary, same reason: no real
`ODT-Populate` instruction exists yet.

## Verification approach

A real, hand-assembled smoke test (same methodology as the base core's own
Milestone A/B): `Object-Bind` a capability to the seeded `Object_ID=1`,
`OCS.D` a known value, `OCL.D` it back, confirm exact match via manual
trace review — the same positive-path shape already proven twice (Sail
V-A, and now RTL). A negative control (an unbound capability register,
`Object_ID` never populated) must show `$veda_violation` asserted and the
destination register/memory correctly *not* written — mirroring this
project's own repeated negative-control discipline (RTL ACT4 testbench,
every Sail milestone, the V-C self-check corpus) rather than only showing
a correct case pass.

## Milestone 4 addendum: a minimal, real privilege gate, decided after
direct user challenge, not preemptively

Milestones 1–3 deferred *all* privilege architecture (item 2 above). That
was verified safe at the time: every instruction built so far only
exercises or narrows an *already-granted* capability (Object-Bind reads
an ODT entry populated at hardware reset, not by software; `OCA`/
`CSetBounds` only ever narrow, CHERI's own real monotonicity principle,
verified in full-document research earlier this project) — nothing built
so far can *escalate* access beyond what a trusted, pre-execution step
already granted.

That property expires the moment `ODT-Populate` becomes a real, callable
RTL instruction — it *mints* new capability-granting authority from raw
`Base`/`Length`/`Perms` values, and monotonicity provides no protection
against a mint operation itself. This is not unique to Veda-Core: every
real capability system researched this project (seL4's trusted-root
principle, CHERI's boot-firmware-established root capabilities, Plessey's
own privileged SCT population) resolves this identically, and every real
CHERI hardware implementation read in full this project (CHERI-Tooba, on
Piccolo/Flute/Toooba) sits on top of a core with genuine RISC-V M/S/U
privilege architecture underneath its capability layer — capability-based
and privilege-based access control are consistently complementary in
every real system checked, not substitutes.

**Decision**: build the smallest real mechanism that closes this specific
gap, not a full M/S/U/trap subsystem (still disproportionate scope creep
for what's actually needed) and not a partial, semantically-misleading
subset of real `mstatus`/`mret` (which would *look* standard while not
*behaving* standard, since real `mret` is a trap-return semantic this core
has no trap to return from). A new 1-bit `$priv` register, reset to `1`
(privileged, matching real RISC-V's own "harts reset into the highest
privilege level" convention), and one new instruction —
`veda.droppriv` — in the Custom-3 opcode space (`1111011`, explicitly
"Reserved, unallocated" in `VEDA_CORE_SPEC.md`'s own ISA summary table
since the very first draft), which clears `$priv` to `0`. Deliberately
one-way: no instruction raises it back, matching the common real
"drop-privilege-and-never-return" pattern used in secure-boot flows,
and avoiding the need to design a real trap-based privilege-raise
mechanism this milestone doesn't need. `ODT-Populate`/`ODT-Destroy`
(`VEDA_CORE_SPEC.md` §5.1's already-decided encoding: Custom-0,
`funct7=0000011`, `funct3=000`/`001`) are gated on `$priv == 1`, using
this project's own established violation-suppresses-write convention
when not privileged (no trap infrastructure exists to raise a real
exception into, the identical real constraint already documented for
every other instruction built so far).
