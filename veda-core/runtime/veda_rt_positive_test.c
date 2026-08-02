// Toolchain Milestone 7 positive control: repeatedly malloc every slot in
// an VEDA_RT_MAX_OBJECTS-object pool, write a distinct pattern into each
// via veda_ocs_d, read it back via veda_ocl_d, free all of them, and
// repeat -- proving real malloc/write/read/free/reuse works across many
// rounds (48 full lifecycle cycles total), not just once.
#include "veda_rt.h"

#define ROUNDS 6

int main(void) {
  veda_rt_init(VEDA_RT_SLOT_SIZE, VEDA_PERM_LOAD | VEDA_PERM_STORE);

  for (int round = 0; round < ROUNDS; round++) {
    veda_obj_t objs[VEDA_RT_MAX_OBJECTS];

    for (int i = 0; i < VEDA_RT_MAX_OBJECTS; i++) {
      objs[i] = veda_malloc();
      if (objs[i] == VEDA_OBJ_INVALID) return 1;
    }

    for (int i = 0; i < VEDA_RT_MAX_OBJECTS; i++) {
      uint64_t pattern = 0x1000ull * (uint64_t)(round + 1) + (uint64_t)i;
      if (!veda_ocs_d(objs[i], 0, pattern)) return 2;
    }

    for (int i = 0; i < VEDA_RT_MAX_OBJECTS; i++) {
      uint64_t pattern = 0x1000ull * (uint64_t)(round + 1) + (uint64_t)i;
      uint64_t got = 0;
      if (!veda_ocl_d(objs[i], 0, &got)) return 3;
      if (got != pattern) return 4;
    }

    for (int i = 0; i < VEDA_RT_MAX_OBJECTS; i++) {
      veda_free(objs[i]);
    }
  }

  return 0;
}
