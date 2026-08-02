; Toolchain Milestone 8, bonus test (beyond the plan's own 4 named cases,
; added for real rigor): a loop-carried, CYCLIC pointer phi -- a
; linked-list-traversal shape, where the phi's own shadow value is needed
; (as an operand to @veda_shadow_store, to persist it before the reload
; that produces %next) before the phi's own incoming-edge list is fully
; known on a single top-down pass. Proves the two-phase
; placeholder-then-fill algorithm genuinely handles the hard, cyclic case,
; not just the simple, non-cyclic one already covered by phi_merge.ll.
; RUN: opt -load-pass-plugin=%veda_shadow_plugin -passes=veda-shadow-prop -S %s | FileCheck %s

declare ptr @veda_malloc_raw(i64, ptr)

define void @test_loop_phi(i64 %sz) {
entry:
  %oid_slot = alloca i32
  %head = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot)
  %slot = alloca ptr
  br label %loop

loop:
  %node = phi ptr [ %head, %entry ], [ %next, %loop ]
  store ptr %node, ptr %slot
  %next = load ptr, ptr %slot
  br label %loop
}

; CHECK: %head = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot)
; CHECK-NEXT: %oid = load i32, ptr %oid_slot
; CHECK: loop:
; CHECK-NEXT: %node.shadow = phi i32 [ %oid, %entry ], [ %next.shadow, %loop ]
; CHECK-NEXT: %node = phi ptr [ %head, %entry ], [ %next, %loop ]
; CHECK-NEXT: call void @veda_shadow_attach(ptr %node, i32 %node.shadow)
