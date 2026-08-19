# VEDA_LOCAL_HANDLER: hardware-enforced compartment-local fault recovery

## The gap, and why it's real for Veda-Core specifically

§3.5 of `NEXT_STEPS_ROADMAP.md` (2026-08-19) named this gap after a full re-read of CHERIoT RTOS
(Amar et al., ACM SOSP '25, official, cross-industry-authored, read complete for this pass -- not
just its §5.1.2 "repeat attacks" paragraph this project already acted on). CHERIoT's second design
principle states plainly: **"(P2) Fine-grained fault-tolerant compartments... A thread that
encounters a fault... invokes the developer-provided error handler for that compartment. The
handler might unwind the thread out of the compartment and/or micro-reboot it."** That handler is
*"called by the switcher but executing in the context and with the rights of the [faulting]
compartment"* -- bounded, not ambient. §5.1.2's own "Attacks on the error handler" paragraph names
the accepted residual risk: a buggy handler could corrupt state, but the blast radius stays scoped
to that one compartment's own rights, because the handler never runs with more privilege than that.

Veda-Core has no equivalent. Confirmed directly (not assumed) by reading `postlude/step_ext.sail`'s
`handle_trap_extension` and `sail_tests/vc_syscall0_kernel.S`'s real `handler:` entry point: every
real trap resets `veda_pcc_length` to `VEDA_PCC_UNBOUNDED` unconditionally, and the single global
`mtvec` handler runs start-to-finish with fully ambient authority. A bug in that one handler has an
*unbounded* blast radius -- strictly larger than the residual risk CHERIoT itself names and accepts.

## Research: what CHERI's own base architecture actually says (read in full, not assumed)

**The base CHERI ISA spec** (UCAM-CL-TR-987, Version 10-DRAFT, University of Cambridge, read
directly, §2.4.6 and §3.11.2) states the *opposite* of what I first assumed before checking: exception
handling in the base architecture is expected to run with **elevated** rights, not reduced ones --
"as exception handlers are entered, they *gain access to capabilities unavailable to general
execution*, allowing them to implement mechanisms such as domain transition to more privileged
compartments" (§3.11.2). §2.4.6 is explicit that this nonmonotonic escalation is how compartmentalization
gets built at all: *"If the software supervisor arranges that additional rights will be acquired by
the exception handler..., then the exception handler will be able to perform non-monotonic
transformations on the set of capabilities in the register file."* Register/context save-restore
across an exception is also explicitly named as a **software** responsibility in the base spec, not
a hardware guarantee: *"the exception handler must restore or clear those values [that could leak
capabilities]"* (§3.11.2, "Safe exception state handling").

**The real conclusion, stated honestly**: Veda-Core's own current model (unconditional
reset-to-unbounded, ambient-authority global handler) is not a deviation from base CHERI -- it *is*
base CHERI's own default architecture, precisely as officially specified. CHERIoT's compartment-scoped
`compartment_error_handler()` is not something the ISA hands you; it is a deliberate **software
convention CHERIoT's own switcher builds on top of** the base mechanism, by choosing to re-enter the
faulting compartment's own code rather than escalating all the way to the kernel. This project
already has the load-bearing primitive that convention would be built on: the switcher pattern
(`MINIMAL_OS_KERNEL_DESIGN.md`, Milestone A, Sail-verified 44/44), which already routes every
cross-compartment transition through one trusted intermediary using nothing but `OCInvoke`, exactly
matching the base spec's own explicit switcher blueprint (p.317-318, quoted in that doc's Finding 5).

## Design decision: hardware-native, not a copy of CHERIoT's software convention

