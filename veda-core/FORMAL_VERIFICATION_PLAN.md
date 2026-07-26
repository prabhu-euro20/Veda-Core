# Veda-Core Formal Verification Plan (Draft v0.1)

**Status**: Design-stage. No Sail code written yet. This is the plan for task "design a Sail-equivalent formal verification model for Veda-Core" (`VEDA_CORE_SPEC.md` §6 item 5) — what mechanism to build on, what maps onto real precedent, what's genuinely novel, and in what order. Nothing here goes beyond what was verified against the actual local `sail-riscv` source; where something has no real precedent, it's marked as such rather than invented.

---

## 1. Decision: extend our own local `sail-riscv`, not fork `sail-cheri-riscv`

`VEDA_CORE_SPEC.md` already named `sail-cheri-riscv` as "CHERI's own answer to the equivalent problem — a Sail extension of the same `sail-riscv` model." Verified this pass, directly from the local `toolchain/sail-riscv` checkout (the same one ACT4 already uses as its Sail reference model, `sail_riscv_sim`): that description is accurate — `sail-riscv` has a real, native, per-extension file layout (`model/extensions/<Name>/*.sail`) used by every extension already in the tree (A, B, C, FD, M, V, Zicbom, pointer_masking, etc.), not a one-off CHERI-specific mechanism.

**Decision**: build Veda-Core's model as a new `model/extensions/Veda/` directory inside our own already-built, already-verified `sail-riscv` checkout, using that same native mechanism — not by fetching and adapting the real `sail-cheri-riscv` repository. Reasoning: `sail-cheri-riscv` encodes *CHERI's* capability format (flat 64-bit addresses, MMU integration, sentries, `PCC`/`IDC`) — adapting it would mean fighting an entire unrelated architecture's assumptions to retrofit Veda-Core's address-less, `Object_ID`-based model onto it. Writing fresh extension files against our own verified base, using the same real mechanism CHERI's own extension is built on, is the more direct path and doesn't require an extra external dependency.

---

## 2. What maps directly onto real, already-present hooks (verified, not assumed)

Read the following files in full from the local checkout before deciding anything below — not summarized from search results:

### 2.1 Custom exception code — a real, unplanned cross-check

`model/core/types_ext.sail`:
```sail
mapping ext_exc_type_bits : ext_exc_type <-> exc_code = {
  // First code for a custom extension
  () <-> 0b011000, // 24
}
```
`0b011000` = `0x18` = **24** — Sail's own default reservation for a custom extension's exception code. `VEDA_CORE_SPEC.md` §3 independently committed to `mcause = 24 (0x18)` months earlier, verified only against the RISC-V privileged spec's "designated for custom use" range (24-31, 48-63), with no knowledge of this Sail hook. The two agree exactly. This isn't proof of anything beyond coincidence-of-convention, but it's a real, found-not-planned confirmation that the design's exception-numbering choice sits exactly where Sail's own extension mechanism expects a single custom extension to sit.

### 2.2 Tagged memory — `mem_meta`

`model/core/mem_metadata.sail`:
```sail
type mem_meta = unit
let default_meta : mem_meta = ()
function __WriteRAM_Meta(_addr : physaddrbits, _width : mem_access_width, _meta : mem_meta) -> unit = ()
function __ReadRAM_Meta(_addr : physaddrbits, _width : mem_access_width) -> mem_meta = default_meta
```
The comment ("default metadata carries no information... unit type") makes clear this exists *specifically* for an extension to override with real per-location metadata. This is the real hook for Veda-Core's capability Tag bit surviving a round trip through memory (`OCL.C`/`OCS.C`, the 128-bit capability load/store width already in `VEDA_CORE_SPEC.md` §1's OCL/OCS width table) — Veda-Core's extension would redefine `mem_meta` to carry the Tag bit and implement the two functions against a real tag store, rather than inventing a parallel memory-tagging mechanism from scratch.

### 2.3 A new register file — the V extension as template

