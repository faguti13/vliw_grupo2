# Microarquitectura Feistel4-VLIW

## 1. Diagrama de bloques

## 2. Etapas

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

## 6. Módulos y archivos


| Módulo        | Archivo              | Función                                               |
| ------------- | -------------------- | ----------------------------------------------------- |
| `vliw_pkg`    | `rtl/vliw_pkg.sv`    | `rol32` y función F de Feistel4                       |
| `key_vault`   | `rtl/key_vault.sv`   | bóveda de llaves                                      |
| `crypto_unit` | `rtl/crypto_unit.sv` | `LOADKEY`, `FROUND`, `AUTH`, `LOGOUT`, `RDSR` y el SR |


Los cambios al SR y a la bóveda son visibles para la instrucción de slot 3 del bundle siguiente.