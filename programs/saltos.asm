; Prueba todos los saltos del BRU

; Cubre los saltos (tomados y no tomados, hacia adelante y atras), S, SYE/SRG y FIN. 
; Tras un salto tomado se descartan los 2 bundles siguientes (flush).
; Los veneno son instr trampa, si el flush falla , se ejecutan y dejan el registro en 0x111
; El .expect verifica que queden en 0.
.text
        SUMI r0, 1, r28
        SUMI r0, 3, r1
        SUMI r0, 3, r2
        DLII r28, 16, r28
        SUMI r0, 5, r3
        SUMI r0, -2, r4
        SUMI r0, 0, r5
        SUMI r0, 4, r6
        NOP
        NOP
; SIG tomado (3 == 3)
        SIG r1, r2, L1
        SUMI r0, 0x111, r10        ; veneno
        SUMI r0, 0x111, r11        ; veneno
L1:     NOP
; SIG no tomado (3 != 5) -los 2 bundles siguientes SI se ejecutan
        SIG r1, r3, Lx1
        SUMI r0, 1, r12
        SUMI r0, 2, r13
Lx1:    NOP
; SNIG tomado (3 != 5)
        SNIG r1, r3, L2
        SUMI r0, 0x111, r14        ; veneno
        SUMI r0, 0x111, r15        ; veneno
L2:     NOP
;  SNIG no tomado (3 == 3)
        SNIG r1, r2, Lx2
        SUMI r0, 1, r16
        SUMI r0, 2, r17
Lx2:    NOP
;  SMI (>=) tomado (5 >= 3)
        SMI r3, r1, L3
        SUMI r0, 0x111, r18        ; veneno
        SUMI r0, 0x111, r19        ; veneno
L3:     NOP
;  SMI no tomado (3 >= 5 es falso)
        SMI r1, r3, Lx3
        SUMI r0, 1, r20
        SUMI r0, 2, r21
Lx3:    NOP
;  SMQ (<) tomado con signo (-2 < 3)
        SMQ r4, r1, L4
        SUMI r0, 0x111, r22        ; veneno
        SUMI r0, 0x111, r23        ; veneno
L4:     NOP
; SMQ no tomado (3 < -2 es falso con signo)
        SMQ r1, r4, Lx4
        SUMI r0, 1, r24
        SUMI r0, 2, r25
Lx4:    NOP
;  S incondicional hacia adelante
        S L5
        SUMI r0, 0x111, r26        ; veneno
        SUMI r0, 0x111, r27        ; veneno
L5:     NOP
; Lazo hacia atras - r5 cuenta de 0 a 4 
Lloop:  SUMI r5, 1, r5
        NOP
        NOP
        SMQ r5, r6, Lloop
        NOP
        NOP
        NOP
; SYE / SRG - dos llamadas a f 
        SYE f
        NOP
        NOP
        SYE f
        NOP
        NOP
        SUM r1, r0, r7             ; r1 (retorno de f) - r7, ya listo por la distancia
        NOP
        NOP
        NOP
        SUM r0, r31, r8            ; r8 = direccion de retorno de la ultima llamada
        S Lfin
        NOP
        NOP
; f: r1 <- r1 + 10 
f:      SUMI r1, 10, r1
        NOP
        NOP
        SRG r31
        NOP
        NOP
Lfin:   NOP
        NOP
        NOP
        FIN
        SUMI r0, 0x77, r9          ; despues de FIN: no debe ejecutarse
        SUMI r0, 0x77, r9
