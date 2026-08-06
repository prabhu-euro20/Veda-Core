# Veda-Core RTL Minimal OS Kernel Milestone C Results — a Real Cooperative Scheduler

**Date:** 2026-08-06
**Scope:** RTL mirror of the Sail-side minimal OS kernel Milestone C
(`veda-core/MILESTONE_C_RESULTS.md`) — a real, two-thread cooperative round-robin scheduler,
proving Milestones A (TSC + `OSpecialRW` selector) and B (`CSealEntry`/`OCRETURN`) compose into
the actual OS-kernel pattern in RTL too. Blocked until this session by a real, pre-existing gap
(RTL had never implemented `ecall`, the scheduler's own yield trigger) — closed first as its own
prerequisite, `MILESTONE_23_RESULTS.md` ("real ECALL support"), then this mirror was built
directly on top of it.

## What was built

No new RTL hardware logic beyond Milestone 23's own 4-line `ecall` diff — every instruction this
milestone needs (`OCInvoke`, `OCRETURN`, `CSealEntry`, `OSpecialRW`, `OCL.D`/`OCS.D`, `ecall`) was
already implemented and already proven correct in isolation. This is a pure software-integration
test: `rtl/sim/veda_smoke_m23_scheduler.S` + `tb_veda_smoke_m23_scheduler.sv`, a direct RTL port
of the already-verified Sail source (`sail_tests/vc_scheduler_cooperative_yield.S`).

Four compartments (THREAD_A/THREAD_B/SWITCHER/SCHEDULER), same 4-yield (2 round-trip)
verification target, same final assertions (each thread's own counter incremented exactly twice,
live PCC-bounds fidelity on each thread's second visit, TSC round-trip fidelity every cycle).
Object_IDs 110-122 (13 total) — personally grepped every existing `rtl/sim/*.S` file's own usage
(now including Milestone 23's own two new tests' `100`/`101`/`102`) before picking: `110-199`
confirmed completely free.

All three real bugs the Sail side found during its own development were applied directly, since
each was independently re-confirmed to hold identically in this RTL:

1. **Ordinary `lw`/`sw` blocked inside any live `OCInvoke` compartment, regardless of
   `veda_purecap`** — confirmed via direct read of `veda_core.tlv:2724-2725`
   (`$veda_purecap_violation = ($is_load||$is_store) && ($veda_mode[0] ||
   ($veda_pcc_length != 16'hFFFF))`, an unconditional OR, identical to Sail's Milestone 19 rule).
   SCHEDULER (itself `OCInvoke`-entered) uses `OCL.D`/`OCS.D` for `thread_index`; SWITCHER (runs
   unbounded) uses ordinary `lw`/`sw` freely.
2. **Atomic `OCA`+`CSealEntry`+`OCRETURN` restore, not `csrw`+`mret`** — directly portable: RTL's
   `OCInvoke`/`OCRETURN` (funct7 `0010010`/`0010110`) both narrow `veda_pcc_base`/`_length` to
   `cs1`'s Base/Length and jump in the same instruction, confirmed identical semantics to the
   already-verified Sail mechanism during Milestone 23's own design-review pass.
3. **`mepc += 4` before use as a resume address** — RTL's `$mepc` capture has no auto-advance
   either (confirmed directly, `veda_core.tlv:2369-2380`), so the switcher's trap handler needed
   the identical `addi` fix immediately after reading `mepc`.

## Verification

Passed on the **first run**, no debugging needed — every lesson the Sail side learned the hard
way (three real, empirically-found bugs) was already known and correctly ported before this RTL
version ever ran, and the funct7/opcode/descriptor-packing conventions between Sail and RTL held
perfect parity throughout (independently confirmed during Milestone 23's own research pass:
`OCInvoke`=`0010010`, `OCRETURN`=`0010110`, `CSealEntry`=`0010101`, `OCA`=`0001010`, `CSeal`=
`0010000`, `OSpecialRW`=`0010011`, `OCL.D`/`OCS.D`=Custom-0/funct3=`011`/funct7=`0000000`/
`0000001` — all identical to the values already used in the Sail-verified test).

```
$ bash run_veda_smoke_test.sh
...
THREAD_A counter (must be 2): x20=2
THREAD_B counter (must be 2): x21=2
THREAD_A bounds fidelity (must be 1): x22=1
THREAD_B bounds fidelity (must be 1): x26=1
TSC round-trip fidelity (must be 1): x9=1
overall sentinel (must be 0x600D): x27=0x600d

*** TEST PASSED *** (a real 2-thread cooperative round-robin scheduler -- 4 yields via real
ECALL, TSC swap via OSpecialRW, SCHEDULER invoked via OCInvoke and returning via OCRETURN
through a CSealEntry-minted sentry -- proves Milestones A/B/23 compose into the real
OS-kernel pattern in RTL, RTL mirror of Sail-side Milestone C)
...
41/41 (38 pre-existing + Milestone 23's own 3 new tests) TEST PASSED
```

**41/41** RTL smoke regression, **51/51** ACT4 RV64I conformance, zero regressions on either.

## Not yet built

Per the Sail-side plan's own explicit scope, unchanged here: real fault recovery for the
`unexpected_trap`/guard path, full GPR context save, preemptive scheduling, more than 2 threads,
priorities, message queues/event channels/futexes, and the allocator are all still out of scope.
This milestone closes the entire "prove the minimal-OS-kernel primitives compose, in both models"
goal this initiative was named for.
