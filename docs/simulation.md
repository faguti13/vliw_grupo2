# Simulación, pruebas y herramientas

<<<<<<< HEAD
## 3. Matriz de pruebas


| Banco de pruebas | Qué comprueba                                                                                          |
| ---------------- | ------------------------------------------------------------------------------------------------------ |
| `tb_key_vault`   | escritura y lectura de las 16 subllaves, sin camino hacia GPR                                          |
| `tb_crypto_unit` | `FROUND` contra los vectores de `tools/feistel4_ref`, `AUTH` válido e inválido, bloqueo sin sesión, SR |



| Programa (`programs/`) | Cubre                                                                         |
| ---------------------- | ----------------------------------------------------------------------------- |
| `fround`               | una ronda con la bóveda                                                       |
| `feistel_bloque`       | cifrado y descifrado de un bloque contra la referencia en C                   |
| `boveda`               | bloqueo sin `AUTH`, credencial inválida, `LOGOUT`, subllaves fuera de los GPR |
| `mixto`                | un lazo con `FROUND` sobre 3 bloques                                          |


Cada programa tiene un `.expect` (registros, memoria, `forbid`, `illegal = 0`, `hazards = 0`) que
`tools/check_dump.py` verifica. `make test` imprime una línea `PASS`/`FAIL` por prueba.
`boveda.asm` exige, con reglas `forbid`, que ninguna subllave aparezca en un registro.

## 4. Herramientas


| Herramienta             | Función                                                                                                                            |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `tools/feistel4_ref.c`  | referencia de la Fig. 1: cifra, descifra archivos y genera vectores de prueba                                                      |
| `tools/load_file.py`    | convierte un archivo (texto, binario o imagen) en `.mem` en `0x20000` y escribe el buzón en `0x1FFF0` (dirección, tamaño, bloques) |
| `tools/extract_data.py` | recupera los bytes cifrados del volcado de memoria                                                                                 |
| `tools/demo.sh`         | demo de cifrado y descifrado de archivo de texto o imagen, comparada con la referencia en C                                        |


`+DATA=archivo.mem` carga el archivo a cifrar. Con `+TRACE`, cada cambio de SR aparece en la traza.
`+REGS` vuelca también el SR. La línea final incluye el SR:

```
HALT cycles=... bundles=... illegal=0 hazards_raw=0 hazards_waw=0 SR=00000000
```



## 5. Flujo de trabajo  


### Feistel4:

```
make run PROG=programs/fround.asm
make run PROG=programs/feistel_bloque.asm
make run PROG=programs/boveda.asm
make demo-archivo
make demo-imagen
```

`make demo-archivo` y `make demo-imagen` cifran y descifran en el procesador y comparan el
resultado con `feistel4_ref`.
=======
## 1. Elección del simulador

| | Icarus Verilog 12 | Verilator 5 |
|---|---|---|
| Papel | **principal** (`make sim`, `make test`, demos) | **complementario** (`make lint`, `make sim-verilator`) |
| Modelo | intérprete de eventos, 4 estados (`x`, `z`) | compilado, 2 estados, ciclo a ciclo |
| Ventaja | corre los testbenches con `#` y `$display` sin adaptación; la inicialización con `x` delata registros o memorias sin inicializar; arranque inmediato | lint estricto (`-Wall`) del RTL y simulación rápida del mismo diseño |
| Límite | más lento en programas largos | exige código sintetizable en el RTL y una compilación C++ previa |

**Justificación.** El proyecto es pequeño (≈ 620 líneas de RTL) y los testbenches son de
comprobación dirigida con retardos y tareas, que Icarus ejecuta tal cual y con la semántica de 4
estados que revela errores de inicialización. Se eligió como simulador principal porque la
regresión completa (7 testbenches unitarios y 8 programas) tarda unos segundos y todo el equipo
puede reproducirla con un solo paquete. Verilator se añade para dos cosas que Icarus no hace bien:
el **lint** (`make lint` queda limpio y se corre antes de cada merge) y una **segunda
implementación del simulador** sobre el mismo RTL: `make sim-verilator PROG=...` corre un programa y
debe producir los mismos registros finales. Un resultado igual en dos simuladores independientes
descarta errores de semántica del simulador (por ejemplo, condiciones de carrera entre `always`).

## 2. Modelos

* **Memoria.** `memory.sv`: arreglo de bytes de 1 MiB, inicializado en 0. Un puerto de fetch
  combinacional de 128 bits (16 bytes alineados) y un puerto de datos de 32 bits, big-endian, con
  lectura combinacional y escritura síncrona en EX. Carga de imágenes con `$readmemh` de un `.mem`.
* **Banco de registros.** 32 × 32 bits, 8 lecturas combinacionales y 5 escrituras síncronas. `r0`
  vale siempre 0. Una lectura no ve una escritura del mismo ciclo (no hay bypass), que es lo que
  el contrato de tiempo supone.
* **Unidades funcionales.** ALU, LSU, BRU y cripto son combinacionales dentro de EX; sus resultados
  se registran en EX/WB. El SR y la bóveda cambian al final de EX.

## 3. Matriz de pruebas

