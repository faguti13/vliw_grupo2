#!/usr/bin/env python3
"""load_file.py - Convierte un archivo cualquiera (texto, imagen, binario) en una
inicializacion de memoria Verilog (.mem) para el simulador.

    ./load_file.py --input archivo.txt --output memory.mem --address 0x20000

Rellena con ceros hasta un multiplo de 8 bytes (bloque Feistel4) y escribe el
buzon de E/S en 0x1FFF0: [direccion, tamano en bytes, cantidad de bloques].
"""
import argparse
import struct
import sys

MAILBOX = 0x1FFF0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--address", default="0x20000", type=lambda s: int(s, 0))
    ap.add_argument("--no-mailbox", action="store_true")
    a = ap.parse_args()
    data = open(a.input, "rb").read()
    padded = data + bytes((-len(data)) % 8)
    with open(a.output, "w") as f:
        f.write(f"@{a.address:08x}\n")
        f.writelines(f"{b:02x}\n" for b in padded)
        if not a.no_mailbox:
            f.write(f"@{MAILBOX:08x}\n")
            f.writelines(f"{b:02x}\n" for b in struct.pack(">3I", a.address, len(data), len(padded) // 8))
    print(f"archivo: {a.input}")
    print(f"tamano: {len(data)} bytes ({len(padded)} con relleno, {len(padded) // 8} bloques de 8 bytes)")
    print(f"zona de memoria: 0x{a.address:08x} - 0x{a.address + len(padded) - 1:08x}")
    if not a.no_mailbox:
        print(f"buzon de E/S en 0x{MAILBOX:08x}: direccion, tamano, bloques")
    if a.address + len(padded) > 0xE0000:
        print("advertencia: la zona invade la pila (>= 0xE0000)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
