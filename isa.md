# Especificación del ISA — Feistel4-VLIW

**Curso:** CE-4301 Arquitectura de Computadores I
**Grupo:** 2
**Entrega 1 — Especificación del ISA**

## Resumen

| Parámetro | Valor |
|---|---|
| Filosofía | RISC, registro-registro |
| Ancho de bundle | 128 bits |
| Slots por bundle | 4 (32 bits cada uno) |
| Asignación de slots | Fija: 1× ALU, 1× LSU, 1× BRU, 1× Unidad Criptográfica y Seguridad (Feistel4 + AUTH/LOGOUT/RDSR) |
| Registros de propósito general | 32 (5 bits por campo de registro) |
| Ancho de registro | 32 bits |
| Direccionamiento de memoria | Byte-addressable, alineado |
| Endianness | Big-Endian |
| Ancho de dirección | 32 bits |
| Tamaño mínimo de memoria | Mínimo 64 KB |
| Punto flotante | No soportado |
| Tipos de instrucción | 6 — nomenclatura **RIMCFS** (Registro, Inmediato, Memoria, Control, Feistel, Seguridad) |
| Codificación general | Opcode 3 bits, funct 4 bits |
| Program Counter | 32 bits, valor de reset: `0x00000000`, avanza de  16 en 16 bytes (al siguiente bundle) |
| Registro de estado (SR) | 32 bits, registro **aparte del banco de GPRs** (no es un GPR) — ver sección "Registro de Estado (SR)" |

## Formato de instrucción (dentro de cada slot)

```
 31                                   ...                                    3   2 1 0
[                     campos según tipo de instrucción                    ] [ funct ] [opcode]
```

- **Opcode** (bits `[2:0]`): identifica el tipo de instrucción (Registro, Inmediato, Memoria, Control, Cripto, Seguridad).
- **Funct** (bits `[6:3]`): dentro de cada tipo, selecciona la operación específica (SUM, REST, MUL, …).
- Los campos restantes (`rs1`, `rs2`, `rd`, inmediatos, offsets) varían según el tipo — ver tablas abajo.

La vista a nivel de bundle (diagrama de cómo se acomodan los 4 slots dentro de los 128 bits) está en la sección **"Formato de Bundle y Slots"** → "Distribución de bits del bundle".

## Formato de Bundle y Slots

- **Ancho del bundle:** 128 bits, dividido en 4 slots de 32 bits.
- **Esquema de asignación:** se utilizan slots fijos, donde cada slot está atado permanentemente a un tipo de unidad funcional: 1 slot para ALU, 1 para LSU, 1 para BRU, 1 para la Unidad Criptográfica y de Seguridad (Feistel4 + AUTH/LOGOUT/RDSR).
- **Justificación:** un esquema de slots fijos simplifica el datapath y su decodificación, ya que cada slot corresponde directamente a su unidad funcional. Además garantiza que el cómputo general (ALU/LSU/BRU) y el cómputo criptográfico puedan ejecutarse de forma independiente dentro del mismo bundle.

> ⚠️ **Falta — obligatorio (Sec. 4.1.1):** **codificación de NOP por slot.** Actualmente solo existe el opcode/funct de cada instrucción real; no está definido qué patrón de bits en el slot de ALU, LSU, BRU o Cripto significa "este slot no ejecuta nada este ciclo". Debe definirse (por ejemplo, reservando un funct específico dentro de cada tipo, o un opcode reservado) y quedar documentado explícitamente, uno por cada uno de los 4 slots.

### Distribución de bits del bundle

```
 127            96 95             64 63             32 31              0
┌─────────────────┬─────────────────┬─────────────────┬─────────────────┐
│      Slot 0     │      Slot 1     │      Slot 2     │      Slot 3     │
│       ALU       │       LSU       │       BRU       │ Cripto/Seguridad│
│  opcode 000/001 │    opcode 010   │    opcode 011   │  opcode 100/101 │
│   PC+0 .. PC+3  │   PC+4 .. PC+7  │  PC+8 .. PC+11  │  PC+12 .. PC+15 │
└─────────────────┴─────────────────┴─────────────────┴─────────────────┘
```

