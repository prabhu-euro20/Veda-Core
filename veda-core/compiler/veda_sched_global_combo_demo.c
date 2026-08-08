// CRF-exhaustion fix, real combined verification test
// (TOOLCHAIN_MILESTONE_14_CRF_SPILL_RESULTS.md): proves the globals
// table-base capability (c11) survives a real 2-thread cooperative
// scheduler round-trip, mirroring veda_sched_demo.c's own established
// structure exactly.

#include "../runtime/veda_sched.h"

extern void veda_sched_global_combo_boot(void);
extern void veda_combo_thread0(void);
extern void veda_combo_thread1(void);

// x22/x23 are never touched by main() itself -- ordinary, unbounded C
// register reads once veda_scheduler_start() has returned and no
// compartment is live, the identical pattern veda_sched_demo.c's own
// read_x20()/read_x21() already establish.
static inline unsigned long read_x22(void) {
  unsigned long v;
  __asm__ volatile("mv %0, x22" : "=r"(v));
  return v;
}
static inline unsigned long read_x23(void) {
  unsigned long v;
  __asm__ volatile("mv %0, x23" : "=r"(v));
  return v;
}

int main(void) {
  // Bootstrap: mint the data-region capability and the one-entry table,
  // bind c11 to the table -- "wide open" PCC, before any OCInvoke,
  // identical bootstrap timing to Milestone 13's own veda_rt_init_globals.
  veda_sched_global_combo_boot();

  veda_thread_t threads[VEDA_MAX_THREADS] = {
      {veda_combo_thread0, 0x40},
      {veda_combo_thread1, 0x40},
  };

  // 4 yields = each thread's first entry (write) + second resume
  // (re-read through c11, the real discriminator) + park.
  uint32_t yields = veda_scheduler_start(threads, VEDA_MAX_THREADS, 4);

  if (yields != 4)
    return 1;

  // The real, checkable proof: each thread's SECOND table access (after
  // a real yield/resume round-trip) must return the exact constant it
  // itself wrote on its first access, through the SAME c11 -- not
  // garbage (untagged capability) and not the other thread's value
  // (wrong offset/aliasing).
  if (read_x22() != 0xAAAA)
    return 1;
  if (read_x23() != 0xBBBB)
    return 1;
  return 0;
}
