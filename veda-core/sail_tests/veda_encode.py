#!/usr/bin/env python3
"""Computes exact 32-bit machine code for Veda-Core custom instructions,
mirroring the `mapping clause encdec` definitions in
toolchain/sail-riscv/model/extensions/Veda/*.sail field-for-field, to avoid
hand-computation errors when building a raw test program."""

def bind(mode, rs1, rd_cap):
    # 0b0000000000 @ mode(2) @ rs1(5) @ 0b101(3) @ 0b0(1) @ rd_cap(4) @ 0b0001011(7)
    assert 0 <= mode <= 3
    assert 0 <= rs1 <= 31
    assert 0 <= rd_cap <= 15
    v = (0 << 22) | (mode << 20) | (rs1 << 15) | (0b101 << 12) | (0 << 11) | (rd_cap << 7) | 0b0001011
    return v

def ocl(rs2, rs1_cap, rd):
    # 0b0000000(7) @ rs2(5) @ 0(1) @ rs1_cap(4) @ 0b011(3) @ rd(5) @ 0b0001011(7)
    assert 0 <= rs2 <= 31 and 0 <= rs1_cap <= 15 and 0 <= rd <= 31
    v = (0b0000000 << 25) | (rs2 << 20) | (0 << 19) | (rs1_cap << 15) | (0b011 << 12) | (rd << 7) | 0b0001011
    return v

def ocs(rs2, rs1_cap, rd):
    # 0b0000001(7) @ rs2(5) @ 0(1) @ rs1_cap(4) @ 0b011(3) @ rd(5) @ 0b0001011(7)
    assert 0 <= rs2 <= 31 and 0 <= rs1_cap <= 15 and 0 <= rd <= 31
    v = (0b0000001 << 25) | (rs2 << 20) | (0 << 19) | (rs1_cap << 15) | (0b011 << 12) | (rd << 7) | 0b0001011
    return v

def ocl_c(rs2, rs1_cap, rd_cap):
    # OCL.C -- Milestone 7. funct7=0000000(7) @ rs2(5) @ 0(1) @ rs1_cap(4) @ funct3=100(3) @ 0(1) @ rd_cap(4) @ 0b0001011(7)
    assert 0 <= rs2 <= 31 and 0 <= rs1_cap <= 15 and 0 <= rd_cap <= 15
    v = (0b0000000 << 25) | (rs2 << 20) | (0 << 19) | (rs1_cap << 15) | (0b100 << 12) | (0 << 11) | (rd_cap << 7) | 0b0001011
    return v

def ocs_c(rs2, rs1_cap, rd_cap):
    # OCS.C -- Milestone 7. funct7=0000001(7) @ rs2(5) @ 0(1) @ rs1_cap(4) @ funct3=100(3) @ 0(1) @ rd_cap(4) @ 0b0001011(7)
    assert 0 <= rs2 <= 31 and 0 <= rs1_cap <= 15 and 0 <= rd_cap <= 15
    v = (0b0000001 << 25) | (rs2 << 20) | (0 << 19) | (rs1_cap << 15) | (0b100 << 12) | (0 << 11) | (rd_cap << 7) | 0b0001011
    return v

def nmc_add_d(rs2, rs1_cap, rd):
    # 0b0000010(7) @ rs2(5) @ 0(1) @ rs1_cap(4) @ 0b011(3) @ rd(5) @ 0b0001011(7)
    assert 0 <= rs2 <= 31 and 0 <= rs1_cap <= 15 and 0 <= rd <= 31
    v = (0b0000010 << 25) | (rs2 << 20) | (0 << 19) | (rs1_cap << 15) | (0b011 << 12) | (rd << 7) | 0b0001011
    return v

def nmc_add_w(rs2, rs1_cap, rd):
    # 0b0000010(7) @ rs2(5) @ 0(1) @ rs1_cap(4) @ 0b010(3) @ rd(5) @ 0b0001011(7)
    assert 0 <= rs2 <= 31 and 0 <= rs1_cap <= 15 and 0 <= rd <= 31
    v = (0b0000010 << 25) | (rs2 << 20) | (0 << 19) | (rs1_cap << 15) | (0b010 << 12) | (rd << 7) | 0b0001011
    return v

CGETBASE, CGETLEN, CGETPERM, CGETTAG, CGETTYPE, CGETADDR, CGETOFFSET = range(7)

def capquery(funct7, rs1_cap, rd):
    # funct7(7) @ 00000(5, unused rs2) @ 0(1) @ rs1_cap(4) @ funct3=000(3) @ rd(5) @ 0b1011011(7)
    assert 0 <= funct7 <= 6 and 0 <= rs1_cap <= 15 and 0 <= rd <= 31
    v = (funct7 << 25) | (0 << 20) | (0 << 19) | (rs1_cap << 15) | (0b000 << 12) | (rd << 7) | 0b1011011
    return v