| Slot | Bits del bundle | Bytes en memoria | Unidad funcional | Opcodes válidos en el slot |
|---|---|---|---|---|
| 0 | `[127:96]` | `PC+0` … `PC+3` | ALU | `000` (Registro), `001` (Inmediato) |
| 1 | `[95:64]` | `PC+4` … `PC+7` | LSU | `010` (Memoria) |
| 2 | `[63:32]` | `PC+8` … `PC+11` | BRU | `011` (Control) |
| 3 | `[31:0]` | `PC+12` … `PC+15` | Unidad Criptográfica y de Seguridad | `100` (Criptografía), `101` (Seguridad) |

- **Orden de los slots:** como la memoria es Big-Endian, el slot 0 ocupa los bits más significativos del bundle y es el primero en memoria. El bit 31 del slot 0 corresponde al bit 127 del bundle, y el bit 0 del slot 3 al bit 0 del bundle.
- **Tamaño y alineación:** cada bundle ocupa 16 bytes consecutivos y empieza en una dirección múltiplo de 16. Esto es consistente con el avance del PC de 16 bytes por bundle usado en la estrategia de saltos.
- **Codificación dentro del slot:** los 32 bits de cada slot siguen exactamente las tablas de "Codificación por Tipo de Instrucción".
- **Opcodes fuera de su slot:** una instrucción con un opcode que no corresponde a su slot (por ejemplo, un `011` en el slot de la ALU) es una codificación inválida y el ensamblador debe rechazarla.
- **Emisión:** las cuatro instrucciones de un bundle se emiten juntas. Las dependencias entre ellas las resuelve el compilador.

### Ubicación de las instrucciones de Seguridad (AUTH, LOGOUT, RDSR)

**Decisión de Diseño:** las instrucciones de tipo Seguridad comparten el slot 3 con las instrucciones de Criptografía. La unidad de ese slot pasa a llamarse Unidad Criptográfica y de Seguridad, y distingue qué ejecutar por el opcode: `100` para Criptografía (`LOADKEY`, `FROUND`) y `101` para Seguridad (`AUTH`, `LOGOUT`, `RDSR`).

**Justificación:**

1. **Controlan el mismo recurso.** Las instrucciones de Seguridad existen solo para habilitar o consultar el acceso a la bóveda de llaves, y el registro de estado ya se define como modificado únicamente por `AUTH`, `LOGOUT` y la lógica de error de la Unidad Criptográfica. Ponerlas en el mismo slot deja en una sola unidad funcional todo lo que toca la bóveda y el bit `SR.AUTH`.
2. **Respeta el formato fijo del bundle.** El bundle es de 128 bits con 4 slots de 32 bits y no se amplía. Con 6 tipos de instrucción y 4 slots, algunos slots deben atender más de un tipo: así como el slot de la ALU atiende los tipos Registro e Inmediato, el slot 3 atiende Criptografía y Seguridad. Esto es consistente con el enunciado (Sec. 4.5), que agrupa en una sola categoría las instrucciones de la Unidad Criptográfica Feistel4 y de manejo de la bóveda de llaves, por lo que cada bundle puede seguir combinando libremente instrucciones de ALU, memoria, control y criptografía/bóveda.
3. **Evita ambigüedad dentro de un bundle.** Como una instrucción de Seguridad y una de Criptografía no pueden ir en el mismo bundle, no existe el caso de un `AUTH` y un `FROUND` emitidos juntos donde haya que definir cuál ve primero el bit de autenticación.

**Alternativa descartada:** se consideró asignar a las instrucciones de Seguridad un slot propio, pero se descartó porque obligaría a ampliar el bundle a 5 slots (160 bits), y el formato del bundle está fijo en 128 bits con 4 slots.