Given the reframe above, the honest options are: (a) build the identical CHERIoT convention
(switcher software decides to re-enter a compartment's handler function), or (b) go further and make
the *scoping guarantee itself* a hardware invariant, so a bug in the redirect logic cannot possibly
grant more than the faulting compartment's own bounds -- no trusted software step required to get it
right. Per this project's own standing "hardware gets priority whenever it can solve a security
problem" philosophy, and because Veda-Core already has every piece needed to build (b) as a small,
precise extension of infrastructure this project already built and verified this session, **(b) is
the decision**: `VEDA_LOCAL_HANDLER`, a hardware-mediated redirect that can never widen PCC beyond
the faulting compartment's own already-captured bounds, composing with `VEDA_TRAP_QUARANTINE`
(same session) as its own safety backstop rather than inventing a parallel one.

## Mechanism

**Reused, not reinvented** -- three pieces of infrastructure this project already has, unmodified:
1. `veda_pcc_otype` (`VEDA_TRAP_QUARANTINE`, this session) -- already identifies the faulting
   compartment at the exact chokepoint this design hooks.
2. `veda_mepcc_base`/`veda_mepcc_length` (Milestone 21-restore) -- already captures the faulting
   compartment's own pre-trap Base/Length on every real trap, before this design's own hook runs.
3. `veda_trap_tracker_is_quarantined(otype)` (`VEDA_TRAP_QUARANTINE`) -- already the authoritative
   "has this compartment been faulting too much" signal.

**New state**: `veda_local_handler_table`, an 8-entry table (matching `veda_trap_tracker`'s own
established size/shape precedent for a small otype-keyed structure), each entry `{valid, otype,
entry_addr}`. No `Length` field -- the redirect target's *bounds* are always the SAME
`veda_mepcc_base`/`veda_mepcc_length` already captured for that trap, never a separately-declared
region; the handler can therefore never do anything the faulting compartment's own ordinary code
could not already do (a strictly narrower guarantee than requiring a Length match).

**New instruction, self-registration only**: `VEDA_SET_LOCAL_HANDLER rs1` -- registers `X(rs1)` as
the CURRENT live compartment's own local-handler entry point, keyed by `veda_pcc_otype`. Two checks,
both hard-trap on failure:
- Callable only from within a live, bounded compartment (`veda_pcc_length != VEDA_PCC_UNBOUNDED`) --
  there is no "otype" to register against otherwise.
- `X(rs1)` must lie within `[veda_pcc_base, veda_pcc_base + veda_pcc_length)` -- a compartment can
  only ever point its own handler at its own code, never at another compartment's or the kernel's.
  This is the confused-deputy guard: no operand names a target otype, so nothing lets one compartment
  register a handler for a DIFFERENT compartment.

Table write follows the exact same allocate-or-evict shape `veda_trap_tracker` already established
(free slot first, else evict; re-registering the same otype overwrites in place) -- deliberately not
reusing that same table, because the two structures have incompatible lifecycles: quarantine entries
are an opportunistic attack-mitigation cache meant to decay/evict; a registered handler must be
stable and must never be silently evicted by unrelated trap churn from other compartments.

**Trap-time redirect** -- the new logic lives in `veda_pcc_save_and_reset()`, the exact chokepoint
`VEDA_TRAP_QUARANTINE` already extended this session, added *after* the existing `mepcc` capture and
*after* the existing `record_fault` call (so a local-handler invocation counts toward the SAME
quarantine budget as any other real fault from that compartment -- see "Composition" below):

```
if veda_pcc_length != VEDA_PCC_UNBOUNDED then {
  veda_trap_tracker_record_fault(veda_pcc_otype);   // already exists
  veda_mepcc_base = veda_pcc_base;                  // already exists
  veda_mepcc_length = veda_pcc_length;               // already exists
  if not(veda_trap_tracker_is_quarantined(veda_pcc_otype))
     & veda_local_handler_registered(veda_pcc_otype) then {
    // NEW: redirect into the SAME compartment's own bounds, at its own
    // registered entry point -- PCC is NOT widened at all.
    veda_pcc_base = veda_mepcc_base;
    veda_pcc_length = veda_mepcc_length;
    redirect_pc(veda_local_handler_entry(veda_pcc_otype));
  } else {
    veda_pcc_base = zeros();                         // existing fallback, unchanged
    veda_pcc_length = VEDA_PCC_UNBOUNDED;
    redirect_pc(mtvec);
  };
  veda_pcc_otype = UNSEALED_OTYPE;                    // note: see "found during design" below
}
```

**Hand-off out of the local handler needs no new instruction.** The handler, running bounded to its
own compartment's own bounds, has exactly the primitives every other compartment already has:
`OCReturn` through a sentry to hand control anywhere it was given a sentry for (the kernel, its own
ordinary entry point to retry, wherever); or it can simply fault again (illegal instruction, running
off its own bound, another real error) -- which re-enters this exact same chokepoint, increments the
SAME quarantine counter again, and after the third such failure the compartment is quarantined and
every subsequent trap falls through to the ordinary global `mtvec` path automatically. No "resume
with modified registers" primitive is built in this pass -- CHERIoT's own richer form (§3.2.6) is a
real, separately-scoped future extension (see "Not built"), not required for the core guarantee.

## Composition with VEDA_TRAP_QUARANTINE -- the real danger found while designing, not after

**A local-handler mechanism that redirects unconditionally on every trap is itself a new
repeated-trap DoS vector**, potentially defeating the very mechanism this project built earlier
today: an attacker (or a genuinely buggy handler) that faults immediately upon entering its own
handler would loop hardware-redirect after hardware-redirect forever, since this redirect never goes
through `VEDA_OCINVOKE`'s own quarantine check (it is a hardware-internal PC redirect, not a fresh
software-issued invoke instruction) -- the exact class of gap `VEDA_TRAP_QUARANTINE` was built to
close. Found and fixed at design time, not shipped and found later: the redirect is explicitly gated
on `not(veda_trap_tracker_is_quarantined(veda_pcc_otype))`, and every redirect still runs through the
UNCONDITIONAL `record_fault` call above it. This means a broken local handler quarantines itself
within 3 real faults exactly like ordinary compartment code, and the FOURTH trap correctly falls
through to the safe, always-available global `mtvec` path -- local recovery is a privilege a
compartment keeps only while behaving within its own quarantine budget, never an unconditional
escape hatch.

