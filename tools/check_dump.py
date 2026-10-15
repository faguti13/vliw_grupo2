#!/usr/bin/env python3
"""check_dump.py - Compara el volcado de registros/memoria de una simulacion con un .expect.

Formato del .expect (una regla por linea, '#' comenta):
    r5 = 0x1234          registro final
    sr = 0x1             registro de estado
    mem 0x10000 = 0xAB   palabra de 32 bits big-endian en memoria (dentro del volcado)
    forbid 0xDEADBEEF    ningun registro ni palabra del volcado puede valer eso
    illegal = 0          (por omision 0)    hazards = 0   (por omision 0)
"""
import argparse
import re
import sys


def load_regs(path):
    regs = {}
    for line in open(path):
        k, v = line.split()
        regs[k] = int(v, 16) if k == "sr" or re.fullmatch(r"r\d+", k) else int(v)
    return regs


def load_dump(path):
    mem, addr = {}, 0
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        if line.startswith("@"):
            addr = int(line[1:], 16)
            continue
        mem[addr] = int(line, 16)
        addr += 1
    return mem


def word(mem, a):
    return (mem[a] << 24) | (mem[a + 1] << 16) | (mem[a + 2] << 8) | mem[a + 3]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--regs", required=True)
    ap.add_argument("--dump")
    ap.add_argument("--expect", required=True)
    ap.add_argument("--name", default="")
    ap.add_argument("--log")
    a = ap.parse_args()
    regs = load_regs(a.regs)
    mem = load_dump(a.dump) if a.dump else {}
    errs = []
    if a.log and "TIMEOUT" in open(a.log).read():
        errs.append("la simulacion termino por TIMEOUT")
    rules = {"illegal": 0, "hazards": 0}
    for raw in open(a.expect):
        line = raw.split("#")[0].strip()
        if not line:
            continue
        m = re.fullmatch(r"(r\d+|sr|illegal|hazards)\s*=\s*(\S+)", line)
        if m:
            k, v = m.group(1), int(m.group(2), 0)
            if k in ("illegal", "hazards"):
                rules[k] = v
            elif regs[k] != v:
                errs.append(f"{k} = {regs[k]:#010x} (esperado {v:#010x})")
            continue
        m = re.fullmatch(r"mem\s+(\S+)\s*=\s*(\S+)", line)
        if m:
            ad, v = int(m.group(1), 0), int(m.group(2), 0)
            try:
                got = word(mem, ad)
            except KeyError:
                errs.append(f"mem[{ad:#x}] fuera del volcado")
                continue
            if got != v:
                errs.append(f"mem[{ad:#x}] = {got:#010x} (esperado {v:#010x})")
            continue
        m = re.fullmatch(r"forbid\s+(\S+)", line)
        if m:
            v = int(m.group(1), 0)
            for k, x in regs.items():
                if re.fullmatch(r"r\d+", k) and x == v:
                    errs.append(f"{k} contiene el valor prohibido {v:#010x}")
            for ad in sorted(mem):
                if ad % 4 == 0 and ad + 3 in mem and word(mem, ad) == v:
                    errs.append(f"mem[{ad:#x}] contiene el valor prohibido {v:#010x}")
            continue
        errs.append(f"regla no reconocida: {line}")
    for k in ("illegal", "hazards"):
        if regs.get(k, 0) != rules[k]:
            errs.append(f"{k} = {regs.get(k)} (esperado {rules[k]})")
    if errs:
        print(f"{a.name}: FAIL")
        for e in errs:
            print("   -", e)
        return 1
    print(f"{a.name}: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