**Consecuencia de compartir el slot:** una instrucción de Seguridad y una de Criptografía no pueden ir en el mismo bundle, por lo que quien genera el código debe colocarlas en bundles distintos. Como `AUTH`, `LOGOUT` y `RDSR` son poco frecuentes frente a `FROUND`, el impacto en rendimiento es despreciable.

## Unidades Funcionales

| # | Unidad | Instrucciones que atiende |
|---|--------|---------------------------|
| 1 | **ALU** — Aritmético-lógica | SUM, REST, MUL, DIV, OLY, OLO, LOE, DLI, DLD, COMP, y sus variantes inmediatas (SUMI, RESTI, MULI, DIVI, DLII, DLDI) |
| 2 | **LSU** — Carga/almacenamiento | CB, CP (load byte/word), AB, AP (store byte/word) |
| 3 | **BRU** — Control de flujo | SIG, SNIG, SMI, SMQ (branches), S (jump) |
| 4 | **Unidad Criptográfica y de Seguridad** | LOADKEY, FROUND (Criptografía, opcode `100`) y AUTH, LOGOUT, RDSR (Seguridad, opcode `101`) — única unidad con acceso a la bóveda de llaves y al bit de autenticación del SR |

Las instrucciones de Seguridad comparten el slot de la Unidad Criptográfica; la decisión y su justificación están en "Formato de Bundle y Slots" → "Ubicación de las instrucciones de Seguridad".

## Banco de Registros, PC y Registro de Estado

- 32 registros de propósito general de 32 bits, campo de registro de 5 bits.
- **Justificación de 32 registros:** al ser una arquitectura VLIW, es el compilador (o el ensamblador) quien calendariza las instrucciones dentro de cada bundle. Contar con 32 registros evita dependencias falsas entre instrucciones, da margen para mantener variables vivas en registros, y facilita llenar los 4 slots de un bundle con instrucciones independientes — maximizando el paralelismo estático.

### Program Counter (PC)

El Program Counter (PC) es un registro especial de **32 bits** que contiene la dirección del bundle que se está ejecutando. Debido a que cada bundle VLIW tiene un tamaño de 128 bits, equivalente a 16 bytes, el PC avanza normalmente de 16 en 16 bytes.

Por lo tanto, durante la ejecución secuencial:

`PC_siguiente = PC + 16`

El valor de reset del PC es `0x00000000`, por lo que la ejecución de un programa
inicia en la dirección `0x00000000`.

Las instrucciones de control pueden modificar el flujo normal del PC. En los
saltos relativos, la dirección destino se calcula con respecto al siguiente
bundle:

`PC_destino = PC + 16 + (SignExtend(offset) × 16)`

Como los bundles tienen 16 bytes y se almacenan alineados, las direcciones de inicio de bundles son múltiplos de 16.

> ⚠️ **Falta (recomendado, no obligatorio):** convención de registros — ¿hay algún registro reservado (por ejemplo un registro cero, como suele hacerse en RISC), o los 32 son de uso completamente libre? Vale la pena dejarlo explícito para el ensamblador y para la contraparte de CE1108.


### Registro de Estado (SR) 

El **SR es un registro especial de 32 bits, separado del banco de registros de propósito general.** No tiene número de registro dentro del campo `rd`/`rs` de ninguna instrucción aritmética, de memoria, etc. — ninguna instrucción genérica puede escribirle un valor arbitrario. Esto es intencional: si el SR fuera un GPR más, cualquier instrucción aritmética podría poner el bit de autenticación en 1 sin pasar por `AUTH`, y la autenticación sería solo una convención de software, no una restricción real de hardware.

Las **únicas** fuentes que pueden modificar el SR son: `AUTH`, `LOGOUT`, y la lógica interna de la Unidad Criptográfica cuando detecta un acceso no autorizado a la bóveda.