`model/extensions/V/vext_regs.sail` (read in full):
```sail
newtype vregidx = Vregidx : bits(5)
newtype vregno = Vregno : range(0, 31)
...
register vr0 : vlenbits
register vr1 : vlenbits
... (32 total)
```
This is the real, direct template for Veda-Core's 16-register Capability Register File (`VEDA_CORE_SPEC.md` §2): `newtype cregidx = Cregidx : bits(4)` (4 bits address 16 registers, `c0`-`c15`), a `capability` Sail `struct` type matching §2's exact field layout — **as originally drafted here**, `Object_ID: bits(16)`, `Base: bits(32)`, `Length: bits(16)`, `Offset: bits(16)`, `Perms: bits(16)`, `otype: bits(16)`, `Reserved: bits(15)` (the `Length`/`Offset` split, not the originally-drafted single 32-bit `Limit` field, is the corrected layout: `VEDA_CORE_SPEC.md` §2 documents a real gap found and fixed only after this plan's first draft, when `OCA`'s own already-written semantics turned out to reference a capability `Offset` field the field table never actually defined) — **since widened, post-V-A, to `Object_ID: bits(23)`/`Reserved: bits(8)`** (§6 below), and 16 `register crN : capability` declarations. The Tag bit is out-of-band per §2 ("not counted in the 128"), so it needs its own parallel state — most directly a 16-bit `register crTags : bits(16)`, one bit per capability register, mirroring how `mem_meta` (2.2) keeps the memory-resident tag similarly out-of-band from the data.

### 2.4 Instruction dispatch — the Zicbom extension as template

`model/extensions/Zicbom/zicbom_insts.sail` (read in full, 128 lines, a real, complete, minimal-but-non-trivial extension): confirms the exact 4-clause pattern every extension in this tree uses to add new instructions to the model:
```sail
function clause currentlyEnabled(Ext_X) = hartSupports(Ext_X)
union clause instruction = MNEMONIC : (field, field, ...)
mapping clause encdec = MNEMONIC(...) <-> bits(32) when currentlyEnabled(Ext_X)
mapping clause assembly = MNEMONIC(...) <-> "mnemonic" ^ ...
function clause execute MNEMONIC(...) = ...
```
This is the real template for every one of Veda-Core's ~20-odd instructions (`OCL.{B,H,W,D,C}`, `OCS.{B,H,W,D,C}`, `NMC_ADD.{W,D}`, Object-Bind, Veda-Atomic's op family, `CGetBase/Len/Perm/Tag/Type/Addr/Offset`, `CSetBounds(Exact)`, `OCA`, `CSeal`, `CUnseal`). `currentlyEnabled` also ties directly into the same extension-enable convention already used throughout this session's ACT4 config work (`sail.json`'s `extensions.<Name>.supported` field, `rva23-base-rv64i.yaml`'s `implemented_extensions` list) — a Veda-Core UDB/ACT4 config would gate this extension the identical way `I`/`Zicsr`/`Sm` are gated today.

---

## 3. The ODT — now resolved (`VEDA_CORE_SPEC.md` §5.1), Sail representation still open

Searching `model/core/` and the page-table-walk extension hooks (`ext_ptw`, `types_ext.sail`) directly, confirmed nothing in `sail-riscv`'s own model maps onto "look up an `Object_ID` in a table, get back `Base`/`Limit`/`Perms`/`otype`" — CHERI has no equivalent either (CHERI capabilities describe regions of one flat address space directly, no object-table indirection). This *design* question is now resolved (`VEDA_CORE_SPEC.md` §5.1, researched against seL4's CSpace, IBM System/38, and the Cambridge CAP Computer's Process Resource List — a flat, single-level, system-wide table indexed by `Object_ID`, with a per-entry generation counter to detect stale capabilities after ID reuse). What's still open here is purely the *Sail representation*:

