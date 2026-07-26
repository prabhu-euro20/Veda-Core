.section .text
.global _start
_start:
    li   x1, 5                     # a fresh Object_ID, never touched by the test scaffold
    li   x2, 0x800104000040100c    # packed descriptor: Base=0x80010400, Length=0x40, Perms=0x100C
    .word 0x0620800b               # veda.odt.populate x0, x1, x2  (real ODT-Populate, not the test scaffold)
    .word 0x0000d00b               # veda.bind c0, x1              (bind the freshly-populated object)
    li   x3, 0                      # access offset
    li   x4, 0x77                    # value to store
    .word 0x0230320b                 # ocs.d c0, x3, x4  -- must succeed, object is real and valid
    li   x5, 0
    .word 0x0030328b                  # ocl.d c0, x3, x5  -- load back, expect 0x77
    .word 0x0600900b                  # veda.odt.destroy x0, x1   -- destroys Object_ID=5, bumps generation
    .word 0x0230320b                   # ocs.d c0, x3, x4 (again) -- c0's cached generation is now stale,
                                        # must hard-trap Tag Violation (cause 0x02), not silently succeed
1:
    j 1b