| Bit(s) | Nombre | Escrito por | Significado |
|---|---|---|---|
| `0` | `AUTH` | `AUTH` (éxito → 1), `LOGOUT` (→ 0) | 1 = sesión autenticada activa; la bóveda es accesible para `LOADKEY`/`FROUND`. |
| `1` | `VAULT_ERR` | Unidad Criptográfica | Bit **sticky**: se pone en 1 cuando `LOADKEY` o `FROUND` se ejecutan con `AUTH = 0`. No se autolimpia — permanece en 1 hasta el siguiente `AUTH` exitoso. |
| `4:2` | `ERR_CODE` | Unidad Criptográfica | Causa del último error (3 bits). `000` = sin error. `001` = acceso no autorizado a bóveda. `010`–`111` = reservado para futuras causas, sin tener que rediseñar el registro. |
| `31:5` | reservado | — | Fijo en 0. |

**Semántica de escritura:**
- `AUTH rs_cred` (éxito) → `SR.AUTH ← 1`, `SR.VAULT_ERR ← 0`, `SR.ERR_CODE ← 000` (una autenticación exitosa limpia cualquier error previo).
- `LOGOUT` → `SR.AUTH ← 0`. No toca `VAULT_ERR`/`ERR_CODE`.
- `LOADKEY` / `FROUND` con `SR.AUTH = 1` → ejecutan normal, SR no cambia.
- `LOADKEY` / `FROUND` con `SR.AUTH = 0` → **la operación se convierte en NOP arquitectónico**: no escriben la bóveda ni el/los registro(s) destino, y además `SR.VAULT_ERR ← 1`, `SR.ERR_CODE ← 001`.

**Cómo cumple con la Sec. 4.4.1 ("las operaciones no autorizadas deberán generar una excepción o error de acceso"):** el bloqueo ocurre en **hardware**, en la señal de write-enable de la Unidad Criptográfica — no depende de que el software "se porte bien" y consulte el bit antes de operar. La ecuación de control es literalmente:

```
vault_we  = SR.AUTH & loadkey_valid
fround_we = SR.AUTH & fround_valid
```

Si `SR.AUTH = 0`, esas señales son 0 sin importar qué instrucción venga codificada en el slot — la bóveda nunca se toca sin autenticación. El bit `VAULT_ERR` es lo que hace que ese bloqueo sea *observable* (por el testbench, y por software si se agrega una instrucción de lectura — ver `RDSR` abajo), que es lo que el enunciado pide como "error de acceso". No implica trap, vector de interrupción, ni guardar/restaurar PC — no es necesario para cumplir el requisito y complicaría mucho el pipeline sin ningún beneficio real para este proyecto.

**Instrucción de lectura — `RDSR`:** para que el compilador de CE1108 (o cualquier programa) pueda *enterarse* de que hubo un error de acceso y reaccionar (por ejemplo, reintentar `AUTH`, o abortar), se agrega una instrucción de lectura del SR hacia un GPR. Se añade al tipo **Seguridad**, junto a `AUTH`/`LOGOUT` — ver tabla de codificación abajo. Sin esta instrucción, `VAULT_ERR`/`ERR_CODE` solo serían visibles desde el testbench (mirando la señal interna), nunca desde un programa en ejecución.

---
### Direccionamiento y Memoria

La arquitectura utiliza direcciones de **32 bits** y memoria **byte-addressable**,
lo que significa que cada dirección numérica identifica un byte individual. El espacio de
direccionamiento teórico es de `2^32` bytes, equivalente a **4 GiB**.

Sin embargo, la implementación planteada debe soportar como mínimo **64 KiB de memoria física**.
Este tamaño mínimo no limita el formato de las direcciones del ISA, que permanece
en 32 bits. La arquitectura utiliza representación **Big-Endian**. Por lo tanto, al almacenar
una palabra de 32 bits, el byte más significativo se ubica en la dirección de
memoria más baja.

