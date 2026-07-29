.section .text
.global _start
_start:
    # Traditional RV64I: an attacker-corrupted return address (e.g. from a
    # real stack-buffer overflow) is "returned through" via a raw jalr --
    # no check exists anywhere in the base ISA. Whatever the attacker put
    # there simply executes.
    la   ra, attacker_controlled_code   # simulates a corrupted saved return address
    jalr ra                              # "return" -- unprotected, no check
    j    done                            # never reached if hijack succeeds

attacker_controlled_code:
    li   x30, 0xbad1                    # attacker's own code, now running with full control
done:
1:
    j 1b
