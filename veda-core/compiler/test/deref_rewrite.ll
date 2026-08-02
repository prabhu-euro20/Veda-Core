; Toolchain Milestone 9: real dereference rewrite -- a 64-bit store/load
; whose ADDRESS is itself a tracked, object-relative pointer must be
; redirected through real veda_rt_ocs_d/veda_rt_ocl_d, not left as an
; ordinary memory access.
; RUN: opt -load-pass-plugin=%veda_shadow_plugin -passes=veda-shadow-prop -S %s | FileCheck %s

declare ptr @veda_malloc_raw(i64, ptr)

define i64 @test_deref(i64 %sz) {
entry:
  %oid_slot = alloca i32
  %p = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot)
  store i64 42, ptr %p
  %v = load i64, ptr %p
  ret i64 %v
}

; CHECK: %veda.ocl.scratch = alloca i64
; CHECK: %p = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot)
; CHECK-NEXT: %oid = load i32, ptr %oid_slot
; The store is gone entirely, replaced by a real veda_rt_ocs_d call using
; (object_id, offset-from-kVedaNullBase, raw 64-bit value).
; CHECK-NOT: store i64 42, ptr %p
; CHECK: [[OFF1:%[0-9]+]] = ptrtoint ptr %p to i64
; CHECK-NEXT: [[SUB1:%[0-9]+]] = sub i64 [[OFF1]], 4096
; CHECK-NEXT: call void @veda_rt_ocs_d(i32 %oid, i64 [[SUB1]], i64 42)
; The load is gone entirely, replaced by a real veda_rt_ocl_d call plus a
; plain (untracked, real-address) reload of the scratch out-param slot.
; CHECK-NOT: load i64, ptr %p
; CHECK: [[OFF2:%[0-9]+]] = ptrtoint ptr %p to i64
; CHECK-NEXT: [[SUB2:%[0-9]+]] = sub i64 [[OFF2]], 4096
; CHECK-NEXT: call void @veda_rt_ocl_d(i32 %oid, i64 [[SUB2]], ptr %veda.ocl.scratch)
; CHECK-NEXT: [[V:%[0-9]+]] = load i64, ptr %veda.ocl.scratch
; CHECK-NEXT: ret i64 [[V]]
