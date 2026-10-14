#!/usr/bin/env python3
"""bin2mem.py - Convierte el .bin del compilador (encabezado VLW1) en .mem (@dir + un byte por linea)."""
import struct
import sys

def main():
    if len(sys.argv) != 3:
        print("uso: bin2mem.py entrada.bin salida.mem", file=sys.stderr)
        return 2
    data = open(sys.argv[1], "rb").read()
    if data[:4] != b"VLW1":
        print("bin2mem: magic invalido", file=sys.stderr)
        return 1
    _ver, entry, cbase, csize, dbase, dsize, _top = struct.unpack(">7I", data[4:32])
    code = data[32:32 + csize]
    dat = data[32 + csize:32 + csize + dsize]
    with open(sys.argv[2], "w") as f:
        f.write(f"@{cbase:08x}\n")
        f.writelines(f"{b:02x}\n" for b in code)
        if dat:
            f.write(f"@{dbase:08x}\n")
            f.writelines(f"{b:02x}\n" for b in dat)
    return 0

if __name__ == "__main__":
    sys.exit(main())
