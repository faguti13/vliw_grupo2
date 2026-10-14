# vliw_grupo2 — Feistel4-VLIW (CE4301, Grupo 2)

Procesador VLIW de 128 bits por bundle (4 slots de 32 bits: ALU, LSU, BRU y
cripto/seguridad) con cifrado por bloques Feistel de 4 rondas en hardware,
escrito en SystemVerilog, con ensamblador, cargador de archivos, simulación
y pruebas. El compilador del lenguaje JAF (repo `P1_CE1108`) genera binarios
para este procesador.

## Estructura

| Carpeta | Contenido |
|---|---|
| `rtl/` | SystemVerilog: pipeline IF/ID/EX/WB, banco de registros, ALU, LSU, BRU, bóveda de llaves, unidad Feistel |
| `tb/` | Testbenches autoverificables por módulo y `tb_top` (procesador completo); `tb/waves/` guarda de GTKWave |
| `tools/` | `vliwasm.py` (ensamblador), `bin2mem.py`, `load_file.py`, `extract_data.py`, `check_dump.py`, `feistel4_ref.c` (referencia en C), `demo.sh` |
| `programs/` | Programas en ensamblador con su `.expect` (resultado esperado) |
| `docs/` | `isa.md`, `microarchitecture.md`, `simulation.md`, `compiler-integration.md`, `evidencias/` |

## Dependencias

Icarus Verilog 12 (simulador principal), Verilator 5 (complementario, lint y
simulación rápida), GTKWave (opcional), gcc y Python 3. La justificación de
los simuladores está en `docs/simulation.md`.

Con versiones anteriores:

- **Icarus Verilog 11:** `make test` funciona (probado: todos los testbenches y programas en PASS).
- **Verilator 4.x:** no reconoce `-Wno-UNUSEDSIGNAL` ni `-Wno-UNUSEDPARAM`; el lint se corre con
  `make lint VLINT="-Wall -Wno-DECLFILENAME -Wno-UNUSED -Wno-PINCONNECTEMPTY"`.
  `make sim-verilator` y `make cmp-sims` necesitan Verilator 5 (`--binary --timing`).

## Uso con `make`

| Comando | Qué hace |
|---|---|
| `make test` | Pruebas unitarias, ensambla y ejecuta todos los programas, verifica contra `.expect` |
| `make sim-verilator` | Simula con Verilator |
| `make cmp-sims` | Comprueba que Icarus y Verilator dejan registros finales idénticos en todos los programas |
| `make lint` | Lint con Verilator |
| `make run PROG=programs/mixto.asm` | Ensambla y ejecuta un programa |
| `make wave` | Abre `build/waves/run.vcd` en GTKWave |
| `make demo-archivo` / `make demo-imagen` | Cifra y descifra un archivo de texto / una imagen BMP en el procesador y compara con la referencia en C |
| `make demo-compilador` | Compila los ejercicios JAF con `P1_CE1108`, los ejecuta en el RTL y los verifica |
| `make demo` | Simulación base más ambas demos de archivo |

## Ensamblador y carga

```
python3 tools/vliwasm.py programa.asm -o programa.mem     # imagen .mem (@addr + un byte por línea)
python3 tools/vliwasm.py programa.asm --bin programa.bin  # binario con encabezado VLW1
python3 tools/vliwasm.py programa.asm --lst programa.lst  # listado con palabras hexadecimales
python3 tools/vliwasm.py programa.asm --check-hazards     # advierte dependencias RAW a menos de 3 bundles
python3 tools/bin2mem.py programa.bin programa.mem        # .bin (p. ej. del compilador) a .mem
```

- **Texto:** `load_file.py` coloca el archivo en el buffer `0x20000` y deja en el mailbox `0x1FFF0` la dirección, el tamaño y el número de bloques.
- **Binario / imagen:** el mismo mecanismo; para BMP solo se cifran los píxeles (`tools/demo.sh imagen`).
- **Salida:** `extract_data.py` recupera el buffer del volcado de memoria del testbench.

Sintaxis y codificaciones: `docs/isa.md` (incluye la green sheet completa).

## Integración con el compilador

El compilador (`../P1_CE1108`) usa el mismo contrato de latencias (`docs/compiler-integration.md`).
`jaf -x` incluye un segundo ensamblador independiente que se valida byte a byte contra `vliwasm.py`
(`make xcheck` en el repo del compilador).

## Evidencias

`docs/evidencias/` contiene los logs de `make test`, `make lint` y `make cmp-sims` (Icarus vs Verilator),
la comparación del resultado de `programs/mixto.asm` contra `tools/feistel4_ref.c` y las versiones de
los simuladores usadas (`versiones.txt`).
