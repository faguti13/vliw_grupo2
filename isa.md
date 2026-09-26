# Especificación del ISA — Feistel4-VLIW

**Curso:** CE-4301 Arquitectura de Computadores I
**Grupo:** 2
**Entrega 1 — Especificación del ISA**

> ⚠️ **Nota general antes de entregar:** este documento se armó a partir de lo avanzado hasta ahora. Al final hay una sección **"Pendientes para Entrega 1"** con todo lo que el enunciado (Sec. 4.5, 4.1.1, 4.1.2 y el rubro 8.1) exige y que aún no está resuelto en el material actual. Revísenla y complétenla antes de subir el documento — son puntos que si faltan, se pierden directamente en la rúbrica de la Entrega 1 (20%).

---

## Resumen

| Parámetro | Valor |
|---|---|
| Filosofía | RISC, registro-registro |
| Ancho de bundle | 128 bits |
| Slots por bundle | 4 (32 bits cada uno) |
| Asignación de slots | Fija: 1× ALU, 1× LSU, 1× BRU, 1× Unidad Criptográfica (Feistel4) |
| Registros de propósito general | 32 (5 bits por campo de registro) |
| Ancho de registro | 32 bits |
| Direccionamiento de memoria | Byte-addressable, alineado |
| Endianness | Big-Endian |
| Ancho de dirección | ⚠️ **[FALTA — ver Pendientes]** (enunciado exige 32 bits) |
| Tamaño mínimo de memoria | ⚠️ **[FALTA — ver Pendientes]** (enunciado exige mínimo 64 KB) |
| Punto flotante | No soportado |
| Tipos de instrucción | 6 — nomenclatura **RIMCFS** (Registro, Inmediato, Memoria, Control, Feistel, Seguridad) |
| Codificación general | Opcode 3 bits, funct 4 bits |
| Program Counter | ⚠️ **[FALTA — ver Pendientes]** (ancho, valor de reset) |
| Registro de estado (SR) | 32 bits, registro **aparte del banco de GPRs** (no es un GPR) — ver sección "Registro de Estado (SR)" |

---

## Formato de instrucción (dentro de cada slot)

```
 31                                   ...                                    3   2 1 0
[                     campos según tipo de instrucción                    ] [ funct ] [opcode]
```

- **Opcode** (bits `[2:0]`): identifica el *tipo* de instrucción (Registro, Inmediato, Memoria, Control, Cripto, Seguridad).
- **Funct** (bits `[6:3]`): dentro de cada tipo, selecciona la operación específica (SUM, REST, MUL, …).
- Los campos restantes (`rs1`, `rs2`, `rd`, inmediatos, offsets) varían según el tipo — ver tablas abajo.

> ⚠️ **Falta:** diagrama del **bundle completo de 128 bits** mostrando los 4 slots de 32 bits uno al lado del otro y qué unidad funcional ocupa cada uno. Hoy solo está documentada la codificación *dentro* de un slot de 32 bits, tipo por tipo — falta la vista a nivel de bundle que exige la Sec. 4.1.1.

---

## Formato de Bundle y Slots

- **Ancho del bundle:** 128 bits, dividido en **4 slots de 32 bits**.
- **Esquema de asignación:** slots **fijos** — cada slot está atado permanentemente a un tipo de unidad funcional: 1 slot para ALU, 1 para LSU, 1 para BRU, 1 para la Unidad Criptográfica (Feistel4).
- **Justificación:** un esquema de slots fijos simplifica el datapath y su decodificación, ya que cada slot corresponde directamente a su unidad funcional (no requiere un campo de selección adicional). Además garantiza que el cómputo general (ALU/LSU/BRU) y el cómputo criptográfico puedan coexistir de forma independiente en el mismo bundle, sin competir por el mismo slot.

> ⚠️ **Falta — obligatorio (Sec. 4.1.1):** **codificación de NOP por slot.** Actualmente solo existe el opcode/funct de cada instrucción real; no está definido qué patrón de bits en el slot de ALU, LSU, BRU o Cripto significa "este slot no ejecuta nada este ciclo". Debe definirse (por ejemplo, reservando un funct específico dentro de cada tipo, o un opcode reservado) y quedar documentado explícitamente, uno por cada uno de los 4 slots.

> ⚠️ **Falta — ambigüedad a resolver:** el ISA define **6 tipos de instrucción** (RIMCFS) pero el bundle solo tiene **4 slots/unidades funcionales** (ALU, LSU, BRU, Cripto). Las instrucciones de tipo **Seguridad** (AUTH, LOGOUT, opcode `101`) no tienen unidad funcional ni slot asignado explícitamente — ¿comparten el slot de la Unidad Criptográfica (por estar ligadas a la bóveda de llaves) o necesitan su propio slot? Esto debe decidirse y justificarse, porque afecta directamente si el bundle sigue teniendo 4 slots o necesita un quinto.

---

## Unidades Funcionales

| # | Unidad | Instrucciones que atiende |
|---|--------|---------------------------|
| 1 | **ALU** — Aritmético-lógica | SUM, REST, MUL, DIV, OLY, OLO, LOE, DLI, DLD, COMP, y sus variantes inmediatas (SUMI, RESTI, MULI, DIVI, DLII, DLDI) |
| 2 | **LSU** — Carga/almacenamiento | CB, CP (load byte/word), AB, AP (store byte/word) |
| 3 | **BRU** — Control de flujo | SIG, SNIG, SMI, SMQ (branches), S (jump) |
| 4 | **Unidad Criptográfica (Feistel4)** | LOADKEY, FROUND — con acceso exclusivo a la bóveda de llaves |



> ⚠️ **Falta:** ¿dónde encajan las instrucciones de tipo **Seguridad** (AUTH/LOGOUT) en esta tabla de unidades funcionales? (mismo punto señalado arriba).

---

## Banco de Registros, PC y Registro de Estado

- 32 registros de propósito general de 32 bits, campo de registro de 5 bits.
- **Justificación de 32 registros:** al ser una arquitectura VLIW, es el compilador (o el ensamblador) quien calendariza las instrucciones dentro de cada bundle. Contar con 32 registros evita dependencias falsas entre instrucciones, da margen para mantener variables vivas en registros, y facilita llenar los 4 slots de un bundle con instrucciones independientes — maximizando el paralelismo estático.

> ⚠️ **Falta — obligatorio (Sec. 4.5):** ancho del PC y su valor de reset / dirección de inicio del programa. (El registro de estado ya se resolvió abajo.)

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
- [ ] **Diagrama del bundle completo de 128 bits** con los 4 slots y su unidad funcional asociada.
- [ ] **Resolver dónde encajan las instrucciones de tipo Seguridad** (AUTH/LOGOUT) dentro del esquema de 4 slots/unidades funcionales.
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
- [ ] Revisar que el documento **no incluya el pipeline/microarquitectura** (Sec. 4.1.3 nota) — eso se evalúa en la Entrega 2, no aquí. El boceto de datapath IF/ID/EX/MEM/WB puede quedar fuera de este documento o marcarse claramente como "avance preliminar, no parte del contrato congelado".
