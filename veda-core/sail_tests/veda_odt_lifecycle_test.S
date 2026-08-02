.section .text
.global _start
_start:
    li   x1, 5                     # a fresh Object_ID, never touched by the test scaffold
    li   x2, 0x800104000040100c    # packed descriptor: Base=0x80010400, Length=0x40, Perms=0x100C
    .insn r 0x0b, 0x0, 0x03, x0, x1, x2  # veda.odt.populate x0, x1, x2  (real ODT-Populate, not the test scaffold)
    .insn i 0x0b, 0x5, x0, x1, 0  # veda.bind c0, x1              (bind the freshly-populated object)
    li   x3, 0                      # access offset
    li   x4, 0x77                    # value to store
    .insn r 0x0b, 0x3, 0x01, x4, x0, x3  # ocs.d c0, x3, x4  -- must succeed, object is real and valid
    li   x5, 0
    .insn r 0x0b, 0x3, 0x00, x5, x0, x3  # ocl.d c0, x3, x5  -- load back, expect 0x77
    .insn r 0x0b, 0x1, 0x03, x0, x1, x0  # veda.odt.destroy x0, x1   -- destroys Object_ID=5, bumps generation
    .insn r 0x0b, 0x3, 0x01, x4, x0, x3  # ocs.d c0, x3, x4 (again) -- c0's cached generation is now stale,
                                        # must hard-trap Tag Violation (cause 0x02), not silently succeed
1:
    j 1b