## Real correction found while designing (not assumed correct after writing it)

The pseudocode above still resets `veda_pcc_otype = UNSEALED_OTYPE` unconditionally on every trap,
matching `VEDA_TRAP_QUARANTINE`'s own existing behavior -- but that is now WRONG for the local-handler
redirect path specifically: the handler is running with the SAME compartment's own bounds, so its
own identity for quarantine-counting purposes must stay `veda_pcc_otype` (not reset to `UNSEALED_OTYPE`),
otherwise a fault INSIDE the handler itself would be attributed to the wrong (unsealed) bucket,
silently defeating the very quarantine-composition guarantee described above. Fix: `veda_pcc_otype`
is reset to `UNSEALED_OTYPE` only on the EXISTING fallback (global) path; the local-handler redirect
path leaves `veda_pcc_otype` unchanged, since it never actually left that compartment's identity.

## Explicit, honest scope limits

- **No "resume with modified registers"** -- only clean-exit-via-`OCReturn` or "fault again and let
  quarantine escalate to the global path" are available outcomes this pass. CHERIoT's richer
  resume-in-place semantics is a real, separately-scoped future extension, not required to close the
  core CHERIoT-parity gap (bounded-privilege recovery) this design exists to close.
- **Registration is compile/setup-time software policy, not verified against any external
  attestation** -- a compartment can point its own handler anywhere within its own bounds; this
  project has no code-signing/attestation layer at any layer today, so this is consistent with every
  other Veda-Core trust boundary (a compartment is already trusted with everything inside its own
  bounds).
- **Single-hart only**, matching every other Veda-Core mechanism in this line.
- **Not a general theory of fault recovery** -- closes specifically the "buggy/malicious local
  handler cannot exceed the faulting compartment's own rights" gap CHERIoT names and Veda-Core
  lacked; does not attempt supply-chain auditing, micro-reboot orchestration, or scheduler-level
  policy, all of which remain software-layer concerns this mechanism is a primitive for, not a
  replacement of.

## Verification plan

Sail-first. Positive: register a handler, drive a real fault, confirm PC lands at the registered
entry with `veda_pcc_base`/`_length` exactly equal to the pre-fault bounds (not unbounded, not some
other region) via CSR readback; handler exits cleanly via a pre-minted sentry `OCReturn`; confirm the
compartment's own quarantine count decayed to 0 by that clean exit (reusing `VEDA_TRAP_QUARANTINE`'s
own already-verified decay path). Negative 1: no handler registered for an otype -- confirm existing
global-fallback behavior (`mtvec`, unbounded PCC) is completely unchanged, zero regression. Negative
2: a handler that faults repeatedly -- confirm exactly 3 local-handler redirects, then the 4th trap
falls through to the global path (`mtvec`, unbounded PCC), proving the composition guard is real, not
merely asserted. Negative 3 (confused-deputy guard): attempt to register an entry address outside the
current compartment's own bounds -- confirm hard-trap, no table write occurs. Mutation tests: drop
the quarantine gate on the redirect (confirm negative-2's own test now shows unbounded redirect
looping instead of falling through at 3); drop the `veda_pcc_otype`-preservation fix (confirm a fault
inside the handler gets mis-attributed, detectable via the same decay/quarantine bookkeeping already
built). Full regression required after every change, matching this project's own standing discipline.
