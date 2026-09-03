#!/usr/bin/env python3
"""Build a UKNCBTL headless runner that logs every I/O register a program
touches - the instrument behind progress.md 19 (MKLAD, 3 Sep 2026).

    soft/uknc-iolog.py <workdir>

copies the emulator core from ../mc0511-dicewars (see
.claude/docs/soft.md, "Seeing what a program does with the hardware")
into <workdir>/emu, patches CFirstMemoryController (CPU) and
CSecondMemoryController (PPU) so that every port read, word write and
byte write goes through IoLog(), and adds these script commands to the
runner:

    iolog N       0 off; 1 print each new {side, dir, address, PC} once
                  ("IO ..." lines on stderr); 2 also print every access
                  ("io ..." lines)
    pputrace N    N debug ticks of PPU PC changes (up to 400 printed)
    pregs         the PPU's registers
    disppu A N    disassemble N instructions of PPU RAM (plane 0) from
                  octal A
    discpu A N    the same for CPU address space

Then `make -C <workdir>/emu uknc-headless` is run.  A worked script,
booting build/MKLAD.DSK to the RT-11 prompt and starting the game with
the log on, is written to <workdir>/emu/run_mklad.txt; key codes are
mnano/uknc.h's.  PPU accesses with a PC below 0100000 are the program's
own PPU code, the rest are the ROM's.

The copy lives wherever <workdir> is - the previous one was in /tmp and
went with a host restart, which is why this script exists.
"""
import os, shutil, subprocess, sys

DICE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'mc0511-dicewars')
EMUBASE = os.path.join(DICE, 'tmp', 'ukncbtl-qt', 'emulator', 'emubase')
RUNNER = os.path.join(DICE, 'tools', 'uknc-headless')
ROM = os.path.join(DICE, 'bin', 'ukncbtl', 'uknc_rom.bin')

HOOK = r'''
#include <set>
#include <tuple>
#include <cstdio>
int g_iolog = 0;
static std::set<std::tuple<int,int,int,int>> g_ioseen;
void IoLog(int side, int dir, uint16_t addr, uint16_t pc, uint16_t val)
{
    if (!g_iolog) return;
    const char *d = dir == 0 ? "rd" : (dir == 1 ? "wr" : "wb");
    auto k = std::make_tuple(side, dir, (int)addr, (int)pc);
    if (g_ioseen.insert(k).second)
        fprintf(stderr, "IO %s %s %06o pc=%06o val=%06o\n", side ? "PPU" : "CPU", d, addr, pc, val);
    if (g_iolog >= 2)
        fprintf(stderr, "io %s %s %06o pc=%06o val=%06o\n", side ? "PPU" : "CPU", d, addr, pc, val);
}
'''

HOOKS = [
    ('uint16_t CFirstMemoryController::GetPortWord(uint16_t address)\n',  '\n    IoLog(0,0,address,m_pProcessor->GetPC(),0);'),
    ('void CFirstMemoryController::SetPortWord(uint16_t address, uint16_t word)\n', '\n    IoLog(0,1,address,m_pProcessor->GetPC(),word);'),
    ('void CFirstMemoryController::SetPortByte(uint16_t address, uint8_t byte)\n', '\n    IoLog(0,2,address,m_pProcessor->GetPC(),byte);'),
    ('uint16_t CSecondMemoryController::GetPortWord(uint16_t address)\n', '\n    IoLog(1,0,address,m_pProcessor->GetPC(),0);'),
    ('void CSecondMemoryController::SetPortWord(uint16_t address, uint16_t word)\n', '\n    IoLog(1,1,address,m_pProcessor->GetPC(),word);'),
    ('void CSecondMemoryController::SetPortByte(uint16_t address, uint8_t byte)\n', '\n    IoLog(1,2,address,m_pProcessor->GetPC(),byte);'),
]