def oca(rs2, rs1_cap, rd_cap):
    # funct7=0001010(7) @ rs2(5) @ 0(1) @ rs1_cap(4) @ funct3=001(3) @ 0(1) @ rd_cap(4) @ 0b1011011(7)
    assert 0 <= rs2 <= 31 and 0 <= rs1_cap <= 15 and 0 <= rd_cap <= 15
    v = (0b0001010 << 25) | (rs2 << 20) | (0 << 19) | (rs1_cap << 15) | (0b001 << 12) | (0 << 11) | (rd_cap << 7) | 0b1011011
    return v

def odt_populate(rs2, rs1, rd):
    # funct7=0000011(7) @ rs2(5) @ rs1(5) @ funct3=000(3) @ rd(5) @ 0b0001011(7)
    assert 0 <= rs2 <= 31 and 0 <= rs1 <= 31 and 0 <= rd <= 31
    v = (0b0000011 << 25) | (rs2 << 20) | (rs1 << 15) | (0b000 << 12) | (rd << 7) | 0b0001011
    return v

def odt_destroy(rs1, rd):
    # funct7=0000011(7) @ 00000(5) @ rs1(5) @ funct3=001(3) @ rd(5) @ 0b0001011(7)
    assert 0 <= rs1 <= 31 and 0 <= rd <= 31
    v = (0b0000011 << 25) | (0 << 20) | (rs1 << 15) | (0b001 << 12) | (rd << 7) | 0b0001011
    return v

def cseal(rs2_cap, rs1_cap, rd_cap):
    # funct7=0010000(7) @ 0(1) @ rs2_cap(4) @ 0(1) @ rs1_cap(4) @ funct3=001(3) @ 0(1) @ rd_cap(4) @ 0b1011011(7)
    assert 0 <= rs2_cap <= 15 and 0 <= rs1_cap <= 15 and 0 <= rd_cap <= 15
    v = (0b0010000 << 25) | (0 << 24) | (rs2_cap << 20) | (0 << 19) | (rs1_cap << 15) | (0b001 << 12) | (0 << 11) | (rd_cap << 7) | 0b1011011
    return v

def cunseal(rs2_cap, rs1_cap, rd_cap):
    # funct7=0010001(7) @ 0(1) @ rs2_cap(4) @ 0(1) @ rs1_cap(4) @ funct3=001(3) @ 0(1) @ rd_cap(4) @ 0b1011011(7)
    assert 0 <= rs2_cap <= 15 and 0 <= rs1_cap <= 15 and 0 <= rd_cap <= 15
    v = (0b0010001 << 25) | (0 << 24) | (rs2_cap << 20) | (0 << 19) | (rs1_cap << 15) | (0b001 << 12) | (0 << 11) | (rd_cap << 7) | 0b1011011
    return v

def veda_atomic(op5, rs2, rs1_cap, rd, aq=0, rl=0):
    # op(5) @ aq(1) @ rl(1) @ rs2(5) @ 0(1) @ rs1_cap(4) @ funct3=011(3) @ rd(5) @ 0b0101011(7)
    assert 0 <= op5 <= 31 and 0 <= rs2 <= 31 and 0 <= rs1_cap <= 15 and 0 <= rd <= 31
    v = (op5 << 27) | (aq << 26) | (rl << 25) | (rs2 << 20) | (0 << 19) | (rs1_cap << 15) | (0b011 << 12) | (rd << 7) | 0b0101011
    return v

def ocinvoke(rs2_cap, rs1_cap):
    # OCInvoke -- Milestone 10 (CInvoke-equivalent). funct7=0010010(7) @
    # 0(1) @ rs2_cap(4) @ 0(1) @ rs1_cap(4) @ funct3=001(3) @ 0(1) @
    # rd_reserved=0000(4) @ 0b1011011(7)
    assert 0 <= rs2_cap <= 15 and 0 <= rs1_cap <= 15
    v = (0b0010010 << 25) | (0 << 24) | (rs2_cap << 20) | (0 << 19) | (rs1_cap << 15) | (0b001 << 12) | (0 << 11) | (0b0000 << 7) | 0b1011011
    return v

def ospecialrw(rs1_cap, rd_cap):
    # OSpecialRW -- Milestone 11 (ODA read/write). funct7=0010011(7) @
    # 00000(5, reserved rs2) @ 0(1) @ rs1_cap(4) @ funct3=001(3) @ 0(1) @
    # rd_cap(4) @ 0b1011011(7)
    assert 0 <= rs1_cap <= 15 and 0 <= rd_cap <= 15
    v = (0b0010011 << 25) | (0b00000 << 20) | (0 << 19) | (rs1_cap << 15) | (0b001 << 12) | (0 << 11) | (rd_cap << 7) | 0b1011011
    return v

VEDA_AMOXOR = 0b00100

if __name__ == "__main__":
    # Test program:
    #   veda.bind c0, x1      (x1 holds Object_ID=1)
    #   ocs.d     c0, x2, x3  (store x3 at offset x2 into object c0)
    #   ocl.d     c0, x2, x4  (load back from offset x2 into x4)
    print("bind(mode=0,rs1=x1,rd=c0)  =", hex(bind(0, 1, 0)))
    print("ocs.d(rs2=x2,rs1=c0,rd=x3) =", hex(ocs(2, 0, 3)))
    print("ocl.d(rs2=x2,rs1=c0,rd=x4) =", hex(ocl(2, 0, 4)))
