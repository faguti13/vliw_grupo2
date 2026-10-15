#!/usr/bin/env bash
# Cifra o descifra un archivo cualquiera en el procesador (Icarus).
# Genera el .asm con la llave pedida, lo carga con load_file.py y extrae el resultado.
#
#   tools/crypto_file.sh enc|dec|crypto --input archivo --key HEX [--output salida] [--address 0x20000] [--size N]
#
# enc/dec: una pasada. crypto: cifra, descifra y compara contra el original.
# La extension la pone --output (p.ej. --output foto.png).
set -euo pipefail
cd "$(dirname "$0")/.."

modo=""
IN=""
OUT=""
KEY="00112233445566778899aabbccddeeff"
ADDR=0x20000
ORIG_SIZE=""
TIMEOUT="${TIMEOUT:-20000000}"
OPEN="${OPEN:-0}"

usage() {
  echo "uso: tools/crypto_file.sh enc|dec|crypto --input archivo --key HEX [--output salida] [--size N]" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    enc|dec|crypto|cifrar|descifrar) modo="$1"; shift ;;
    --input|-i) IN="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --key|-k) KEY="$2"; shift 2 ;;
    --address) ADDR="$2"; shift 2 ;;
    --size) ORIG_SIZE="$2"; shift 2 ;;
    --open) OPEN=1; shift ;;
    -h|--help) usage ;;
    *) echo "argumento no reconocido: $1" >&2; usage ;;
  esac
done

case "$modo" in
  enc|cifrar) modo=enc ;;
  dec|descifrar) modo=dec ;;
  crypto) ;;
  *) usage ;;
esac
if [ -z "$IN" ] || [ ! -f "$IN" ]; then
  echo "falta --input (archivo existente)" >&2
  exit 2
fi

B=build/crypto
mkdir -p "$B"
python3 tools/gen_programs.py --buffer cifrar --key "$KEY" --out "$B/cifrar.asm"
python3 tools/gen_programs.py --buffer descifrar --key "$KEY" --out "$B/descifrar.asm"
python3 tools/vliwasm.py -o "$B/cifrar.mem" "$B/cifrar.asm"
python3 tools/vliwasm.py -o "$B/descifrar.mem" "$B/descifrar.asm"

if [ ! -f build/tb_top.vvp ]; then
  echo "no esta build/tb_top.vvp; corre: make build/tb_top.vvp" >&2
  exit 1
fi

ADDR_DEC=$((ADDR))

run_paso() {
  local paso="$1" src="$2" dest="$3" extraer="$4"
  local size pad hi log
  size=$(stat -c %s "$src")
  pad=$(( (size + 7) / 8 * 8 ))
  hi=$((ADDR_DEC + pad - 1))
  log="$B/${paso}.log"
  python3 tools/load_file.py --input "$src" --output "$B/datos.mem" --address "$ADDR"
  echo "== $paso ($size bytes, $pad con relleno) =="
  set +e
  vvp -n build/tb_top.vvp +PROG="$B/${paso}.mem" +DATA="$B/datos.mem" \
      +DUMP="$B/dump.txt" +DUMPLO="$ADDR_DEC" +DUMPHI="$hi" +TIMEOUT="$TIMEOUT" >"$log" 2>&1
  local rc=$?
  set -e
  grep -E "HALT|TIMEOUT" "$log" || true
  if grep -q TIMEOUT "$log"; then
    echo "la simulacion termino por TIMEOUT (sube TIMEOUT=)" >&2
    exit 1
  fi
  if ! grep -q "^HALT" "$log"; then
    echo "la simulacion no termino en HALT" >&2
    tail -20 "$log" >&2
    exit 1
  fi
  if [ "$rc" -ne 0 ]; then
    echo "vvp salio con codigo $rc" >&2
    exit 1
  fi
  python3 tools/extract_data.py --memory "$B/dump.txt" --address "$ADDR" --size "$extraer" --output "$dest"
}

default_out() {
  local ext base
  base=$(basename "$IN")
  ext="${base##*.}"
  if [ "$1" = enc ]; then
    if [ "$base" = "$ext" ]; then
      echo "${IN}.enc"
    else
      echo "${IN%.*}.enc.${ext}"
    fi
  else
    if [ "$base" = "$ext" ]; then
      echo "${IN}.dec"
    else
      echo "${IN%.*}.dec.${ext}"
    fi
  fi
}

abrir() {
  local f="$1"
  if [ "$OPEN" != 1 ]; then
    return 0
  fi
  if command -v wslview >/dev/null 2>&1; then
    wslview "$f" || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$f" >/dev/null 2>&1 || true
  elif command -v explorer.exe >/dev/null 2>&1; then
    explorer.exe "$(wslpath -w "$f" 2>/dev/null || echo "$f")" || true
  else
    echo "abre $f con el visor de imagenes"
  fi
}

IN_SIZE=$(stat -c %s "$IN")
IN_PAD=$(( (IN_SIZE + 7) / 8 * 8 ))

case "$modo" in
  enc)
    [ -n "$OUT" ] || OUT=$(default_out enc)
    run_paso cifrar "$IN" "$OUT" "$IN_PAD"
    echo "cifrado: $OUT ($IN_PAD bytes; original $IN_SIZE)"
    ;;
  dec)
    [ -n "$OUT" ] || OUT=$(default_out dec)
    extraer=${ORIG_SIZE:-$IN_SIZE}
    run_paso descifrar "$IN" "$OUT" "$extraer"
    echo "descifrado: $OUT ($extraer bytes)"
    abrir "$OUT"
    ;;
  crypto)
    enc_out="${OUT:-$B/cifrado.bin}"
    if [ -n "$OUT" ]; then
      dec_out="$OUT"
    else
      base=$(basename "$IN")
      ext="${base##*.}"
      if [ "$base" = "$ext" ]; then
        dec_out="$B/descifrado.bin"
      else
        dec_out="$B/descifrado.${ext}"
      fi
    fi
    # el round-trip deja el cifrado en build/crypto/cifrado.bin si OUT es el descifrado
    if [ "$enc_out" = "$dec_out" ]; then
      enc_out="$B/cifrado.bin"
    fi
    run_paso cifrar "$IN" "$enc_out" "$IN_PAD"
    extraer=${ORIG_SIZE:-$IN_SIZE}
    run_paso descifrar "$enc_out" "$dec_out" "$extraer"
    if cmp -s "$IN" "$dec_out"; then
      echo "OK: el descifrado recupera $IN ($IN_SIZE bytes) -> $dec_out"
    else
      echo "FAIL: $dec_out no coincide con $IN" >&2
      exit 1
    fi
    abrir "$dec_out"
    ;;
esac
