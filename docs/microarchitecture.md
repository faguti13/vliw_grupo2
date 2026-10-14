# Microarquitectura Feistel4-VLIW

## 1. Diagrama de bloques

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


| Puertos de lectura | Slot     | Qué lee                                          |
| ------------------ | -------- | ------------------------------------------------ |
| 6, 7               | 3 Cripto | `rs_L`, `rs_R` (o la fuente de `LOADKEY`/`AUTH`) |



| Puertos de escritura | Origen                   |
| -------------------- | ------------------------ |
| 3, 4                 | `FROUND` `rd_L` y `rd_R` |


`FROUND` solo escribe resultados si `SR.AUTH = 1`
(`fround_we = SR.AUTH & fround_valid`). Sin sesión, no cambia los registros y registra
`VAULT_ERR` y `ERR_CODE = 001`.

## 4. Aislamiento de la bóveda

- `key_vault` guarda 4 llaves × 4 subllaves de 32 bits. Su **única escritura** es `LOADKEY` (`we = SR.AUTH & loadkey_valid`) y su **única lectura** es el puerto `rdata`, conectado solo a la función F de `FROUND`. No existe ningún camino hacia un GPR ni hacia la memoria.
- `FROUND` solo escribe resultados si `SR.AUTH = 1` (`fround_we = SR.AUTH & fround_valid`). Sin sesión, no cambia los registros y registra `VAULT_ERR` y `ERR_CODE = 001`.
- `AUTH` con una credencial distinta de `0xCAFE1234` deja `ERR_CODE = 010`. `LOGOUT` cierra la sesión. El estado se lee con `RDSR` (bit 0 AUTH, bit 1 VAULT_ERR pegajoso, bits 4:2 ERR_CODE).
- Los testbenches `tb_key_vault` y `tb_crypto_unit` comprueban el bloqueo; el programa `boveda.asm` lo comprueba extremo a extremo y exige que ninguna subllave aparezca en un registro (`forbid`).

La función de ronda vive en `vliw_pkg` (`rol32` y `F(R,k) = ROL(R,5) + k` XOR `ROL(R,13)`).

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


| Módulo        | Archivo              | Función                                               |
| ------------- | -------------------- | ----------------------------------------------------- |
| `vliw_pkg`    | `rtl/vliw_pkg.sv`    | `rol32` y función F de Feistel4                       |
| `key_vault`   | `rtl/key_vault.sv`   | bóveda de llaves                                      |
| `crypto_unit` | `rtl/crypto_unit.sv` | `LOADKEY`, `FROUND`, `AUTH`, `LOGOUT`, `RDSR` y el SR |
| `bru` | `rtl/bru.sv` | condicionales, `S`, `SYE`, `SRG`, `FIN` |
| `dispatch` | `rtl/dispatch.sv` | separación de slots y extracción de registros; detección de opcode ilegal |
| `fetch` | `rtl/fetch.sv` | PC, redirección y parada |
| `core` | `rtl/core.sv` | pipeline IF/ID/EX/WB y registros entre etapas |
| `top` | `rtl/top.sv` | `core` + `memory` |

Los cambios al SR y a la bóveda son visibles para la instrucción de slot 3 del bundle siguiente.