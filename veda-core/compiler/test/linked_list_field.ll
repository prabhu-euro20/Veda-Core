; Toolchain Milestone 9: storing/loading a TRACKED POINTER VALUE into/from
; a TRACKED ADDRESS -- the real "node->next = other_node" linked-list
; pattern, needing the synthetic (object,offset)-keyed shadow persistence
; since the target slot has no real machine address.
; RUN: opt -load-pass-plugin=%veda_shadow_plugin -passes=veda-shadow-prop -S %s | FileCheck %s

declare ptr @veda_malloc_raw(i64, ptr)

define ptr @test_linked_field(i64 %sz) {
entry:
  %oid_slot1 = alloca i32
  %node = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot1)
  %oid_slot2 = alloca i32
  %next_node = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot2)
  store ptr %next_node, ptr %node
  %loaded = load ptr, ptr %node
  ret ptr %loaded
}

; The store's own raw payload is next_node's own raw offset-token value
; (its ptrtoint), written via real OCS.D into node's own object.
; CHECK: %node = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot1)
; CHECK-NEXT: %oid = load i32, ptr %oid_slot1
; CHECK: %next_node = call ptr @veda_malloc_raw(i64 %sz, ptr %oid_slot2)
; CHECK-NEXT: %oid1 = load i32, ptr %oid_slot2
; CHECK: call void @veda_rt_ocs_d(i32 %oid, i64 {{%[0-9]+}}, i64 {{%[0-9]+}})
; The stored VALUE is itself tracked -- its shadow (%oid1, next_node's own
; object_id) is persisted keyed by a synthetic (node_oid,offset) key,
; since the target slot has no real machine address.
; CHECK: call void @veda_shadow_store(ptr {{%[0-9]+}}, i32 %oid1)
; The load is redirected through real OCL.D on the same real object.
; CHECK: call void @veda_rt_ocl_d(i32 %oid, i64 {{%[0-9]+}}, ptr %veda.ocl.scratch)
; The reloaded pointer's own shadow is correctly recovered via the SAME
; synthetic key scheme, and attached to the final result.
; CHECK: %loaded.shadow = call i32 @veda_shadow_load(ptr {{%[0-9]+}})
; CHECK-NEXT: call void @veda_shadow_attach(ptr {{%[0-9]+}}, i32 %loaded.shadow)
