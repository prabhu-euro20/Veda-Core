// Toolchain Milestone 20-fix (indirect-call crash fix) follow-up control:
// confirms the fix (rewriteSignatures now skips a function with any
// non-direct-call use, rather than half-rewriting it and crashing) does
// not break the COMMON, legitimate case -- a function pointer used with
// ORDINARY data that never touches a Veda-Core object at all. `n` here is
// a real stack local, never obtained from veda_malloc_raw, so `n->value`
// is a genuinely ordinary, correctly-unprotected raw access -- expected
// to succeed cleanly, with no trap of any kind, proving the fix's real
// scope limit (indirect calls touching TRACKED pointers lose protection
// at that boundary, matching this pass's own stated design) does not
// regress the far more common untracked case.
typedef unsigned long u64;

struct node {
  u64 value;
};

unsigned long read_value(struct node *n) { return n->value; }

unsigned long (*g_reader)(struct node *) = read_value;

int main(void) {
  struct node n; // ordinary stack local -- never veda_malloc_raw'd
  n.value = 42;

  u64 result = g_reader(&n);

  if (result != 42) return 1;
  return 0;
}
