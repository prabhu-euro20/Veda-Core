// Real, compiled C driver for the Veda-Core cooperative scheduler.
// Proves the switcher/scheduler/TSC mechanism -- already verified twice
// as hand-assembled RISC-V -- is genuinely reachable and controllable
// from ordinary, compiled C, not just from a hand-written test program.
//
// See runtime/veda_sched.h for the real, honestly-stated scope: exactly
// 2 static threads, cooperative-only, no preemption, and (found this
// session) thread BODIES must be hand-written assembly with zero
// ordinary memory traffic -- see veda_sched_demo_threads.S -- while the
// scheduler/switcher/init MECHANISM itself is genuinely C-callable.

#include "../runtime/veda_sched.h"

extern void veda_demo_thread0(void);
extern void veda_demo_thread1(void);

// x20/x21 are never touched by main() itself, so reading them back here
// (ordinary, unbounded C -- veda_scheduler_start() has already returned
// by this point, so no compartment is live and this is just a normal
// register read) is safe and does not require any Veda-Core instruction.
static inline unsigned long read_x20(void) {
  unsigned long v;
  __asm__ volatile("mv %0, x20" : "=r"(v));
  return v;
}
static inline unsigned long read_x21(void) {
  unsigned long v;
  __asm__ volatile("mv %0, x21" : "=r"(v));
  return v;
}

int main(void) {
  veda_thread_t threads[VEDA_MAX_THREADS] = {
      {veda_demo_thread0, 0x40},
      {veda_demo_thread1, 0x40},
  };

  // 4 yields = 2 full round-trips -- the same minimum
  // vc_scheduler_cooperative_yield.S's own design used to distinguish
  // genuine independent per-thread restoration from a coincidental
  // single-pass success.
  uint32_t yields = veda_scheduler_start(threads, VEDA_MAX_THREADS, 4);

  if (yields != 4)
    return 1;
  // Discriminating by construction, exactly like the original .S test:
  // a wrong resume (restarting a thread at its entry instead of its true
  // saved PC) would reset its counter to 1 every visit instead of
  // reaching 2.
  if (read_x20() != 2)
    return 1;
  if (read_x21() != 2)
    return 1;
  return 0;
}
