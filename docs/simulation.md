# Simulación, pruebas y herramientas

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