Para las instrucciones `load` y `store` se utiliza **direccionamiento base +
desplazamiento (base + offset)**. La dirección efectiva se calcula como:

`direccion_efectiva = GPR[rbase] + SignExtend(offset)`

donde `rbase` es un registro de propósito general que contiene la dirección base
y `offset` es el inmediato con signo de 15 bits codificado en la instrucción. `GPR[rbase]` es el contenido de un registro de propósito general ($rbase$) que guarda una dirección "punto de partida". 

Este modo de direccionamiento permite acceder a posiciones cercanas a una
dirección base utilizando una sola instrucción, sin requerir una operación
aritmética adicional para calcular cada dirección.

Los accesos de palabra (`CP` y `AP`) transfieren 32 bits (4 bytes) y deben
realizarse sobre direcciones alineadas a 4 bytes.

---
## Codificación por Tipo de Instrucción

### Tipo Registro (opcode `000`)

| Inst. | opt `[31:22]` | rs1 `[21:17]` | rs2 `[16:12]` | rd `[11:7]` | funct `[6:3]` | opcode `[2:0]` |
|-------|------|------|------|------|------|------|
| SUM (ADD)   | 0000000000 | rs1 | rs2 | rd | 0000 | 000 |
| REST (SUB)  | 0000000000 | rs1 | rs2 | rd | 0001 | 000 |
| MUL         | 0000000000 | rs1 | rs2 | rd | 0010 | 000 |
| DIV         | 0000000000 | rs1 | rs2 | rd | 0011 | 000 |
| OLY (AND)   | 0000000000 | rs1 | rs2 | rd | 0100 | 000 |
| OLO (OR)    | 0000000000 | rs1 | rs2 | rd | 0101 | 000 |
| LOE (XOR)   | 0000000000 | rs1 | rs2 | rd | 0110 | 000 |
| DLI (shift izq.) | 0000000000 | rs1 | rs2 | rd | 0111 | 000 |
| DLD (shift der.) | 0000000000 | rs1 | rs2 | rd | 1000 | 000 |
| COMP        | 0000000000 | rs1 | rs2 | rd | 1001 | 000 |

### Tipo Inmediato (opcode `001`)

Campo de inmediato de 15 bits total, partido entre bit 31 (MSB, `imm[14]`) y bits `[25:12]` (`imm[13:0]`).

| Inst. | imm[14] `[31]` | rs1 `[30:26]` | imm[13:0] `[25:12]` | rd `[11:7]` | funct `[6:3]` | opcode `[2:0]` |
|-------|------|------|------|------|------|------|
| SUMI (ADDI)  | imm[14] | rs1 | imm[13:0] | rd | 0000 | 001 |
| RESTI (SUBI) | imm[14] | rs1 | imm[13:0] | rd | 0001 | 001 |
| MULI         | imm[14] | rs1 | imm[13:0] | rd | 0010 | 001 |
| DIVI         | imm[14] | rs1 | imm[13:0] | rd | 0011 | 001 |
| DLII (shift izq. inm.) | imm[14] | rs1 | imm[13:0] | rd | 0100 | 001 |
| DLDI (shift der. inm.) | imm[14] | rs1 | imm[13:0] | rd | 0101 | 001 |

### Tipo Acceso a Memoria (opcode `010`)

Mismo esquema de campo partido que el tipo Inmediato (offset de 15 bits, `imm[14]` en bit 31 + `imm[13:0]` en `[25:12]`), con `rbase` como registro base.

| Inst. | imm[14] `[31]` | rbase `[30:26]` | imm[13:0] `[25:12]` | rd `[11:7]` | funct `[6:3]` | opcode `[2:0]` |
|-------|------|------|------|------|------|------|
| CP (LW — load word)  | imm[14] | rbase | imm[13:0] | rd | 0000 | 010 |
| AP (SW — store word) | imm[14] | rbase | imm[13:0] | rd | 0001 | 010 |
| CB (LB — load byte)  | ⚠️ **falta funct** | rbase | imm[13:0] | rd | ⚠️ **falta** | 010 |
| AB (SB — store byte) | ⚠️ **falta funct** | rbase | imm[13:0] | rd | ⚠️ **falta** | 010 |

