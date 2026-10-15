#!/usr/bin/env python3
"""extract_data.py - Extrae datos (cifrados/descifrados) del volcado de memoria.

    ./extract_data.py --memory memory_dump.txt --address 0x20000 --size 4096 --output resultado.bin

El volcado es el que genera tb_top (+DUMP): lineas '@direccion' seguidas de un byte
hexadecimal por linea. Si la zona pedida no esta en el volcado se informa el error.
"""
import argparse
import sys


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--memory", required=True)
    ap.add_argument("--address", required=True, type=lambda s: int(s, 0))
    ap.add_argument("--size", required=True, type=lambda s: int(s, 0))
    ap.add_argument("--output", required=True)
    a = ap.parse_args()
    mem, addr = {}, 0
    for line in open(a.memory):
        line = line.strip()
        if not line:
            continue
        if line.startswith("@"):
            addr = int(line[1:], 16)
        else:
            mem[addr] = int(line, 16)
            addr += 1
    try:
        out = bytes(mem[a.address + i] for i in range(a.size))
    except KeyError as e:
        print(f"extract_data: la direccion 0x{e.args[0]:x} no esta en el volcado", file=sys.stderr)
        return 1
    open(a.output, "wb").write(out)
    print(f"{a.size} bytes desde 0x{a.address:x} -> {a.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
