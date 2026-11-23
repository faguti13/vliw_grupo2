; bench_secuencial.asm - Barrido lineal de 8 palabras (una linea de cache de 32 B).
; Patron: 1 miss + 7 hits por linea cuando haya L1/L2. Aqui solo se verifica
; correccion funcional en el procesador actual (memoria de 1 ciclo).
; Mapa P1: gp = 0x10000. En P2 el mismo arreglo ira en gp = 0x0000 (DRAM 64 KB).
.text
        SUMI r0, 1, r28
        SUMI r0, 1, r1
        SUMI r0, 2, r2
        DLII r28, 16, r28          ; r28 = 0x10000 (gp P1)
        SUMI r0, 3, r3
        SUMI r0, 4, r4
        SUMI r0, 5, r5
        SUMI r0, 6, r6
        SUMI r0, 7, r7
        SUMI r0, 8, r8
        NOP
        NOP
        AP 0(r28), r1
        AP 4(r28), r2
        AP 8(r28), r3
        AP 12(r28), r4
        AP 16(r28), r5
        AP 20(r28), r6
        AP 24(r28), r7
        AP 28(r28), r8
        NOP
        NOP
        NOP
        SUMI r0, 0, r10            ; checksum
        CP 0(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10
        CP 4(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10
        CP 8(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10
        CP 12(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10
        CP 16(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10
        CP 20(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10
        CP 24(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10
        CP 28(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10          ; r10 = 1+...+8 = 36
        NOP
        NOP
        NOP
        FIN