> ⚠️ **Falta:** las filas de `CB` (load byte) y `AB` (store byte) están definidas como mnemónicos en la lista de instrucciones, pero **no tienen codificación (funct) asignada** en el material actual — solo `CP` y `AP` (word) tienen fila completa. Hay que asignarles su `funct` (por ejemplo `0010` y `0011`) para que el set quede completo.

### Tipo Control (opcode `011`)

| Inst. | Offset `[31:17]` | rs1 `[16:12]` | rs2 `[11:7]` | funct `[6:3]` | opcode `[2:0]` |
|-------|------|------|------|------|------|
| SIG (BEQ)   | offset | rs1 | rs2 | 0000 | 011 |
| SNIG (BNE)  | offset | rs1 | rs2 | 0001 | 011 |
| SMI (BGE)   | offset | rs1 | rs2 | 0010 | 011 |
| SMQ (BLT)   | offset | rs1 | rs2 | 0011 | 011 |


#### Salto incondicional S

La instrucción `S` utiliza un formato diferente a los saltos condicionales,
debido a que no requiere registros fuente.

| Inst. | Offset `[31:7]` | funct `[6:3]` | opcode `[2:0]` |
|-------|------------------|---------------|----------------|
| S (JMP) | offset | 0100 | 011 |

El campo `offset` es un valor con signo de 25 bits y representa una cantidad
de bundles relativa al siguiente bundle.

`PC_destino = PC + 16 + (SignExtend(offset) × 16)`
#### Estrategia de saltos

Las instrucciones de control utilizan direccionamiento relativo al Program
Counter (PC). Debido a que cada bundle VLIW tiene un tamaño de 128 bits,
equivalente a 16 bytes, el PC avanza 16 bytes por cada bundle.

Para los saltos condicionales (`SIG`, `SNIG`, `SMI` y `SMQ`), el campo
`offset` representa una cantidad de bundles relativa al siguiente bundle.

La dirección destino se calcula como:

`PC_destino = PC + 16 + (SignExtend(offset) × 16)`

No se utilizarán branch delay slots visibles para el programador. Cuando un
salto sea tomado, el PC se actualiza con la dirección destino y los bundles
obtenidos por el flujo secuencial que ya no correspondan deberán ser
descartados. La cantidad exacta de bundles a descartar dependerá de la
organización del pipeline definida en la Entrega 2.

Los saltos condicionales utilizan un offset con signo de 15 bits, mientras que
el salto incondicional `S` utiliza un offset con signo de 25 bits.

### Tipo Criptografía — Feistel4 (opcode `100`)

| Inst. | opt `[31]` | rd_L `[30:26]` | rd_R `[25:21]` | idx2 `[20:19]` | idx1 `[18:17]` | rs_L `[16:12]` | rs_R `[11:7]` | funct `[6:3]` | opcode `[2:0]` |
|-------|---|------|------|------|------|------|------|------|------|
| LOADKEY | 0 | 00000 | 00000 | subkey_idx | key_idx | 00000 | src | 0000 | 100 |
| FROUND  | 0 | destL | destR | round_idx | key_idx | srcL | srcR | 0001 | 100 |

- `LOADKEY rs, key_idx, subkey_idx`: escribe el valor de 32 bits de `rs` (registro de propósito general) en `bóveda[key_idx][subkey_idx]`. Solo escritura — no hay instrucción de lectura de vuelta desde la bóveda hacia registros.
- `FROUND rs_L, rs_R, key_idx, round_idx, rd_L, rd_R`: ejecuta una ronda completa de Feistel4 tomando la subllave `bóveda[key_idx][round_idx]` internamente (sin exponerla en ningún registro), calcula `F(R,k) = ROL(R,5) + k` XOR `ROL(R,13)`, produce `L' = R`, `R' = L` XOR `F(R,k)`.

