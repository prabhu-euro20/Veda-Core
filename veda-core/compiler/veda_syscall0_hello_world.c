// Toolchain Milestone "Syscall-0" Step 2 (task #298): a REAL, compiled C
// program, built through the UNMODIFIED Veda-Core toolchain (the exact
// same -fpass-plugin pipeline every other compiler/ demo already uses),
// performing a real write()+exit() through hand-written syscall shims
// (veda_syscall0_shim.S) and the KERNEL ecall dispatcher already proven
// in sail_tests/vc_syscall0_kernel.S (Task #297, 65/65 regression).
//
// Design decision 1, empirically forced: sys_write/sys_exit are declared
// with ONLY scalar parameters, never a pointer parameter. Confirmed by
// directly reading VedaShadowPropagation.cpp's rewriteSignatures:
// `if (F.isDeclaration() ...) continue;` (VedaShadowPropagation.cpp:507)
// -- the pass only rewrites (and only knows how to call-site-fix-up)
// functions DEFINED WITH A BODY in a pass-processed translation unit. A
// hand-written .S function is permanently "just a declaration" from the
// pass's own point of view -- there is no real mechanism for it to ever
// receive an auto-appended shadow Object_ID parameter.
//
// Design decision 2, found the hard way via a real runtime trap
// (PURECAP_VIOLATION, cause=0x07) while building this file:
// hello_world_thread does NOT call veda_rt_init/veda_malloc_raw itself,
// and does NOT take a pointer parameter either. Both veda_compiler_rt.c
// and runtime/veda_rt.c are compiled WITHOUT -fpass-plugin in every
// established build script in this repo (confirmed) -- their own
// internal bookkeeping (g_in_use[]/etc.) is therefore always ordinary,
// un-instrumented C, which a live OCInvoke-narrowed compartment's
// purecap enforcement correctly hard-traps on. The fix: the entry point
// (veda_syscall0_kernel_entry.S) calls veda_rt_init/veda_malloc_raw and
// writes the real message bytes itself, BEFORE OCInvoke narrows PCC --
// mirroring veda_global_protect_entry.S's own already-established
// pre-OCInvoke veda_rt_init_globals() call, for the identical reason
// ("purecap enforcement is not yet active at that point"). This function
// receives the already-allocated Object_ID as a plain scalar argument --
// deliberately NOT a pointer, which also sidesteps rewriteSignatures
// entirely (no pointer parameter, no return-shadow -> this function's
// own signature is never touched by the pass at all).
extern long sys_write(int fd, unsigned int oid, unsigned long offset,
                       unsigned long len);
extern void sys_exit(long status) __attribute__((noreturn));

__attribute__((veda_compartment))
long hello_world_thread(unsigned int msg_oid) {
  long n = sys_write(1, msg_oid, 0, 14);
  if (n != 14)
    sys_exit(1);

  sys_exit(0);
  return 0; // unreachable
}
