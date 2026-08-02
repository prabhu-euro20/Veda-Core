.section .text
.global _start
_start:
    // ─────────────────────────────────────────────────────────────
    // Veda-Core RTL Milestone 12: owner-hart ODT enforcement
    // (VEDA_CORE_SPEC.md §4.1, closing the spec's own long-named gap:
    // "an owner-hart field in the ODT entry, checked at Bind/Rebind
    // time"). This single-core RTL testbench has no real second hart
    // to own anything with (MHARTID is a fixed localparam=0, mirroring
    // Sail's own single-hart veda_test_sail.json config) -- Object_ID=60
    // is injected directly into the reset-time ODT scaffold (this
    // file's own top-level `initial` block, veda_core.tlv) pre-claimed
    // by owner_hart=0x63 (99 decimal), a stand-in "other hart," the
    // identical real technique already used for every other RTL-seeded
    // ODT fixture in this project (none are populated via a real
    // ODT-Populate instruction either). This positive test proves the
    // two paths genuinely reachable from a single real hart: claiming a
    // genuinely-unowned object, and a self-owned idempotent re-claim via
    // Rebind -- plus both instructions' own real soft-fail (never a
    // trap) against the injected wrong-owner fixture. The genuine
    // hard-trap path (plain Bind against a live, wrong-owner object) is
    // covered separately in veda_smoke_m12_neg.S.
    // ─────────────────────────────────────────────────────────────

    // -- Step 1: Object_ID=1 (reset-seeded, unowned) -- plain Bind must
    //    succeed AND claim it for this hart (MHARTID=0). --
    li   x1, 1
    .insn i 0x0b, 0x5, x0, x1, 0  // veda.bind c0, x1
    .insn r 0x5b, 0x0, 0x03, x10, x0, x0  // cgettag  x10, c0   -- expect 1
    .insn r 0x5b, 0x0, 0x00, x11, x0, x0  // cgetbase x11, c0   -- expect 0x80010000

    // -- Step 2: Rebind the SAME object -- now owned by hart 0, this
    //    hart's own real identity, so owner_ok must take the "self-owns"
    //    branch (not the "unowned" branch already proven in Step 1). --
    .insn i 0x0b, 0x5, x0, x1, 2  // veda.rebind c0, x1
    .insn r 0x5b, 0x0, 0x03, x12, x0, x0  // cgettag  x12, c0   -- expect 1
    .insn r 0x5b, 0x0, 0x00, x13, x0, x0  // cgetbase x13, c0   -- expect 0x80010000 (unchanged, same object)

    // -- Step 3: Object_ID=60 -- the RTL reset-seeded fixture pre-claimed
    //    by owner_hart=0x63. Bind-NoTrap must soft-fail (Tag cleared,
    //    no trap). --
    li   x3, 60
    .insn i 0x0b, 0x5, x1, x3, 1  // veda.bind.notrap c1, x3
    .insn r 0x5b, 0x0, 0x03, x14, x1, x0  // cgettag  x14, c1   -- expect 0 (soft-fail, wrong owner)

    // -- Step 4: Rebind against the SAME wrong-owner object -- Rebind
    //    never traps for ANY reason, so a wrong-owner Rebind must ALSO
    //    soft-fail. Use a freshly-bound register (c2, Object_ID=1) as
    //    the target so the "already sealed" short-circuit doesn't fire
    //    first -- isolates the owner-check path specifically. --
    li   x1, 1
    .insn i 0x0b, 0x5, x2, x1, 0  // veda.bind c2, x1        -- c2: Object_ID=1, Tag=1, Base=0x80010000
    .insn r 0x5b, 0x0, 0x03, x15, x2, x0  // cgettag  x15, c2   -- expect 1
    .insn r 0x5b, 0x0, 0x00, x16, x2, x0  // cgetbase x16, c2   -- expect 0x80010000
    li   x3, 60
    .insn i 0x0b, 0x5, x2, x3, 2  // veda.rebind c2, x3      -- Object_ID=60, wrong owner
    .insn r 0x5b, 0x0, 0x03, x17, x2, x0  // cgettag  x17, c2   -- expect 0 (soft-fail, Tag cleared)
    .insn r 0x5b, 0x0, 0x00, x18, x2, x0  // cgetbase x18, c2   -- expect 0x80010000 (UNCHANGED -- still c2's OLD Base, never overwritten by Object_ID=60's 0x80010200)

1:
    j 1b
