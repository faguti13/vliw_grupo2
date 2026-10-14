# Microarquitectura Feistel4-VLIW

Procesador VLIW de 4 slots con pipeline de 4 etapas, sin forwarding, stalls ni scoreboard. La
planificación es 100 % estática y está a cargo del compilador.

## 1. Diagrama de bloques

```
                 +--------+  imem_data (128 b)
   pc --------->|  memory |----------------------+
    ^            +--------+                      v
    |                                    +--------------+
 +-------+     redirect (EX)             |   IF / ID    |  bundle, pc, valid
 | fetch |<------------------------------+--------------+
 +-------+                                      |
                                           +----v-----+
                                           | dispatch |  4 slots, 8 direcciones de lectura,
                                           +----+-----+  5 de escritura, illegal_op
                                                |
              +----------------+                |
              |    regfile     |<---------------+
              | 8R / 5W, r0=0  |
              +-------+--------+
                      | rdata (8 x 32)
                 +----v-----+   ID / EX  (bundle, pc, rdata, valid)
                 |  ID/EX   |
                 +----+-----+
    +---------+-------+--------+-----------------+
    |         |       |        |                 |
 +--v--+  +---v--+ +--v--+ +---v-----------------v----+
 | ALU |  | LSU  | | BRU | |  crypto_unit  (SR)       |
 | s0  |  | s1   | | s2  | |  s3   +--> key_vault     |
 +--+--+  +---+--+ +--+--+ +---+----------------------+
    |         |       |        |
    |         |       |        +-- (FROUND: 2 resultados)
    +----+----+---+---+--------+
         v        v
      +--------------+   EX / WB  (5 puertos de escritura)
      |   EX/WB reg  |------------------------------> regfile (WB)
      +--------------+
          LSU <----> memory (puerto de datos de 32 b, lectura combinacional, escritura en EX)
```

## 2. Etapas

| Etapa | Qué hace |
|---|---|
| IF | `fetch` entrega el PC; `memory` devuelve el bundle de 128 bits en el mismo ciclo. El PC avanza 16 por ciclo. Un salto tomado en EX redirige el PC; `FIN` lo detiene |
| ID | `dispatch` separa los 4 slots y extrae los registros que cada uno lee y escribe. El banco de registros se lee con 8 puertos. No hay bypass: una escritura de WB solo se ve en lecturas de bundles posteriores |
| EX | ALU, LSU, BRU y unidad cripto trabajan en paralelo sobre sus slots. La memoria se escribe y el SR/bóveda se actualizan al final de EX. El salto se resuelve aquí |
| WB | Escribe en el banco hasta 5 resultados: ALU, LSU, enlace de `SYE` (`r31`) y los dos de `FROUND` |

### Registros de pipeline

| Registro | Contenido |
|---|---|
| IF/ID | `ifid_bundle` (128 b), `ifid_pc`, `ifid_valid` |
| ID/EX | `idex_bundle`, `idex_pc`, `idex_rdata` (8 × 32 b), `idex_valid` |
| EX/WB | `exwb_wen` (5), `exwb_waddr` (5 × 5 b), `exwb_wdata` (5 × 32 b), `exwb_fin` |

`ifid_valid` e `idex_valid` se anulan cuando un salto tomado descarta bundles.

## 3. Puertos del banco de registros

| Puertos de lectura (8) | Slot | Qué lee |
|---|---|---|
| 0, 1 | 0 ALU | `rs1`, `rs2` |
| 2, 3 | 1 LSU | `rbase`, registro a almacenar |
| 4, 5 | 2 BRU | `rs1`, `rs2` (el `SRG` usa el 4) |
| 6, 7 | 3 Cripto | `rs_L`, `rs_R` (o la fuente de `LOADKEY`/`AUTH`) |

| Puertos de escritura (5) | Origen |
|---|---|
| 0 | ALU `rd` |
| 1 | LSU `rd` (carga) |
| 2 | enlace de `SYE` (siempre `r31`) |
| 3, 4 | `FROUND` `rd_L` y `rd_R` |

**Por qué 8 y 5:** cada slot es independiente y el compilador puede llenarlos todos en un bundle.
Los 4 slots leen como máximo 2 registros cada uno (8 puertos) y pueden producir cinco resultados:
una ALU, una carga, un enlace y los dos de `FROUND`. Con menos puertos habría bundles legales que
el hardware no podría ejecutar. Si dos puertos escriben el mismo registro en el mismo ciclo gana el
de índice mayor; el compilador no lo genera nunca (regla WAW) y el monitor lo reporta.

