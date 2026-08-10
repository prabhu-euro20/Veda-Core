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

; The callee gains a trailing i32 shadow parameter (for its pointer
; PARAMETER) AND, since it also RETURNS a pointer, a further trailing
; return-shadow out-param (Toolchain Milestone 20) -- attaches the param
; shadow at entry, and writes that same shadow through the return-shadow
; out-param immediately before returning (the returned value IS %in
; itself, so its shadow IS %in.shadow).
; CHECK: define ptr @callee(ptr %in, i32 %in.shadow, ptr %ret.shadow.out)
; CHECK-NEXT: entry:
; CHECK-NEXT: call void @veda_shadow_attach(ptr %in, i32 %in.shadow)
; CHECK-NEXT: store i32 %in.shadow, ptr %ret.shadow.out
; CHECK-NEXT: ret ptr %in

; The call site passes the real, computed shadow (%oid) as the extra
; argument, not the placeholder sentinel.
; CHECK: %p = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot)
; CHECK-NEXT: %oid = load i32, ptr %oid_slot

; @caller ALSO returns a pointer, so it gains its own trailing
; return-shadow out-param and a lazily-created scratch slot to receive
; @callee's return-shadow write-back through -- then chains that value on
; into @caller's OWN return-shadow out-param, proving the mechanism
; composes correctly across nested/chained function-return boundaries, not
; just a single call depth.
; CHECK: %res = call ptr @callee(ptr %p, i32 %oid, ptr %veda.ret.shadow.scratch)
; CHECK-NEXT: %res.retshadow = load i32, ptr %veda.ret.shadow.scratch
; CHECK: store i32 %res.retshadow, ptr %ret.shadow.out
