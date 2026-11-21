; bench_stride.asm - Accesos con paso 1, 8 y 64 palabras (4 B, 32 B, 256 B).
; Con cache: stride 1 favorece hits en la linea; stride 8/64 provocan mas misses.
; Aqui solo correccion funcional. Mapa P1: gp = 0x10000; en P2 gp = 0x0000.
.text
        SUMI r0, 1, r28
        SUMI r0, 10, r1
        SUMI r0, 20, r2
        DLII r28, 16, r28          ; r28 = 0x10000
        SUMI r0, 30, r3
        SUMI r0, 40, r4
        SUMI r0, 50, r5
        SUMI r0, 60, r6
        SUMI r0, 70, r7
        SUMI r0, 80, r8
        SUMI r0, 90, r9
        NOP
; --- stride 1 palabra (4 B): gp+0, +4, +8 ---
        AP 0(r28), r1
        AP 4(r28), r2
        AP 8(r28), r3
; --- stride 8 palabras (32 B = 1 linea): gp+0x100, +0x120, +0x140 ---
        AP 256(r28), r4
        AP 288(r28), r5
        AP 320(r28), r6
; --- stride 64 palabras (256 B): gp+0x400, +0x500, +0x600 ---
        AP 1024(r28), r7
        AP 1280(r28), r8
        AP 1536(r28), r9
        NOP
        NOP
        NOP
        SUMI r0, 0, r10
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
        CP 256(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10
        CP 288(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10
        CP 320(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10
        CP 1024(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10
        CP 1280(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10
        CP 1536(r28), r11
        NOP
        NOP
        NOP
        SUM r10, r11, r10          ; 10+20+...+90 = 450
        NOP
        NOP
        NOP
        FIN
