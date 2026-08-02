; Toolchain Milestone 8, test case 1: straight-line pointer arithmetic.
; RUN: opt -load-pass-plugin=%veda_shadow_plugin -passes=veda-shadow-prop -S %s | FileCheck %s

declare ptr @veda_malloc_raw(i64, ptr)

define ptr @test_straightline(i64 %sz) {
entry:
  %oid_slot = alloca i32
  %p = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot)
  %q = getelementptr i8, ptr %p, i64 8
  ret ptr %q
}

; CHECK: %p = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot)
; CHECK-NEXT: %oid = load i32, ptr %oid_slot
; CHECK-NEXT: call void @veda_shadow_attach(ptr %p, i32 %oid)
; CHECK: %q = getelementptr i8, ptr %p, i64 8
; CHECK-NEXT: call void @veda_shadow_attach(ptr %q, i32 %oid)
