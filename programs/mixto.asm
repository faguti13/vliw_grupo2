; Lazo de cifrado que combina ALU, LSU, BRU y FROUND en los mismos bundles.
;
; Arma la credencial y una llave de 128 bits (4 palabras de 32 bits, una por ronda),
; se autentica con AUTH, carga la llave en la bóveda con LOADKEY (0..3)
; y cifra en el lugar 3 bloques de 8 bytes (L, R) de .data con 4 rondas FROUND cada uno.

; Cada iteración: CP de L y R, 4 FROUND encadenadas (los registros de salida de una son la entrada de la siguiente),
; y AP de vuelta. SMQ r13 < 3 cierra el lazo.

; Mezcla en un mismo bundle: CP + SUMI, FROUND + SUMI (contador r15 = 12 rondas),
; AP + SUM + SMQ (el salto va junto al último AP).
; Supone que no hay forwarding, un GPR se lee 3 bundles después de escribirse,
; y un salto tomado descarta 2 bundles (por eso hay NOP tras el SMQ). LOADKEY ve el SR 1 bundle después de AUTH.
; La credencial y las llaves nunca se escriben en memoria.

; Resultados esperados: mixto.expect (r13 = 3, r15 = 12, las 6 palabras cifradas
; y forbid de las palabras de llave) y la comparación con feistel4_ref sobre los mismos datos.
.text
        ; Preparación: gp, credencial (r5), palabra 0 de la llave (r6) y puntero (r10)
        SUMI r0, 1, r28                                        ; gp = 1; con el DLII se completa gp = 0x10000
        SUMI r0, 811, r5                                       ; r5 (credencial) = 811 = 0x32b
        SUMI r0, 0, r6                                         ; r6 (palabra de llave) = 0
        DLII r28, 16, r28                                      ; gp = 1 << 16 = 0x10000, base de .data
        DLII r5, 11, r5                                        ; r5 = 0x32b << 11
        DLII r6, 11, r6                                        ; r6 = 0
        SUMI r0, 0, r10                                        ; r10 (puntero al bloque) = 0
        SUMI r5, 1986, r5                                      ; r5 = r5 + 1986
        SUMI r6, 548, r6                                       ; r6 = 548
        DLII r10, 11, r10                                      ; r10 = 0
        DLII r5, 11, r5                                        ; r5 = r5 << 11
        DLII r6, 11, r6                                        ; r6 = 548 << 11
        SUMI r10, 32, r10                                      ; r10 = 32
        SUMI r5, 564, r5                                       ; r5 = r5 + 564 -> credencial = 0xcafe1234
        SUMI r6, 563, r6                                       ; r6 = (548 << 11) + 563 = 0x112233 (palabra 0 de la llave)
        DLII r10, 11, r10                                      ; r10 = 32 << 11 = 0x10000, dirección del primer bloque
        ; Autenticación y carga de las 4 palabras de la llave (LOADKEY k=0, ranuras 0..3)
        SUMI r0, 0, r13 | AUTH r5                              ; r13 = 0 (bloques cifrados) | AUTH con la credencial de r5
        SUMI r0, 273, r6 | LOADKEY r6, 0, 0                    ; r6 = 273, inicia la palabra 1 | LOADKEY guarda 0x112233 en la ranura 0 (ve el SR de AUTH)
        SUMI r10, 0, r10                                       ; r10 = 0x10000 (copia, sin cambio)
        SUMI r0, 3, r14                                        ; r14 = 3 (cantidad de bloques)
        DLII r6, 11, r6                                        ; palabra 1: r6 = 273 << 11
        NOP
        NOP
        SUMI r6, 684, r6                                       ; palabra 1: r6 = r6 + 684
        NOP
        NOP
        DLII r6, 11, r6                                        ; palabra 1: r6 = r6 << 11
        NOP
        NOP
        SUMI r6, 1655, r6                                      ; palabra 1: r6 = r6 + 1655 -> 0x44556677
        NOP
        NOP
        SUMI r0, 546, r6 | LOADKEY r6, 0, 1                    ; r6 = 546, inicia la palabra 2 | LOADKEY guarda 0x44556677 en la ranura 1
        NOP
        NOP
        DLII r6, 11, r6                                        ; palabra 2: r6 = 546 << 11
        NOP
        NOP
        SUMI r6, 821, r6                                       ; palabra 2: r6 = r6 + 821
        NOP
        NOP
        DLII r6, 11, r6                                        ; palabra 2: r6 = r6 << 11
        NOP
        NOP
        SUMI r6, 699, r6                                       ; palabra 2: r6 = r6 + 699 -> 0x8899aabb
        NOP
        NOP
        SUMI r0, 819, r6 | LOADKEY r6, 0, 2                    ; r6 = 819, inicia la palabra 3 | LOADKEY guarda 0x8899aabb en la ranura 2
        NOP
        NOP
        DLII r6, 11, r6                                        ; palabra 3: r6 = 819 << 11
        NOP
        NOP
        SUMI r6, 957, r6                                       ; palabra 3: r6 = r6 + 957
        NOP
        NOP
        DLII r6, 11, r6                                        ; palabra 3: r6 = r6 << 11
        NOP
        NOP
        SUMI r6, 1791, r6                                      ; palabra 3: r6 = r6 + 1791 -> 0xccddeeff
        NOP
        NOP
        SUM r0, r0, r6 | LOADKEY r6, 0, 3                      ; r6 = 0 (borra la palabra de llave del registro) | LOADKEY guarda 0xccddeeff en la ranura 3
        NOP
        NOP
        ; Lazo: lee un bloque (L, R), aplica 4 rondas FROUND y lo guarda cifrado en el mismo lugar
Lloop:  CP 0(r10), r1 | SUMI r10, 8, r12                       ; carga L del bloque actual | r12 = dirección del siguiente bloque (r10 + 8)
        CP 4(r10), r2 | SUMI r13, 1, r13                       ; carga R del bloque actual | r13 = r13 + 1 (bloques procesados)
        NOP
        NOP
        SUMI r15, 1, r15 | FROUND r1, r2, 0, 0, r3, r4         ; ronda 0 con la llave 0: (r1, r2) -> (r3, r4) | cuenta una ronda en r15
        NOP
        NOP
        SUMI r15, 1, r15 | FROUND r3, r4, 0, 1, r1, r2         ; ronda 1: (r3, r4) -> (r1, r2) | r15 = r15 + 1
        NOP
        NOP
        SUMI r15, 1, r15 | FROUND r1, r2, 0, 2, r3, r4         ; ronda 2: (r1, r2) -> (r3, r4) | r15 = r15 + 1
        NOP
        NOP
        SUMI r15, 1, r15 | FROUND r3, r4, 0, 3, r1, r2         ; ronda 3: (r3, r4) -> (r1, r2) | r15 = r15 + 1
        NOP
        NOP
        AP 0(r10), r1                                          ; guarda L cifrado en el mismo lugar (3 bundles después de la última ronda)
        AP 4(r10), r2 | SUM r12, r0, r10 | SMQ r13, r14, Lloop ; guarda R cifrado | r10 = r12 (siguiente bloque) | repite el lazo si r13 < r14 (3)
        NOP
        NOP
        ; Fin
        FIN                                                    ; detiene el procesador una vez vaciado el pipeline
.data
        .word 0x0, 0x0                    ; bloque 0: L = 0, R = 0
        .word 0x25dbfac1, 0x4b5c952c      ; bloque 1
        .word 0xdeadbeef, 0xbadcafe       ; bloque 2
