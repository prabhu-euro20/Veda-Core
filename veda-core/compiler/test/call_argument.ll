; Toolchain Milestone 8, test case 3: function-call argument passing.
; RUN: opt -load-pass-plugin=%veda_shadow_plugin -passes=veda-shadow-prop -S %s | FileCheck %s

declare ptr @veda_malloc_raw(i64, ptr)

define ptr @callee(ptr %in) {
entry:
  ret ptr %in
}

define ptr @caller(i64 %sz) {
entry:
  %oid_slot = alloca i32
  %p = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot)
  %res = call ptr @callee(ptr %p)
  ret ptr %res
}

; The callee gains a trailing i32 shadow parameter and attaches it to its
; own pointer argument at entry.
; CHECK: define ptr @callee(ptr %in, i32 %in.shadow)
; CHECK-NEXT: entry:
; CHECK-NEXT: call void @veda_shadow_attach(ptr %in, i32 %in.shadow)
; CHECK-NEXT: ret ptr %in

; The call site passes the real, computed shadow (%oid) as the extra
; argument, not the placeholder sentinel.
; CHECK: %p = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot)
; CHECK-NEXT: %oid = load i32, ptr %oid_slot
; CHECK: %res = call ptr @callee(ptr %p, i32 %oid)
