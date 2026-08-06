// Veda-Core C-callable cooperative-scheduling API.
//
// A real, direct C-level exposure of the switcher/scheduler mechanism
// already proven twice as hand-assembled RISC-V (sail_tests/
// vc_scheduler_cooperative_yield.S, 53/53; rtl/sim/veda_smoke_m23_scheduler.S,
// 41/41) -- every OCInvoke/OCRETURN/OSpecialRW/TSC-swap step this library
// performs is the identical mechanism those tests already verify, not a
// new or simplified one.
//
// SCOPE, STATED PLAINLY (read before using): this is a COOPERATIVE-ONLY,
// exactly-2-static-thread, non-preemptive proof-of-mechanism -- NOT a
// production scheduler and NOT a general-purpose OS API. There is no
// timer interrupt, no preemption, no dynamic thread creation (threads are
// declared by the caller up front, matching CHERIoT RTOS's own real,
// build-time-static thread-registration convention -- verified directly
// against github.com/CHERIoT-Platform/cheriot-rtos before this design was
// finalized), no allocator, and no full GPR context save (only a thread's
// own PC + PCC bounds survive a yield -- a thread's persistent state MUST
// live in `static`/global C storage, never a local variable that might be
// register-resident across a veda_yield() call). If a registered thread
// never calls veda_yield(), the whole program hangs forever -- there is
// no timer to force it, by design, matching this project's own explicit,
// honestly-named deferred-work list.
//
// Toolchain constraint this design works around (TOOLCHAIN_MILESTONE_7_
// RESULTS.md): clang's own driver rejects the xveda ISA extension string,
// so no Veda-Core CUSTOM-mnemonic instruction can appear in a file clang
// compiles -- every one lives in veda_sched_asm.S, assembled separately
// via llvm-mc -mattr=+xveda, exactly like veda_rt_asm.S already does.
// `ecall` itself is a standard base-ISA instruction (not a Veda-Core
// extension), so veda_yield() below is safe as ordinary clang inline asm.
//
// A SECOND, more fundamental constraint, found empirically (clang -S
// inspection, not assumed) while building this library: THREAD BODIES
// CANNOT BE ORDINARY COMPILER-GENERATED C FUNCTIONS. Standard RV64 ABI
// requires a function to save any callee-saved register it uses in its
// own prologue -- an ordinary `sd`/`ld` store/load, which Milestone 19's
// purecap rule hard-traps unconditionally inside any live, narrowly
// OCInvoke/OCRETURN-bound compartment (confirmed: a trivial one-line
// loop body already emits a prologue `sd s4, 8(sp)` register spill at
// -O1; a plain `static` counter is worse, touching memory every
// iteration; a file-scope "global register variable" crashes this LLVM
// build's RISC-V backend outright). A thread's entry function must
// therefore be hand-written assembly containing ZERO ordinary memory
// traffic -- exactly the discipline sail_tests/
// vc_scheduler_cooperative_yield.S's own thread bodies already use
// (persistent state lives only in dedicated GPRs, e.g. x20/x21, which
// the register FILE itself preserves across every OCInvoke/OCRETURN --
// no explicit save/restore needed, since compartment switches narrow
// PCC only, never clear GPRs). `veda_thread_fn` below points at such a
// hand-verified assembly label, not an arbitrary C function.

#ifndef VEDA_SCHED_H
#define VEDA_SCHED_H

#include <stdint.h>

// Exactly 2 for this first pass -- true N-way generalization (N-slot
// round-robin, N-entry TSC-swap table) is real, separate, deferred work,
// not attempted here.
#define VEDA_MAX_THREADS 2

typedef void (*veda_thread_fn)(void);

// One thread's own compile-time-known code footprint. `code_length` is
// the caller's own explicit, informed choice of how many bytes of code
// space to bound this thread's compartment to -- the exact same real
// judgment call the original hand-assembled test's own `Length=0x0100`
// already required a human to make (not something this library can
// safely auto-compute without linker-script cooperation, itself real,
// separate future work).
typedef struct {
  veda_thread_fn entry;
  uint32_t code_length;
} veda_thread_t;

// Registers exactly `count` (must be <= VEDA_MAX_THREADS) threads, then
// runs the real cooperative scheduler -- installing mtvec, entering
// thread 0, and round-robining every subsequent veda_yield() -- until
// `max_yields` total yields have occurred, then returns the real count
// of yields that occurred. Does NOT itself judge success or failure --
// the caller inspects its own threads' `static` state after this
// returns, exactly matching how the original .S tests assert on their
// own persistent counter registers.
uint32_t veda_scheduler_start(const veda_thread_t *threads, int count,
                               uint32_t max_yields);

// Voluntary yield -- a real `ecall`, the identical mechanism the proven
// .S tests use. Safe to call from any registered thread's own entry
// function. Only `static`/global state is guaranteed to survive the
// call; anything else the compiler might have kept live in a register is
// not.
static inline void veda_yield(void) { __asm__ volatile("ecall" ::: "memory"); }

#endif // VEDA_SCHED_H
