.section .text

# Toolchain Milestone "Syscall-0" Step 2 (task #298): hand-written syscall
# shims, deliberately scalar-only ABI (see veda_syscall0_hello_world.c's
# own header comment for the full, empirically-confirmed reason a
# pointer-parameter shim cannot work at all with this pass). Both
# functions are pure leaves -- neither calls anything else, neither
# touches the stack -- so no `ra` spill, no SSC/C15 concern, safe to call
# from inside a live OCInvoke-narrowed compartment exactly as-is.
#
# Real Linux RV64 syscall NUMBERS (__NR_write=64, __NR_exit=93), but a
# deliberate, already-agreed divergence from real Linux's own register
# layout: sys_write's own C-level signature here
# (int fd, u32 oid, u64 offset, u64 len) is designed to match the KERNEL
# ecall ABI (sail_tests/vc_syscall0_kernel.S, Task #297) register-for-
# register -- a0=fd, a1=Object_ID, a2=offset, a3=count, a7=syscall number
# -- so no remapping is needed at all, just append a7 and ecall.

# long sys_write(int fd /*a0*/, u32 oid /*a1*/, u64 offset /*a2*/, u64 len /*a3*/)
.global sys_write
sys_write:
    li   a7, 64
    ecall
    ret

# void sys_exit(long status /*a0*/) -- noreturn: the KERNEL's own
# do_sys_exit halts the simulator directly via RVMODEL_HALT_PASS/FAIL,
# never mret's back here. The trailing loop is a defensive fallback only
# (matches this file's own scalar-only-leaf simplicity -- no real code
# path is expected to ever reach it).
.global sys_exit
sys_exit:
    li   a7, 93
    ecall
1:  j 1b
