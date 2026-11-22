; bench_aleatorio.asm - Accesos a offsets "aleatorios" en un bloque de 128 B
; (4 lineas de 32 B). El patron no es secuencial ni stride fijo: mezcla indices
; tipo LCG reducido. Con L2 de 16 KB un arreglo grande haria thrashing; aqui el
; bloque cabe en L1 pero el orden de acceso es irregular.
; Correccion funcional en P1. Mapa: gp = 0x10000; en P2 gp = 0x0000.
.text
        SUMI r0, 1, r28
        SUMI r0, 1, r1
        SUMI r0, 2, r2
        DLII r28, 16, r28          ; r28 = 0x10000
        SUMI r0, 3, r3
        SUMI r0, 4, r4
        SUMI r0, 5, r5
        SUMI r0, 6, r6
        SUMI r0, 7, r7
        SUMI r0, 8, r8
        NOP
        NOP
; offsets (bytes): 0, 52, 104, 20, 76, 12, 96, 40  — dentro de [0,128)
        AP 0(r28), r1
        AP 52(r28), r2
        AP 104(r28), r3
        AP 20(r28), r4
        AP 76(r28), r5
        AP 12(r28), r6
        AP 96(r28), r7
        AP 40(r28), r8
        NOP
        NOP
        NOP
        SUMI r0, 0, r10
        CP 0(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10
        CP 52(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10
        CP 104(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10
        CP 20(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10
        CP 76(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10
        CP 12(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10
        CP 96(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10
        CP 40(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10          ; 1+...+8 = 36
        NOP
        NOP
        NOP
        FIN
