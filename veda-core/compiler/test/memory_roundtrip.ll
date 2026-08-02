; Toolchain Milestone 8, test case 2: memory round-trip (store then load)
; through an UNTRACKED real address.
;
; %slot is a local alloca, not a function parameter -- a real, deliberate
; design point (Milestone 9's own real Phase-2 discovery, not an original
; Milestone 8 assumption): a pointer PARAMETER always gets a shadow
; companion appended by Phase A's own signature rewrite (needed for the
; genuinely-tracked-parameter case, call_argument.ll), so a parameter
; always has *some* entry in the pass's internal shadow map, even if that
; entry is only ever the default/untracked sentinel at every real call
; site. Phase 2's dereference-rewrite rule (Milestone 9) treats "any
; shadow-map entry" as "this address is object-relative, redirect through
; real OCL.D/OCS.D" -- correct for a real Veda-Core program (where a given
; pointer variable is consistently either object-derived or not, never
; mixed), but it means a parameter is the wrong shape for testing the
; "genuinely, provably untracked real address" path specifically. A local
; alloca is unambiguous: Phase A's parameter-shadow seeding only ever
; touches function PARAMETERS, so an alloca can never receive a shadow
; entry at all, exercising exactly the intended untracked-address /
; Milestone 8 fallback behavior with zero ambiguity.
; RUN: opt -load-pass-plugin=%veda_shadow_plugin -passes=veda-shadow-prop -S %s | FileCheck %s

declare ptr @veda_malloc_raw(i64, ptr)

define ptr @test_roundtrip(i64 %sz) {
entry:
  %slot = alloca ptr
  %oid_slot = alloca i32
  %p = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot)
  store ptr %p, ptr %slot
  %p2 = load ptr, ptr %slot
  ret ptr %p2
}

; CHECK: %p = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot)
; CHECK-NEXT: %oid = load i32, ptr %oid_slot
; CHECK: store ptr %p, ptr %slot
; CHECK-NEXT: call void @veda_shadow_store(ptr %slot, i32 %oid)
; CHECK: %p2 = load ptr, ptr %slot
; CHECK-NEXT: %p2.shadow = call i32 @veda_shadow_load(ptr %slot)
; CHECK-NEXT: call void @veda_shadow_attach(ptr %p2, i32 %p2.shadow)
