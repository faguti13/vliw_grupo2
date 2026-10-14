#!/usr/bin/env bash
# demo.sh - Cifra y descifra un archivo real con el procesador (Icarus), usando
# load_file.py / extract_data.py y comparando contra la referencia en C.
#   tools/demo.sh texto | imagen
set -euo pipefail
cd "$(dirname "$0")/.."
B=build/demo; mkdir -p "$B" build/waves
KEY=00112233445566778899aabbccddeeff
ADDR=0x20000
modo=${1:-texto}

if [ "$modo" = texto ]; then
  python3 - <<'PY'
open("build/demo/original.bin", "wb").write(("Arquitectura VLIW Feistel4 - CE4301 grupo 2. " * 7 + "fin\n").encode())
PY
else
  python3 - <<'PY'
import struct
w = h = 32
px = bytearray()
for y in range(h):
    for x in range(w):
        px += bytes([(x * 8) % 256, (y * 8) % 256, ((x ^ y) * 8) % 256])
hdr = b"BM" + struct.pack("<IHHI", 54 + len(px), 0, 0, 54) + struct.pack("<IiiHHIIiiII", 40, w, h, 1, 24, 0, len(px), 2835, 2835, 0, 0)
open("build/demo/imagen.bmp", "wb").write(hdr + px)
open("build/demo/original.bin", "wb").write(bytes(px))      # solo los pixeles (el encabezado queda sin cifrar)
PY
fi

SIZE=$(stat -c %s $B/original.bin)
PAD=$(( (SIZE + 7) / 8 * 8 ))
python3 tools/vliwasm.py -o $B/cifrar.mem programs/cifrar_buffer.asm
python3 tools/vliwasm.py -o $B/descifrar.mem programs/descifrar_buffer.asm

echo "== Cifrado en el procesador =="
python3 tools/load_file.py --input $B/original.bin --output $B/datos.mem --address $ADDR
vvp -n build/tb_top.vvp +PROG=$B/cifrar.mem +DATA=$B/datos.mem +DUMP=$B/dump1.txt +DUMPLO=$((ADDR)) +DUMPHI=$((ADDR + PAD - 1)) | grep -E "HALT|TIMEOUT"
python3 tools/extract_data.py --memory $B/dump1.txt --address $ADDR --size $PAD --output $B/cifrado.bin
build/feistel4_ref enc $KEY $B/original.bin $B/cifrado_ref.bin
cmp $B/cifrado.bin $B/cifrado_ref.bin && echo "OK: el cifrado del procesador coincide con la referencia en C"

echo "== Descifrado en el procesador =="
python3 tools/load_file.py --input $B/cifrado.bin --output $B/datos2.mem --address $ADDR > /dev/null
vvp -n build/tb_top.vvp +PROG=$B/descifrar.mem +DATA=$B/datos2.mem +DUMP=$B/dump2.txt +DUMPLO=$((ADDR)) +DUMPHI=$((ADDR + PAD - 1)) | grep -E "HALT|TIMEOUT"
python3 tools/extract_data.py --memory $B/dump2.txt --address $ADDR --size $SIZE --output $B/descifrado.bin
cmp $B/descifrado.bin $B/original.bin && echo "OK: el descifrado recupera el archivo original ($SIZE bytes)"

if [ "$modo" = imagen ]; then
  python3 - <<'PY'
hdr = open("build/demo/imagen.bmp", "rb").read()[:54]
open("build/demo/imagen_cifrada.bmp", "wb").write(hdr + open("build/demo/cifrado.bin", "rb").read()[:3072])
open("build/demo/imagen_descifrada.bmp", "wb").write(hdr + open("build/demo/descifrado.bin", "rb").read())
print("imagenes: build/demo/imagen.bmp, imagen_cifrada.bmp, imagen_descifrada.bmp")
PY
fi
