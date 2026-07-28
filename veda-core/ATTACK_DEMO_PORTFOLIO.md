# Real Attack-Demo Portfolio: Traditional RV64I vs Veda-Core, Five Real Vulnerability Classes

**Date:** 2026-07-28
**Purpose:** a single, honest, numbers-first collection of every real,
empirically-run attack demonstration built in this project so far, each
run on both the real, unmodified, committed `rv64i_core.tlv` (traditional)
and `veda_core.tlv` (Veda-Core) — for external presentation (community,
prospective collaborators/funders). Every result below is a real register
or memory value read directly out of an actual Icarus Verilog simulation
of the real RTL, not a theoretical claim.

## Why five, not one — and why these five specifically

A single before/after demo invites the objection "that's one cherry
-picked case." These five were chosen because each is a distinct, real,
independently-named vulnerability class with its own large real-world
literature and its own CVE history — not five variations on the same
underlying bug:

1. Out-of-bounds read (information disclosure)
2. Out-of-bounds write (memory corruption)
3. Stack-smashing / return-address hijack (control-flow hijacking, ROP)
4. Use-after-free (temporal memory safety)
5. Arbitrary-pointer forgery (the "can you fabricate a valid pointer out
   of nothing" question underlying capability unforgeability itself)

Three of these (#3, #4, #5) are new to this document; #1/#2 are carried
over from `SECURITY_COMPARISON_STUDY.md` with the same real numbers, not
re-derived.

## 1. Out-of-Bounds Read (information disclosure)

Same off-by-one loop bug on both cores; an 8-element array immediately
followed by a `secret` value; the loop runs 9 iterations instead of 8.

| | Traditional | Veda-Core |
|---|---|---|
| Result register | `x7 = 0xdeadbeefcafebabe` (secret leaked) | trap fired, `mcause=0x18`/`mtval=0x01` (Bounds Violation), secret never read |

## 2. Out-of-Bounds Write (memory corruption)

Same shape; a `canary` value follows the array; the loop *writes*
`0xbad0bad0bad0bad0` for 9 iterations instead of 8.

| | Traditional | Veda-Core |
|---|---|---|
| Canary after the loop | `0xbad0bad0bad0bad0` (**overwritten**) | `0x1111111111111111` (**untouched**), trap fired |

## 3. Stack-Smashing / Return-Address Hijack (ROP)

The single highest-profile real-world vulnerability class this portfolio
covers — the payload behind decades of real exploit chains. Three real
programs (`STACK_FRAME_CALL_RETURN_ANALYSIS.md`, `rtl/MILESTONE_17_RESULTS.md`):
a simulated stack-buffer-overflow overwrites a saved return address; the
program then "returns" through it.

| Test | Convention | Result | Meaning |
|---|---|---|---|
| `trad_hijack` | traditional `sd ra`/`ld ra`/`jalr` | `x30 = 0xbad1` | **attacker fully hijacked control flow** — jumped to an attacker-chosen address |
| `prot_gap` | Veda-Core, protection built from existing instructions but the explicit check *omitted* | `x30`/PC undefined (X) | proves a **software-discipline gap is real**, not just theoretical |
| `prot_fixed` | Veda-Core, `OCJALR` — one new, atomic, hardware-enforced instruction | `x30 = 0xca11`, real controlled trap | corruption caught **structurally**, no software check needed |

Real, measured cost: the hardware-enforced version (`OCJALR`) is not just
safer than the naive protected version — it is **~30% cheaper** (7 vs. 10
cycles/call), because merging the check into the jump itself removes a
separate branch and query instruction, not just the gap they left open.

## 4. Use-After-Free (temporal memory safety)

New this pass. UAF is the exploitation primitive behind a large fraction
of real, published browser and OS-kernel CVEs: a program keeps using a
reference to memory that has since been freed and reallocated to
something else. Real programs (`trad_uaf.S`/`veda_uaf.S`, session-scoped,
not committed): object A is allocated, a reference to it is kept, A is
"freed" (traditional: nothing happens at the hardware level at all —
"free" is purely a software convention; Veda-Core: a real `ODT-Destroy`),
the same memory/`Object_ID` is reused for a new, unrelated object B, and
the program's *original, stale* reference to A is used again.

| | Traditional | Veda-Core |
|---|---|---|
| Read through the stale reference | `x7 = 0xbbbbbbbbbbbbbbbb` — **object B's data returned through what the program still believes is a pointer to object A** (real type-confusion/info-disclosure primitive) | trap fired, `mcause=0x18`, `mtval=0x02` (Tag Violation via stale-generation re-check), verified at the exact faulting instruction |

This is not a new mechanism — it is Veda-Core's own generation-counter
+ `ODT-Destroy` design (already unit-tested since RTL Milestone 1, "post
-destroy rebind Tag=0, stale-generation OCL rejected"), demonstrated here
for the first time as a direct, named UAF attack scenario rather than an
internal mechanism test.

## 5. Arbitrary-Pointer Forgery (capability unforgeability)

New this pass, and arguably the most structurally fundamental of the
five: can an attacker who fully controls a block of memory simply
*fabricate* a working pointer out of nothing? Real programs
(`trad_forge.S`/`veda_forge.S`): an attacker-chosen, fully-controlled
16-byte bit pattern (`0xDEADC0DEDEADC0DE` repeated) is written into memory
via an ordinary store (not a real capability-producing instruction — the
same primitive a buffer overflow actually gives an attacker) and then
used as if it were a pointer/capability.

| | Traditional | Veda-Core |
|---|---|---|
| Using the forged value | `x7 = 0xdeadc0dedeadc0de` — **write and read both succeed unconditionally**, the single most powerful real exploitation primitive (arbitrary read/write) | `CGetTag = 0` (forged bits are never tagged — Tag is out-of-band, set only by real hardware operations), then attempting to use it anyway (`OCS.D`) hard-traps: `mcause=0x18`, `mtval=0x122` (Tag Violation, `cap_idx=9`), verified at the exact faulting instruction |

This is the real, empirical demonstration of the property CHERI's own
literature calls out as its headline guarantee: **pointers cannot be
forged from arbitrary data — only minted by real, authorized hardware
operations** (`Bind`, `OCA`, `CSeal`, ...). Every other result in this
portfolio is a downstream consequence of this one property.

## Does "traditional" here mean real x86/ARM/production-RISC-V hardware? A direct, honest answer

A fair, important challenge, worth answering precisely rather than
glossed over: `rv64i_core.tlv` is this project's own single-cycle RV64I
core (real ACT4-conformant, 51/51, but never fabricated, never even
FPGA-realized) — not a real Intel/AMD/Arm/SiFive chip. Two genuinely
different questions hide inside "is this the same as real hardware,"
and they have different answers.

**Is the base-ISA behavior being demonstrated real?** Yes, and this part
transfers directly. A raw load/store instruction — `SD` on RISC-V, `MOV
[addr], reg` on x86, `STR` on ARM — has no bounds check, no tag check,
no use-after-free detection built into the instruction itself, on *any*
mainstream architecture's own base ISA. This is not a simplification our
demo core introduces; it is how real load/store instructions work
everywhere. This is the part all five demos actually exercise.

**Does real production hardware have *other*, additional layers that
might catch some of these anyway?** Yes, real ones exist, verified via
live search rather than assumed, and they matter:

- **MMU/virtual-memory paging**: real OS processes run behind page
  tables, and an out-of-bounds access that crosses into an unmapped or
  differently-permissioned page does fault (`SIGSEGV`). But this
  protection is real, verified, **page-granularity only** (typically
  4KB) — "a buffer overflow that occurs within the same page will not
  be caught by MMU paging hardware... these software-based techniques
  [stack canaries, bounds checking, tagging] are necessary to catch
  intra-page buffer overflows that MMU hardware protection cannot
  prevent." Every demo in this portfolio is exactly this kind of
  same-page, sub-object overflow — the class real MMUs do not address.
- **Intel CET (shadow stack)**: real, and directly the same concept as
  RISC-V's own ratified Zicfiss this project already researched
  (`STACK_FRAME_CALL_RETURN_ANALYSIS.md`) — but real-world adoption has
  been slow; it needs OS and compiler opt-in, not a universal, always-on
  guarantee across the installed base.
- **Arm Pointer Authentication (PAC)**: real, shipping — "common on
  Apple Silicon (M1, M2) and high-end Android SoCs" — not universal
  across Arm chips generally, and specifically a return/control-flow
  protection, not a general bounds or use-after-free mechanism.
- **Arm MTE**: real, shipping on some devices, but a narrow 4-bit tag
  (compare Veda-Core's or CHERI's full out-of-band Tag plus 128-bit
  capability envelope) with probabilistic (not absolute) guarantees in
  common configurations.
- **Intel MPX**: attempted a comparable idea, real, and real precedent
  for the honest failure mode — deprecated and removed due to poor
  adoption and performance overhead.

**Why the comparison is still fair, not overstated**: none of the real
mitigations above are the universal, always-on, architecturally-uniform
guarantee this portfolio's claim is actually about. Each is opt-in,
partial (covers only control-flow or only some chips), or both, and the
one mechanism broad real deployment leans on hardest — the MMU — is
independently confirmed not to catch the exact, same-page vulnerability
shape all five demos here use. This is not a novel argument invented for
this project: it is the identical argument CHERI's own literature makes
for its own value proposition against the same real mitigations, and
this portfolio uses that same, community-accepted framing rather than a
new one.

**What would make this airtight, honestly stated**: running the identical
five attack shapes on real x86/Arm silicon with CET/PAC/MTE enabled,
observing which specific demos those specific mechanisms do or do not
catch. Not done here — a real, distinct follow-up, not claimed as already
covered.

## Honest scope, stated plainly

- All five are real RTL simulations of the actual, unmodified, committed
  cores — not Sail-only, not theoretical. Every register/trap value shown
  was read directly from an Icarus Verilog run.
- No FPGA/silicon exists yet (`STACK_FRAME_CALL_RETURN_ANALYSIS.md` and
  recent FPGA-feasibility work already state this honestly) — these are
  simulation results, the same standard evidentiary tier real
  architecture-research papers (including CHERI's own early publications)
  use before silicon exists.
- Each demo injects one specific, hand-crafted bug/attack shape to
  isolate one specific mechanism. Real-world exploitation often chains
  multiple primitives together — these are not claims that Veda-Core
  defeats "all possible attacks," only that it closes these five real,
  named, independently-significant classes, each verified for the
  *specific, correct* reason (real cause codes checked, not just "did it
  trap").
- Demos #4 and #5 are session-scoped test programs (not yet committed to
  the milestone test suite) — real, run against the real core, but not
  yet part of the permanent regression corpus the way #1-#3's underlying
  mechanisms already are.

## Reproducing this

Demos #4/#5: `/tmp/claude-.../scratchpad/attackdemos/` (session-scoped):
`enc.py` (encoder, self-checked against known-good committed encodings),
`gen_uaf.py`/`gen_forge.py` (generate the four `.S` programs),
`tb_marker.sv` (shared testbench), `build_and_run.sh` (transpiles both
real, unmodified cores once each, builds and runs all four programs).
Demos #1/#2: `SECURITY_COMPARISON_STUDY.md`'s own reproduction section.
Demo #3: `STACK_FRAME_CALL_RETURN_ANALYSIS.md` and
`rtl/MILESTONE_17_RESULTS.md`'s own reproduction sections.

## Sources (for the "does this reflect real hardware" section)

- [Memory Management Unit, ScienceDirect Topics](https://www.sciencedirect.com/topics/computer-science/memory-management-unit) — MMU role and page-level granularity.
- [Buffer overflow protection, Wikipedia](https://en.wikipedia.org/wiki/Buffer_overflow_protection) — same-page/intra-page overflow not caught by MMU paging; software techniques (canaries, bounds checking, tagging) needed for that gap.
- [Control-flow Enforcement Technology (CET) Shadow Stack, Linux Kernel documentation](https://docs.kernel.org/6.9/arch/x86/shstk.html) — real CET shadow-stack mechanism.
- [Intel Shadow Stack – A Bridge Too Far for the Tech Giant?, Karamba Security](https://karambasecurity.com/blog/2019-06-11-intel-cet-notyet) — real-world CET adoption lag.
- [LLVM CFI vs Intel CET vs ARM PAC: A Deep Dive into Control Flow Protection](https://medium.com/@nikheelvs/llvm-cfi-vs-intel-cet-vs-arm-pac-a-deep-dive-into-control-flow-protection-39fd4af2fb36) — ARM PAC real deployment (Apple Silicon M1/M2, high-end Android SoCs).
