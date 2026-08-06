// Veda-Core cooperative-scheduler C API: thin glue. See veda_sched.h for
// the real scope statement and veda_sched_asm.S for every real
// Veda-Core-mnemonic step this performs.

#include "veda_sched.h"

extern void veda_sched_init_asm(uint64_t entry0, uint64_t len0,
                                 uint64_t entry1, uint64_t len1);
extern uint32_t veda_sched_run_asm(uint32_t max_yields);

uint32_t veda_scheduler_start(const veda_thread_t *threads, int count,
                               uint32_t max_yields) {
  if (count != VEDA_MAX_THREADS) {
    // This first pass only supports exactly VEDA_MAX_THREADS (2) threads
    // -- true N-way generalization is real, separate, deferred work (see
    // veda_sched.h). Fail loudly rather than silently misbehave.
    return 0;
  }
  veda_sched_init_asm((uint64_t)threads[0].entry, threads[0].code_length,
                       (uint64_t)threads[1].entry, threads[1].code_length);
  return veda_sched_run_asm(max_yields);
}