## 4. Aislamiento de la bóveda

* `key_vault` guarda 4 llaves × 4 subllaves de 32 bits. Su **única escritura** es `LOADKEY`
  (`we = SR.AUTH & loadkey_valid`) y su **única lectura** es el puerto `rdata`, conectado solo a la
  función F de `FROUND`. No existe ningún camino hacia un GPR ni hacia la memoria.
* `FROUND` solo escribe resultados si `SR.AUTH = 1` (`fround_we = SR.AUTH & fround_valid`). Sin
  sesión, no cambia los registros y registra `VAULT_ERR` y `ERR_CODE = 001`.
* `AUTH` con una credencial distinta de `0xCAFE1234` deja `ERR_CODE = 010`. `LOGOUT` cierra la sesión.
  El estado se lee con `RDSR` (bit 0 AUTH, bit 1 VAULT_ERR pegajoso, bits 4:2 ERR_CODE).
* Los testbenches `tb_key_vault` y `tb_crypto_unit` comprueban el bloqueo; el programa `boveda.asm`
  lo comprueba extremo a extremo y exige que ninguna subllave aparezca en un registro (`forbid`).

## 5. Cronogramas

### Dependencia RAW (distancia 3)

```
bundle        ciclo:  1    2    3    4    5    6    7
B0  SUMI r8 ...       IF   ID   EX   WB
B1  (otro)                 IF   ID   EX   WB
B2  (otro)                      IF   ID   EX   WB
B3  SUM r9, r8, ...                  IF   ID   EX   WB
                                          ^ lee r8: la escritura de B0 se hizo en WB (ciclo 4)
                                            y B3 la lee en ID (ciclo 5)
```

Con B1 (distancia 1) o B2 (distancia 2) el bundle leería el valor viejo y el monitor lo reporta
como riesgo RAW.

### Salto tomado (se descartan 2 bundles)

```
bundle        ciclo:  1    2    3    4    5    6
B0  SIG ..., etq      IF   ID   EX*  WB            * resuelve y redirige el PC
B1  (siguiente)            IF   ID   --            descartado
B2  (siguiente)                 IF   --            descartado
T0  (destino)                        IF   ID   EX  primer bundle del destino
```

El destino se ejecuta 3 bundles después del salto (`e+3`): por eso toda escritura del bloque ya es
visible allí. Si el salto no se toma, B1 y B2 se ejecutan normalmente.

## 6. Módulos y archivos

| Módulo | Archivo | Función |
|---|---|---|
| `vliw_pkg` | `rtl/vliw_pkg.sv` | constantes, `rol32`, función F de Feistel4 |
| `memory` | `rtl/memory.sv` | 1 MiB en bytes; puerto de fetch de 128 b y de datos de 32 b |
| `regfile` | `rtl/regfile.sv` | 32 × 32 b, 8R/5W, `r0` constante 0 |
| `alu` | `rtl/alu.sv` | aritmética con signo, lógica, desplazamientos, `COMP`; `DIV` por 0 da `0xFFFFFFFF` |
| `lsu` | `rtl/lsu.sv` | `CP`/`AP` con dirección `rbase + offset` |
| `bru` | `rtl/bru.sv` | condicionales, `S`, `SYE`, `SRG`, `FIN` |
| `key_vault` | `rtl/key_vault.sv` | bóveda de llaves |
| `crypto_unit` | `rtl/crypto_unit.sv` | `LOADKEY`, `FROUND`, `AUTH`, `LOGOUT`, `RDSR` y el SR |
| `dispatch` | `rtl/dispatch.sv` | separación de slots y extracción de registros; detección de opcode ilegal |
| `fetch` | `rtl/fetch.sv` | PC, redirección y parada |
| `core` | `rtl/core.sv` | pipeline IF/ID/EX/WB y registros entre etapas |
| `top` | `rtl/top.sv` | `core` + `memory` |

Instrucciones ilegales (opcode fuera de su slot, `funct` inexistente) incrementan `illegal_cnt` y se
tratan como NOP; el banco de pruebas las informa en la línea `HALT`.