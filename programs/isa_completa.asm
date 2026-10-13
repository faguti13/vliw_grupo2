; isa_completa.asm - Cobertura de las instrucciones de ALU y de memoria (CP/AP) con FIN.
;
; Qué hace: calcula con las 10 operaciones de registro (SUM, REST, MUL, DIV, OLY, OLO,
;   LOE, DLI, DLD, COMP) y las 6 con inmediato (SUMI, RESTI, MULI, DIVI, DLII, DLDI) y
;   guarda cada resultado en memoria con AP, una palabra por resultado desde gp = 0x10000.
;   Incluye casos límite: división entre cero (0xFFFFFFFF), división con signo, COMP con
;   negativos y una escritura a r0 (SUM ... r0) que debe ser ignorada.
; Qué supone: no hay forwarding, un GPR escrito en el bundle i se lee desde el bundle i+3.
;   Por eso el AP de cada resultado va 3 bundles después del cálculo, y hay NOP entre
;   el SUMI/DLII que arma gp y el primer uso. Un AP en i ya lo ve un CP en i+1.
; Qué lo prueba: isa_completa.expect (los 21 resultados, mem[0x10064] y r0 = 0) y
;   vliwasm.py --check-hazards, que no debe dar advertencias.
; Pendiente de cobertura: saltos (SIG, SNIG, SMI, SMQ, S, SYE, SRG) e instrucciones de
;   seguridad (AUTH, LOGOUT, RDSR, LOADKEY, FROUND); las cubren saltos.asm, boveda.asm y
;   mixto.asm.
.text
        ; --- Preparación de operandos (los NOP cubren los 3 bundles de latencia) ---
        SUMI r0, 1, r28                     ; gp = 1 << 16
        SUMI r0, 12, r1                     ; r1 = 12  (operando A)
        SUMI r0, 5, r2                      ; r2 = 5   (operando B)
        DLII r28, 16, r28 | NOP | NOP | NOP ; gp = 1 << 16 = 0x10000, base de los resultados; los NOP dejan pasar la latencia de r28
        SUMI r0, 2, r12                     ; r12 = 2  (cantidad de desplazamiento para DLI/DLD)
        SUMI r0, -7, r21                    ; r21 = -7 (negativo, para probar COMP y DIV con signo)
        NOP
        NOP
        NOP
        ; --- ALU registro-registro; cada AP guarda un resultado 3 bundles después de calcularlo ---
        SUM r1, r2, r3                      ; r3 = 12 + 5 = 17 (0x11)
        REST r1, r2, r4                     ; r4 = 12 - 5 = 7
        MUL r1, r2, r5                      ; r5 = 12 * 5 = 60 (0x3c)
        DIV r1, r2, r6 | AP 0(r28), r3      ; r6 = 12 / 5 = 2 | guarda r3 (suma) en gp+0, ya pasaron 3 bundles
        OLY r1, r2, r7 | AP 4(r28), r4      ; r7 = 12 AND 5 = 4 | guarda r4 (resta) en gp+4
        OLO r1, r2, r8 | AP 8(r28), r5      ; r8 = 12 OR 5 = 13 (0xd) | guarda r5 (mul) en gp+8
        LOE r1, r2, r9 | AP 12(r28), r6     ; r9 = 12 XOR 5 = 9 | guarda r6 (div) en gp+12
        DLI r1, r12, r10 | AP 16(r28), r7   ; r10 = 12 << 2 = 48 (0x30) | guarda r7 (AND) en gp+16
        DLD r1, r12, r11 | AP 20(r28), r8   ; r11 = 12 >> 2 = 3 (lógico) | guarda r8 (OR) en gp+20
        COMP r1, r2, r13 | AP 24(r28), r9   ; r13 = (12 < 5) = 0 | guarda r9 (XOR) en gp+24
        COMP r2, r1, r14 | AP 28(r28), r10  ; r14 = (5 < 12) = 1 | guarda r10 (desplaz. izq.) en gp+28
        ; --- ALU con inmediato ---
        SUMI r1, 100, r15 | AP 32(r28), r11 ; r15 = 12 + 100 = 112 (0x70) | guarda r11 (desplaz. der.) en gp+32
        RESTI r1, 2, r16 | AP 36(r28), r13  ; r16 = 12 - 2 = 10 | guarda r13 (COMP falso) en gp+36
        MULI r1, -3, r17 | AP 40(r28), r14  ; r17 = 12 * -3 = -36 (0xffffffdc) | guarda r14 (COMP cierto) en gp+40
        DIVI r1, 5, r18 | AP 44(r28), r15   ; r18 = 12 / 5 = 2 | guarda r15 (suma inmediata) en gp+44
        DLII r1, 4, r19 | AP 48(r28), r16   ; r19 = 12 << 4 = 192 (0xc0) | guarda r16 (resta inmediata) en gp+48
        DLDI r1, 2, r20 | AP 52(r28), r17   ; r20 = 12 >> 2 = 3 | guarda r17 (mul inmediata) en gp+52
        ; --- Casos límite: negativos, división entre cero y escritura a r0 ---
        COMP r21, r1, r22 | AP 56(r28), r18 ; r22 = (-7 < 12) = 1; COMP compara con signo | guarda r18 (div inmediata) en gp+56
        DIV r21, r2, r23 | AP 60(r28), r19  ; r23 = -7 / 5 = -1; DIV con signo trunca hacia cero | guarda r19 (desplaz. inmediato izq.) en gp+60
        DIV r1, r0, r24 | AP 64(r28), r20   ; r24 = 12 / 0 = 0xffffffff; división entre cero definida en la ISA | guarda r20 (desplaz. inmediato der.) en gp+64
        REST r0, r1, r25 | AP 68(r28), r22  ; r25 = 0 - 12 = -12 (0xfffffff4) | guarda r22 (COMP con negativo) en gp+68
        SUM r1, r1, r0 | AP 72(r28), r23    ; intenta escribir 24 en r0: se ignora, r0 sigue en 0 | guarda r23 (DIV con signo) en gp+72
        ; --- Últimos AP pendientes y prueba de CP después de AP ---
        AP 76(r28), r24                     ; guarda r24 (división entre cero) en gp+76
        AP 80(r28), r25                     ; guarda r25 (resta desde r0) en gp+80
        NOP
        CP 0(r28), r26                      ; r26 = mem[gp+0] = 17: lee de vuelta el primer resultado (CP después de AP)
        NOP
        NOP
        NOP
        AP 100(r28), r26                    ; copia del primer resultado a otra dirección ; copia el valor leído a gp+100 (0x10064); comprueba que CP y AP se encadenan
        NOP
        FIN                                 ; detiene el procesador una vez vaciado el pipeline