**Cumplimiento de las restricciones de la bóveda (Sec. 4.4.1):**
- `LOADKEY` es la única instrucción que escribe en la bóveda, y lo hace desde un registro de propósito general — nunca al revés.
- `FROUND` es la única instrucción que **lee** de la bóveda (como fuente de subllave), y la subllave nunca se materializa en un registro visible al programa.
- Con esto se cumple que las llaves no pueden llegar a registros de propósito general ni a memoria general, y que solo la(s) instrucción(es) de ronda acceden a la bóveda como operando fuente.

### Tipo Seguridad (opcode `101`)

| Inst. | opt `[31:12]` | rd `[11:7]` | funct `[6:3]` | opcode `[2:0]` |
|-------|---|------|------|------|
| AUTH   | 0000000000000000000 | rs_cred | 0000 | 101 |
| LOGOUT | 0000000000000000000 | 00000 | 0001 | 101 |
| RDSR   | 0000000000000000000 | rd | 0010 | 101 |

- `AUTH rs_cred`: compara `rs_cred` contra la credencial esperada; si coincide, activa el bit de autenticado en el registro de estado (`SR.AUTH ← 1`, y limpia `VAULT_ERR`/`ERR_CODE`).
- `LOGOUT`: sin operandos; desactiva el bit de autenticado (`SR.AUTH ← 0`).
- `RDSR rd`: **rd ← SR** (copia el registro de estado completo de 32 bits a un registro de propósito general). Es de **solo lectura** — no existe la operación inversa ("WRSR"): el SR nunca se puede escribir con un valor arbitrario, solo a través de `AUTH`/`LOGOUT` y de la lógica de error de la Unidad Criptográfica. Con esto el software (o el compilador de CE1108) puede consultar `SR.AUTH`, `SR.VAULT_ERR` y `SR.ERR_CODE` después de una operación de bóveda, sin poder falsificar ninguno de esos bits.

**Mecanismo de error de acceso (Sec. 4.4.1) — resuelto:** ver la sección "Registro de Estado (SR)" arriba. El bloqueo real ocurre en hardware (write-enable de la Unidad Criptográfica condicionada por `SR.AUTH`); `VAULT_ERR`/`ERR_CODE` son lo que hace ese error observable, y `RDSR` es cómo el software llega a leerlo.

---

## Tabla resumen de Opcodes (green sheet)

| Tipo | Opcode | Instrucciones |
|------|--------|----------------|
| Registro | `000` | SUM, REST, MUL, DIV, OLY, OLO, LOE, DLI, DLD, COMP |
| Inmediato | `001` | SUMI, RESTI, MULI, DIVI, DLII, DLDI |
| Memoria | `010` | CP, AP, CB ⚠️, AB ⚠️ |
| Control | `011` | SIG, SNIG, SMI, SMQ, S |
| Criptografía | `100` | LOADKEY, FROUND |
| Seguridad | `101` | AUTH, LOGOUT, RDSR |
| — (NOP por slot) | ⚠️ **falta** | — |

---

## Limitaciones del ISA (borrador)

1. No hay soporte de punto flotante.
2. Los inmediatos y los offsets de los saltos condicionales tienen 15 bits. El salto incondicional `S` dispone de un offset con signo de 25 bits.
3. 3. Slots fijos por unidad funcional: si un bundle no necesita, por ejemplo, ALU ese ciclo, ese slot debe llenarse con NOP (ver pendiente de codificación de NOP).
4. El hardware no resuelve riesgos de datos ni de control automáticamente (sin forwarding ni scoreboarding entre slots o bundles) — la calendarización estática es responsabilidad de quien genera el código (ensamblador propio o compilador de CE1108).
5. ⚠️ **Falta completar esta sección** con las limitaciones reales una vez cerrados los pendientes (rango de direccionamiento, estrategia de saltos, etc.).