- Most directly a `register ODT : vector(65536, ODT_Entry)`, `ODT_Entry = struct { valid : bool, Base : bits(32), Length : bits(16), Perms : bits(16), generation : bits(N) }` (`Length` not `Limit` — matches the capability register's own corrected field layout, §2; N not yet fixed, §5.1) — a flat vector maps cleanly onto §5.1's now-decided flat structure, no multi-level lookup logic needed in the model. **Since widened, post-V-A**: `vector(8388608, ODT_Entry)`, `generation : bits(8)` (N now fixed) — `Object_ID` grew from 16 to 23 bits, `SCALING_BARRIERS_RESEARCH.md` §3.
- Needs a way to get populated before a test runs — real RISC-V extensions don't need this (their state either starts zeroed or is set up by the instructions under test themselves), but Veda-Core's ODT is logically "device/environment configuration," analogous to how ACT4's own test setup pre-loads a signature region. Concretely: likely a test-harness-level mechanism (e.g., a reserved memory region the Sail model reads at reset, mirroring how the real `elfmem`/`+elf_hex` mechanism already built for the RTL testbench this session loads memory from the ELF), or the actual ODT-creation instruction/MSA-command once §5.1's "exact instruction encoding... not decided this pass" is resolved. Not decided yet, flagged honestly as open.
- The MSA's `{command, Object_ID, validated_offset, width/data}` request / `{data/old-value, done}` result exchange (§5), including the now-added generation re-check (§5.1), is architecturally a function call inside the Sail model (Sail is a sequential ISA-semantics language, not a cycle-accurate microarchitecture simulator) — there's no "the MSA takes multiple cycles" concept to model at this level, only "did the ODT lookup, generation check, and bounds/permission check succeed." This is actually a *simplification* in Sail's favor: the real multi-cycle pipeline-stall behavior (§5's "how the CPU waits") is an RTL-only concern, checked later via the RTL-vs-Sail trace-diffing technique (§4), not something the ISA-semantics model itself needs to represent.

---

## 4. Verification/build strategy

- **Build mechanism**: identical to what's already proven this session for the (unmodified) RVA23 base core — Sail compiles the model (base `sail-riscv` + the new `extensions/Veda/` files) into a C emulator via the same toolchain already built at `toolchain/sail-riscv/build/`. The result is a new binary (e.g. `veda_sim`) that becomes Veda-Core's own golden reference, architecturally the same role `sail_riscv_sim` already plays for ACT4's RV64I conformance today.
- **RTL-vs-Sail comparison**: this session already proved, empirically, that comparing an RTL core's own execution trace against `sail_*_sim`'s trace output is a real, working way to catch bugs — this is exactly how the genuine SLLI/SRLI/SRAI `funct6` decode bug got found and confirmed fixed (bit-for-bit SP/GP match against Sail's own trace after the fix). The identical technique applies unchanged once real Veda-Core RTL exists: no new tooling needed, just Veda-Core-specific trace points (capability register contents, ODT state) added to the comparison.
- **Test corpus**: ACT4's own test generator (`generators/testgen/`) has no knowledge of custom opcodes — it's driven by UDB extension configs for ratified RISC-V extensions only. Veda-Core needs its own hand-written directed test corpus, not an auto-generated coverage suite, at least initially. ACT4's own `tests/env/` self-check infrastructure (`RVTEST_SIGUPD`, `rvmodel_macros.h`'s `tohost` convention) is not RISC-V-standard-specific — it's DUT-agnostic macros — so Veda-Core's own hand-written `.S`-equivalent tests can reuse that same self-check/`tohost` pattern rather than inventing a separate pass/fail protocol.

---

## 5. Recommended sequencing (mirrors the RVA23 core's own milestone structure, which worked well this session)

