# Toolchain Milestone 15: Compiler-Pass-Sized Capability Table

## Problem

`TOOLCHAIN_MILESTONE_13_RESULTS.md`'s own "Not yet built" section named a real, honest gap: the
in-memory capability table (`g_veda_global_cap_table`) that caches every in-scope global's own minted
capability was a fixed 16-slot (256-byte) upper bound, hand-declared in `runtime/veda_rt.c`, unrelated to
any one program's own real global count. `TOOLCHAIN_MILESTONE_13_DESIGN.md` had already named the correct
fix as an open risk: "exactly as many slots as the tuple table has entries, sized by the compiler pass
itself, no separate policy needed" — but left it unimplemented and untested.

## Design

`VedaShadowPropagation.cpp`'s Phase B1 already emits `__veda_global_table_meta`/`__veda_global_table_count`
as compiler-generated `GlobalVariable`s, exactly sized to `Rows.size()` (the real, compile-time-known count
of in-scope globals for that module). This milestone applies the identical, already-proven mechanism to a
second array:

- **`g_veda_global_cap_table`**: now emitted directly by Phase B1 as a `[Rows.size()*16 x i8]`
  zero-initialized `GlobalVariable` (`ConstantAggregateZero`, not a `ConstantArray` — this array is
  populated at *runtime* via `OCS.C`, unlike the compile-time-initialized metadata table).
- **`__veda_global_cap_table_bytes`**: a new companion `i64` constant carrying the table's real byte size,
  mirroring `__veda_global_table_count`'s own role — needed because the hand-written entry point
  (`veda_global_protect_entry.S`) cannot read an LLVM `GlobalVariable`'s byte size directly the way C code
  can; it reads this constant instead.
- **`runtime/veda_rt.h`**: `g_veda_global_cap_table` becomes an incomplete-array-type `extern` (`uint8_t
  g_veda_global_cap_table[]`) — its real size is decided by whichever definition (pass-emitted or weak
  fallback) the linker resolves. Confirmed safe: no C code in this codebase does
  `sizeof(g_veda_global_cap_table)` (checked by grep before making this change).
- **`runtime/veda_rt.c`**: the old strong, fixed-256-byte definition is replaced with a `__attribute__((weak))`
  1-slot (16-byte) fallback for both `g_veda_global_cap_table` and `__veda_global_cap_table_bytes` — the
  identical real C/ELF weak-symbol mechanism `__veda_global_table_meta`/`__veda_global_table_count` already
  rely on (Phase B1's strong emission wins when present; the harmless minimal default is used when a
  program references the symbol without the pass having found any qualifying global).
- **`veda_global_protect_entry.S`**: the CAP_TABLE_REGION's `ODT-Populate` `Length` field, previously a
  hardcoded `0x0100`, is now computed at runtime: `la`+`ld` loads `__veda_global_cap_table_bytes`, shifted
  into the descriptor's Length field and OR'd with the unchanged `Perms=0x000C` (Load|Store).

## Verification

Rebuilt the pass plugin and reran `run_veda_global_protect_test.sh` (2 real globals, `g_lower[4]`/
`g_upper[4]`). Confirmed directly in the generated LLVM IR (`/tmp/global_demo_positive.ll`), not assumed:

```
@__veda_global_table_count = local_unnamed_addr constant i64 2
@g_veda_global_cap_table = local_unnamed_addr global [32 x i8] zeroinitializer
@__veda_global_cap_table_bytes = local_unnamed_addr constant i64 32
```

32 bytes (2 globals × 16), not the old fixed 256 — the table is now genuinely exactly-sized. Both the
positive (in-bounds, checkable result 113) and negative (deliberate cross-global overflow, exact expected
`mcause=0x18`/`mtval=0x141` `VEDA_CAUSE_BOUNDS_VIOLATION`) runs still pass, confirming the smaller table
and the runtime-computed `ODT-Populate` `Length` are both correct, not just "large enough by coincidence."

**Full regression, zero regressions**:
- `compiler/run_veda_global_protect_test.sh`: PASS (the changed path itself).
- `compiler/run_veda_demo_tests.sh` (2/2) and `runtime/run_veda_rt_tests.sh` (2/2): both link `veda_rt.c`
  with **zero** module-scope globals — the real, direct exercise of the new weak-fallback path (Phase B1
  emits nothing, `g_veda_global_cap_table[16]`/`__veda_global_cap_table_bytes=16` weak defaults are used
  instead). Both still pass, confirming the fallback works, not just the pass-emitted path.
- `compiler/run_veda_alloca_protect_test.sh`, `run_veda_sched_demo_test.sh`,
  `run_veda_compartment_test.sh`, `run_veda_compartment_nested_test.sh`,
  `compiler/run_veda_sched_global_combo_test.sh` (Toolchain Milestone 14): all still pass, confirming zero
  disturbance to any unrelated toolchain suite.

No Sail or RTL file touched — this is a compiler/runtime-layer-only fix, matching every prior Toolchain
Milestone's own scope discipline.

## Not yet built

- The remaining, genuinely distinct `TOOLCHAIN_MILESTONE_13_RESULTS.md` "Not yet built" items — extern
  globals, non-`veda_compartment`-attributed-function accesses — are untouched by this milestone; it closes
  only the specific table-sizing gap that document named.
