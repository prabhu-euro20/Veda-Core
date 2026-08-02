; Toolchain Milestone 9: `icmp eq/ne ptr %X, null` against a TRACKED
; pointer must compare shadow Object_IDs, not raw pointer bit patterns --
; see the file header for why raw comparison is meaningless under the
; offset-token representation.
; RUN: opt -load-pass-plugin=%veda_shadow_plugin -passes=veda-shadow-prop -S %s | FileCheck %s

declare ptr @veda_malloc_raw(i64, ptr)

define i32 @test_null_check(i64 %sz) {
entry:
  %oid_slot = alloca i32
  %p = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot)
  %isnull = icmp eq ptr %p, null
  br i1 %isnull, label %yes, label %no
yes:
  ret i32 0
no:
  ret i32 1
}

; CHECK: %p = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot)
; CHECK-NEXT: %oid = load i32, ptr %oid_slot
; CHECK-NOT: icmp eq ptr %p, null
; CHECK: icmp eq i32 %oid, -1