- **Milestone V-A — done.** Capability `struct`, the 16-register CRF + Tag array, the ODT (flat, system-wide), Object-Bind (`Bind`/`Bind-NoTrap`/`Rebind`), and `OCL.D`/`OCS.D` are real, working Sail code in `toolchain/sail-riscv/model/extensions/Veda/`, compiled into a real `sail_riscv_sim` binary, and verified end-to-end against a real hand-assembled test program — both a positive round-trip (bind, store, load-back, exact match) and a negative control (an unbound capability traps with the exact right `mcause`/`xtval`). See `MILESTONE_V-A_RESULTS.md` for the full results and the real bugs found and fixed while building it.
- **Milestone V-B — done.** `NMC_ADD.{W,D}`, Veda-Atomic (9 real AMO-style ops), `OCA`, the full Veda-Cap query family, `CSetBounds`/`CSetBoundsExact`, `CSeal`/`CUnseal` with the sealed-capability soft-fail/hard-trap split, and a real `ODT-Populate`/`ODT-Destroy` mechanism (replacing V-A's temporary test scaffold) are all real, working Sail code, verified against 13 real hand-assembled test programs covering both positive and negative paths for every instruction added — this is exactly the subtle logic this whole task was motivated by wanting an executable check for, and the enforcement test (a sealed capability's use hard-trapping with the exact right `mcause`/`mtval`) is the single most important result in it. A real security gap was also found and fixed this pass: the ODT generation counter, required by the spec to be re-checked on every dereference, was never actually re-checked by Milestone V-A's own code — fixed, and proven end-to-end once `ODT-Destroy` existed to go stale against. See `MILESTONE_V-B_RESULTS.md` for the full results and the real bugs found and fixed while building it. Remaining `OCL`/`OCS` widths (B/H/W/Cap, beyond V-A's D-only scope) were not part of this pass — not needed by anything built so far, deferred rather than force-fitted.
- **Milestone V-C — done.** A real, self-checking directed test corpus (14/14 passing) using `sail_riscv_sim`'s own real, built-in HTIF/`tohost` support — confirmed working for the first time this pass by giving it a real `.tohost` linker section (every earlier test run had HTIF silently disabled purely because the minimal test linker scripts never defined the symbol). Reuses this project's own real ACT4 `RVMODEL_HALT_PASS`/`RVMODEL_HALT_FAIL` convention verbatim, plus a trap-handler pattern for negative cases that verifies the *exact* `mcause`/`mtval`, not just that some trap fired. A deliberately-broken test was run through the same batch runner and correctly reported `FAIL`, confirmed before trusting the clean pass count — the same negative-control discipline already used for the RTL ACT4 testbench. See `MILESTONE_V-C_RESULTS.md`.
- **Only after V-A/B/C** does it make sense to start real Veda-Core RTL (Custom-0/1/2 decode) — catching spec bugs in Sail first, before hardware exists to debug against, is the entire point of doing this work now rather than after, and is explicitly CHERI's own documented history/rationale for building `sail-cheri-riscv` in the first place.

---

## 6. Explicitly not decided yet

- Exact `ODT` entry-creation/destruction instruction encoding (`VEDA_CORE_SPEC.md` §5.1 resolves the *authorization* — gated by `Permit_Access_System_Registers` — and the *data model*, but not the encoding itself).
- ~~Exact width of the generation-counter field within the capability's `Reserved/Flags` bits (§5.1, §2).~~ **Resolved, post-V-A**: fixed at 8 bits (narrowed from the 15-bit placeholder V-A shipped with), matching CHERI-D's real, empirically-derived per-allocation generation-counter width — the 7 bits freed were applied to widening `Object_ID` from 16 to 23 bits instead (`VEDA_CORE_SPEC.md` §2, `SCALING_BARRIERS_RESEARCH.md` §3). Both the spec and the Sail model (`veda_types.sail`, `veda_regs.sail`, `veda_bind_insts.sail`) were updated to match.
- Exact Veda-Atomic op-select values (`VEDA_CORE_SPEC.md` §1 already notes these as "proposed... not yet finalized").
- Whether the Tag array (§2.3) should be a flat 16-bit register or embedded per-capability in the `struct` — either is mechanically fine; not yet chosen since it doesn't affect any decision made so far.
