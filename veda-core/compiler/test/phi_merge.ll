; Toolchain Milestone 8, test case 4: phi-node control-flow merge of two
; DIFFERENT tracked objects.
; RUN: opt -load-pass-plugin=%veda_shadow_plugin -passes=veda-shadow-prop -S %s | FileCheck %s

declare ptr @veda_malloc_raw(i64, ptr)

define ptr @test_phi(i64 %sz, i1 %cond) {
entry:
  %oid_slot1 = alloca i32
  %p1 = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot1)
  br i1 %cond, label %bb1, label %merge

bb1:
  %oid_slot2 = alloca i32
  %p2 = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot2)
  br label %merge

merge:
  %p = phi ptr [ %p1, %entry ], [ %p2, %bb1 ]
  ret ptr %p
}

; CHECK: %p1 = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot1)
; CHECK-NEXT: %oid = load i32, ptr %oid_slot1
; CHECK: %p2 = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot2)
; CHECK-NEXT: %oid1 = load i32, ptr %oid_slot2
; CHECK: merge:
; CHECK-NEXT: %p.shadow = phi i32 [ %oid, %entry ], [ %oid1, %bb1 ]
; CHECK-NEXT: %p = phi ptr [ %p1, %entry ], [ %p2, %bb1 ]
; CHECK-NEXT: call void @veda_shadow_attach(ptr %p, i32 %p.shadow)