COMMANDS = r'''    else if (!strcmp(cmd, "iolog") && tok.size() >= 2)
    {
        g_iolog = atoi(tok[1]);
        printf("iolog %d\n", g_iolog);
    }
    else if (!strcmp(cmd, "pputrace") && tok.size() >= 2)
    {
        int n = atoi(tok[1]);
        CProcessor *ppu = g_pBoard->GetPPU();
        uint16_t last = 0xFFFF;
        int printed = 0;
        for (int i = 0; i < n && printed < 400; i++)
        {
            g_pBoard->DebugTicks();
            uint16_t pc = ppu->GetPC();
            if (pc != last)
            {
                printf("%06o ", pc);
                if (++printed % 10 == 0) printf("\n");
                last = pc;
            }
        }
        printf("\n");
    }
    else if (!strcmp(cmd, "pregs"))
    {
        CProcessor *p = g_pBoard->GetPPU();
        printf("PPU PC=%06o PSW=%06o SP=%06o R0=%06o R1=%06o R2=%06o R3=%06o R4=%06o R5=%06o\n",
               p->GetPC(), p->GetPSW(), p->GetSP(), p->GetReg(0), p->GetReg(1), p->GetReg(2), p->GetReg(3), p->GetReg(4), p->GetReg(5));
    }
    else if ((!strcmp(cmd, "disppu") || !strcmp(cmd, "discpu")) && tok.size() >= 3)
    {
        bool ppu = !strcmp(cmd, "disppu");
        unsigned addr; int n = atoi(tok[2]);
        if (!ParseOctal(tok[1], &addr)) return Fail("usage: %s OCTAL-ADDR COUNT", cmd);
        for (int i = 0; i < n; i++)
        {
            uint16_t buf[4];
            for (int j = 0; j < 4; j++)
            {
                unsigned a = addr + j*2;
                buf[j] = ppu ? g_pBoard->GetRAMWord(0, (uint16_t)a)
                             : (uint16_t)(g_pBoard->GetRAMByte(1, (uint16_t)(a/2)) | (g_pBoard->GetRAMByte(2, (uint16_t)(a/2)) << 8));
            }
            TCHAR ins[16], arg[32];
            uint16_t len = DisassembleInstruction(buf, (uint16_t)addr, ins, arg);
            printf("%06o  ", addr);
            for (int j = 0; j < 3; j++) printf(j < len ? "%06o " : "       ", buf[j]);
            printf(" %s %s\n", ins, arg);
            addr += len*2;
        }
    }
'''

SCRIPT = '''# boot build/MKLAD.DSK to the RT-11 prompt, then "R MKLAD" with the log on
run 900
press 030
run 30
press 153
run 1500
iolog 1
press 074
press 0113
press 0112
press 052
press 056
press 072
press 057
press 0153
run 400
screenshot mklad.bmp
disppu 023666 20
quit
'''

def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    work = os.path.join(sys.argv[1], 'emu')
    if os.path.exists(work):
        shutil.rmtree(work)
    os.makedirs(work)
    shutil.copytree(EMUBASE, os.path.join(work, 'emubase'))
    for f in ('main.cpp', 'stdafx.h', 'Makefile'):
        shutil.copy(os.path.join(RUNNER, f), work)

    p = os.path.join(work, 'emubase', 'Memory.cpp'); s = open(p).read()
    k = s.find('\n', s.find('#include "Processor.h"'))
    s = s[:k+1] + HOOK + s[k+1:]
    for sig, body in HOOKS:
        j = s.find(sig); assert j >= 0, sig
        b = s.find('{', j)
        s = s[:b+1] + body + s[b+1:]
    open(p, 'w').write(s)

    p = os.path.join(work, 'main.cpp'); s = open(p).read()
    s = s.replace('static CMotherboard *g_pBoard = nullptr;', 'static CMotherboard *g_pBoard = nullptr;\nextern int g_iolog;')
    anchor = '    else if (!strcmp(cmd, "evnt"))'
    assert anchor in s
    s = s.replace(anchor, COMMANDS + anchor)
    open(p, 'w').write(s)

    p = os.path.join(work, 'Makefile'); s = open(p).read()
    s = s.replace('EMUBASE ?= ../ukncbtl-qt/emulator/emubase', 'EMUBASE ?= ./emubase')
    open(p, 'w').write(s)
    open(os.path.join(work, 'run_mklad.txt'), 'w').write(SCRIPT)

    subprocess.check_call(['make', '-C', work, 'uknc-headless'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print('built %s/uknc-headless' % work)
    print('run:  %s/uknc-headless --rom %s --disk build/MKLAD.DSK --script %s/run_mklad.txt 2> io.txt' % (work, ROM, work))

if __name__ == '__main__':
    main()
