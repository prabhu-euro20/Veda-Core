.include "veda_selfcheck_macros.S"
.section .text
.global _start
_start:
    # Minimal OS kernel Milestone B: end-to-end integration -- the switcher
    # pattern (Milestone A, vc_switcher_register_clear.S) with its own
    # RETURN leg (target -> switcher) replaced by a single, cheap,
    # one-operand OCRETURN through a switcher-minted sentry, instead of a
    # second, symmetric OCInvoke. Proves the sentry mechanism composes into
    # a real, multi-hop switcher call chain, not just in isolation
    # (vc_ocreturn_basic.S). vc_switcher_register_clear.S itself is left
    # completely unmodified -- a permanent regression proof that the
    # original, symmetric double-OCInvoke path still works; this is a
    # separate, new file, per the design doc's own explicit "new file, not
    # an edit" decision.
    #
    # Two sentries are minted here in _start, before any compartment is
    # entered (capability registers survive OCInvoke, only PCC narrows --
    # the same pattern vc_switcher_register_clear.S already established):
    # sentry-1 (c9) lets the TARGET compartment cheaply return into a
    # small, dedicated landing window inside the switcher
    # (switcher_fast_return); sentry-2 (c11) lets that landing window
    # itself cheaply exit to fully unbounded PCC afterward -- kept
    # pre-built and minimal-instruction-count on the switcher side (a
    # single marker write + `ocreturn`), exactly the "self-contained
    # trampoline" constraint the design doc names as necessary given a
    # sentry's own Length narrows PCC to whatever window the sentry itself
    # describes.

    # -- sentry-1 SOURCE (Object_ID=40): Base=switcher_fast_return,
    #    Length=0x0100, Perms=Execute. --
    la   t0, switcher_fast_return
    slli t0, t0, 32
    li   t1, 0x01000002
    or   t0, t0, t1
    li   x1, 40
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 40
    .insn i 0x0b, 0x5, x8, x1, 0  # veda.bind c8, x1  -- sentry-1 source, unsealed
    .insn r 0x5b, 0x1, 0x15, x9, x8, x0  # csealentry c9, c8  -- MINT sentry-1

    # -- sentry-2 SOURCE (Object_ID=41): Base=exit_landing, Length=0xFFFF
    #    (VEDA_PCC_UNBOUNDED), Perms=Execute. --
    la   t0, exit_landing
    slli t0, t0, 32
    li   t1, 0xFFFF0002
    or   t0, t0, t1
    li   x1, 41
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2

    li   x1, 41
    .insn i 0x0b, 0x5, x10, x1, 0  # veda.bind c10, x1  -- sentry-2 source, unsealed
    .insn r 0x5b, 0x1, 0x15, x11, x10, x0  # csealentry c11, c10  -- MINT sentry-2

    # -- TARGET compartment (Object_ID=33/34/35, Length=0x0100), identical
    #    in shape to vc_switcher_register_clear.S's own. --
    la   t0, target_entry
    slli t0, t0, 32
    li   t1, 0x01000402
    or   t0, t0, t1
    li   x1, 33
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- TARGET CODE

    li   x1, 34
    li   x2, 0x8003070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- TARGET DATA

    li   x1, 35
    li   x2, 0x8003080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- type authority (target)

    li   x1, 33
    .insn i 0x0b, 0x5, x5, x1, 0  # veda.bind c5, x1  -- TARGET CODE, unsealed
    li   x1, 34
    .insn i 0x0b, 0x5, x6, x1, 0  # veda.bind c6, x1  -- TARGET DATA, unsealed
    li   x1, 35
    .insn i 0x0b, 0x5, x7, x1, 0  # veda.bind c7, x1  -- type authority (target)

    .insn r 0x5b, 0x1, 0x10, x5, x5, x7  # cseal c5, c5, c7  -- sealed TARGET CODE
    .insn r 0x5b, 0x1, 0x10, x6, x6, x7  # cseal c6, c6, c7  -- sealed TARGET DATA

    # -- SWITCHER compartment (Object_ID=30/31/32, Length=0x0100). --
    la   t0, switcher_entry
    slli t0, t0, 32
    li   t1, 0x01000402
    or   t0, t0, t1
    li   x1, 30
    mv   x2, t0
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- SWITCHER CODE

    li   x1, 31
    li   x2, 0x8002070000400400
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- SWITCHER DATA

    li   x1, 32
    li   x2, 0x8002080000400300
    .insn r 0x0b, 0x0, 0x03, x5, x1, x2  # veda.odt.populate x5, x1, x2  -- type authority (switcher)

    li   x1, 30
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1  -- SWITCHER CODE
    li   x1, 31
    .insn i 0x0b, 0x5, x1, x1, 0  # veda.bind c1, x1  -- SWITCHER DATA
    li   x1, 32
    .insn i 0x0b, 0x5, x2, x1, 0  # veda.bind c2, x1  -- type authority (switcher)

    .insn r 0x5b, 0x1, 0x10, x3, x0, x2  # cseal c3, c0, c2  -- sealed SWITCHER CODE
    .insn r 0x5b, 0x1, 0x10, x4, x1, x2  # cseal c4, c1, c2  -- sealed SWITCHER DATA

    li   x20, 0xBAD5EC12                  # poisoned non-argument register

    .insn r 0x5b, 0x1, 0x12, x0, x3, x4  # ocinvoke c3, c4  -- enters the switcher
    j    fail                             # must NOT be reached

switcher_entry:
    li   x20, 0
    .insn r 0x5b, 0x1, 0x12, x0, x5, x6  # ocinvoke c5, c6  -- enters the target
    j    fail                             # must NOT be reached

target_entry:
    li   x22, 0x600D
    .insn r 0x5b, 0x1, 0x16, x0, x9, x0  # ocreturn c9  -- cheap return into switcher_fast_return
    j    fail                             # must NOT be reached

.balign 4
switcher_fast_return:
    # -- back inside the switcher's own, freshly-scoped landing window
    #    (veda_pcc_base/length now equal sentry-1's own Base/Length) --
    #    proves the target's cheap OCRETURN genuinely restored the
    #    switcher's own execution context, not merely jumped somewhere. --
    li   x23, 0xF00D
    .insn r 0x5b, 0x1, 0x16, x0, x11, x0  # ocreturn c11  -- cheap exit to fully unbounded PCC
    j    fail                             # must NOT be reached

.balign 4
exit_landing:
    li   t2, 0
    bne  x20, t2, fail
    li   t2, 0x600D
    bne  x22, t2, fail
    li   t2, 0xF00D
    bne  x23, t2, fail
    RVMODEL_HALT_PASS
fail:
    RVMODEL_HALT_FAIL
