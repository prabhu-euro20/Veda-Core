# Real self-check convention, reused field-for-field from this project's
# own already-verified ACT4 RVMODEL macros
# (act4-verify/config/cores/cvw/cvw-rv64gc/rvmodel_macros.h) -- not a new
# mechanism, the same one already proven to work for the RVA23 base core's
# real conformance testbench, applied here to sail_riscv_sim's own real,
# built-in HTIF support instead of a custom Verilog testbench watcher.

.section .tohost,"aw",@progbits
.balign 8
.global tohost
tohost: .dword 0
.balign 8
.global fromhost
fromhost: .dword 0
.section .text

# Two 32-bit stores at offsets 0/4, not one 64-bit store -- the real,
# exact ACT4 RVMODEL_HALT_PASS/FAIL convention (rvmodel_macros.h): low
# word = the pass/fail code, high word = 0 explicitly. Matches this
# project's own real, previously-debugged tohost write-race lesson from
# the RVA23 RTL testbench (tb_act4.sv): the two words are written as two
# separate stores, and a real watcher must treat the low-word write and
# the high-word-still-0 write as the actual "done" signal together, not
# just the first nonzero write it sees.
.macro RVMODEL_HALT_PASS
    li   x1, 1
    la   t0, tohost
    sw   x1, 0(t0)
    sw   x0, 4(t0)
self_loop_pass_\@:
    j self_loop_pass_\@
.endm

.macro RVMODEL_HALT_FAIL
    li   x1, 3
    la   t0, tohost
    sw   x1, 0(t0)
    sw   x0, 4(t0)
self_loop_fail_\@:
    j self_loop_fail_\@
.endm