---

## Ejemplo de Programa

> ⚠️ **Falta por completo — recomendado, no estrictamente exigido pero refuerza mucho la entrega:** un ejemplo de programa **a nivel de bundle** (como el "Program 1" del sp4r7an de referencia), mostrando varios ciclos con los 4 slots codificados en cada uno — incluyendo slots en NOP cuando no se usan — y no solo instrucciones sueltas. Esto demuestra que el formato de bundle completo funciona en la práctica y sirve como referencia para el ensamblador propio y para la contraparte de CE1108.

```
Ciclo  Slot ALU        Slot LSU        Slot BRU        Slot Cripto      Comentario
─────  ──────────────  ──────────────  ──────────────  ───────────────  ─────────────────────
  0    [pendiente]     [pendiente]     [pendiente]     [pendiente]      [pendiente]
```

---

## ⚠️ Pendientes para la Entrega 1 (resumen)

Checklist de todo lo señalado arriba, agrupado, para no perder nada antes de subir a TEC Digital:

- [ ] **Codificación de NOP por slot** (una por cada una de las 4 unidades funcionales) — Sec. 4.1.1, obligatorio.
- [x] **Diagrama del bundle completo de 128 bits:** resuelto — diagrama y tabla en "Distribución de bits del bundle" (4 slots, rangos de bits, unidad funcional, opcodes válidos y bytes en memoria).
- [x] **Resolver dónde encajan las instrucciones de tipo Seguridad:** resuelto — AUTH/LOGOUT/RDSR comparten el slot 3 con Criptografía (Unidad Criptográfica y de Seguridad); el bundle se mantiene en 4 slots y 128 bits. Ver "Ubicación de las instrucciones de Seguridad".
- [x] **Estrategia frente a saltos** (branch delay slot(s) o vaciado de pipeline) — Sec. 4.1.2, obligatorio.
- [ ] **Program Counter:** ancho y dirección/valor de reset — Sec. 4.5, obligatorio.
- [x] **Registro de estado:** resuelto — 32 bits, registro aparte del banco de GPRs (`AUTH`, `VAULT_ERR`, `ERR_CODE`), solo escribible por `AUTH`/`LOGOUT`/lógica de error de la Unidad Cripto. Ver sección "Registro de Estado (SR)".
- [x] **Mecanismo de excepción/error de acceso:** resuelto — bloqueo por hardware vía write-enable condicionado por `SR.AUTH` (no trap/interrupción); error observable vía `SR.VAULT_ERR`/`ERR_CODE` y nueva instrucción `RDSR` (tipo Seguridad) para que el software lo lea.
- [ ] **Ancho de direccionamiento (32 bits)** y **tamaño mínimo de memoria (64 KB)** — confirmarlos explícitamente en el documento — Sec. 4.5, obligatorio.
- [ ] **Codificación faltante de `CB` y `AB`** (load/store byte) en la tabla de tipo Memoria.
- [x] **Codificación faltante de `S`** (jump incondicional) en la tabla de tipo Control.
- [ ] (Recomendado) **Ejemplo de programa a nivel de bundle**, con NOPs incluidos.
- [ ] (Recomendado) Aclarar si hay algún **registro reservado** (ej. registro cero) o los 32 son de uso libre.
- [ ] Completar la sección de **Limitaciones del ISA** una vez cerrados los puntos anteriores.
- [x] Revisar que el documento **no incluya el pipeline/microarquitectura** (Sec. 4.1.3 nota): resuelto — el boceto de datapath no se incluye en este documento y se agregó la nota "Alcance del documento" al inicio. Las ecuaciones de write-enable de la sección del SR quedan marcadas como ilustrativas.