| Banco de pruebas | Qué comprueba |
|---|---|
| `tb_alu` | las 16 operaciones de la ALU, signo, desplazamientos, `COMP`, `DIV` por 0 |
| `tb_regfile` | 8 lecturas y 5 escrituras simultáneas, `r0`, prioridad entre puertos |
| `tb_lsu` | `CP`/`AP`, dirección efectiva `rbase + offset` con signo |
| `tb_bru` | los 4 saltos condicionales con signo, `S`, `SYE` (enlace), `SRG`, `FIN`, destino relativo al siguiente bundle |
| `tb_dispatch` | separación de slots, puertos usados, NOPs canónicos, opcodes ilegales |
| `tb_key_vault` | escritura y lectura de las 16 subllaves, sin camino hacia GPR |
| `tb_crypto_unit` | `FROUND` contra los vectores de `tools/feistel4_ref`, `AUTH` válido e inválido, bloqueo sin sesión, SR |
| `tb_top` + programa | pipeline completo: ver la tabla siguiente |

| Programa (`programs/`) | Cubre |
|---|---|
| `isa_completa` | cada instrucción de la ISA al menos una vez |
| `alu_paralelo` | 4 slots ocupados en el mismo bundle y escrituras simultáneas |
| `memoria` | `CP`/`AP`, secuencias, store-load en bundles consecutivos |
| `saltos` | saltos tomados y no tomados, los 2 bundles descartados, lazo hacia atrás, llamadas |
| `fround` | una ronda con la bóveda |
| `feistel_bloque` | cifrado y descifrado de un bloque contra la referencia en C |
| `boveda` | bloqueo sin `AUTH`, credencial inválida, `LOGOUT`, subllaves fuera de los GPR |
| `mixto` | un lazo con instrucciones tradicionales y `FROUND` sobre 3 bloques |

Cada programa tiene un `.expect` (registros, memoria, `forbid`, `illegal = 0`, `hazards = 0`) que
`tools/check_dump.py` verifica. `make test` imprime una línea `PASS`/`FAIL` por prueba.

## 4. Herramientas

| Herramienta | Función |
|---|---|
| `tools/vliwasm.py` | ensamblador (una línea por bundle, `|` entre slots, `.equ .word .space .align`); coloca cada instrucción en su slot, comprueba rangos, WAW y, con `--check-hazards`, RAW lineales; emite `.mem`, `.bin` y `.lst` |
| `tools/bin2mem.py` | convierte el `.bin` del compilador a `.mem` |
| `tools/load_file.py` | cargador: convierte un archivo (texto, binario o imagen) en `.mem` en `0x20000` y escribe el buzón de E/S en `0x1FFF0` (dirección, tamaño, bloques) |
| `tools/extract_data.py` | extractor: recupera los bytes del volcado de memoria |
| `tools/traza.py` | resume la traza (`+TRACE`) por ciclos |
| `tools/feistel4_ref.c` | referencia de la Fig. 1: cifra, descifra archivos y genera vectores de prueba |
| `tools/gen_programs.py` | genera los programas con planificación mínima |
| `tools/demo.sh` | demo completa de cifrado y descifrado de archivo de texto o imagen |

### Argumentos de `tb_top`

`+PROG=archivo.mem` (programa), `+DATA=archivo.mem` (datos extra, por ejemplo el archivo a cifrar),
`+REGS=ruta` (vuelca registros y SR), `+DUMP=ruta` con `+DUMPLO`/`+DUMPHI` (vuelca un rango de
memoria), `+TIMEOUT=ciclos`, `+TRACE` (traza por ciclo) y `+VCD=ruta` (ondas).

### Traza y ondas

Con `+TRACE`, cada ciclo informa el bundle en EX (`EX pc=... w0|w1|w2|w3`), cada escritura en WB
(`WB r8 <= 00000078`), cada salto (`SALTO TOMADO`, `se descartan 2 bundles`) y cada cambio de SR.
Las ondas se escriben con `+VCD`; `make wave` las abre en GTKWave con la vista guardada
`tb/waves/tb_top.gtkw` (PC, salto, SR y registros de pipeline).

### Monitor de riesgos

`tb/hazard_monitor.sv` observa IF/ID, ID/EX y EX/WB. Cuenta un **RAW** cuando un bundle lee en ID un
registro con una escritura pendiente en EX o WB (distancia < 3) y un **WAW** cuando dos slots del
mismo bundle escriben el mismo GPR (distinto de `r0`). La línea final es:

```
HALT cycles=203 bundles=172 illegal=0 hazards_raw=0 hazards_waw=0 SR=00000000
```

Todo programa generado por el compilador debe terminar con `hazards_raw=0 hazards_waw=0`.

## 5. Flujo de trabajo

```
make sim                                  # regresión completa en Icarus
make lint                                 # Verilator --lint-only -Wall
make sim-verilator PROG=programs/mixto.asm
make run PROG=programs/fround.asm         # ensambla y simula un programa
make run BIN=archivo.bin                  # simula el binario del compilador
make demo                                 # regresión y demos de archivo y de imagen
make demo-compilador                      # make e2e del repositorio P1_CE1108
```
>>>>>>> 669220671f36fd2861033c8ffb107a3116854203
