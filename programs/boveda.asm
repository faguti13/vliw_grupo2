; boveda.asm - Control de acceso de la boveda: AUTH/LOGOUT/RDSR, bloqueo por hardware y aislamiento
.text
        SUMI r0, 1, r28
        SUMI r0, 68, r1
        SUMI r0, 136, r2
        DLII r28, 16, r28
        DLII r1, 11, r1
        DLII r2, 11, r2
        SUMI r0, 0, r10
        SUMI r1, 546, r1
        SUMI r2, 1092, r2
        DLII r10, 11, r10
        DLII r1, 11, r1
        DLII r2, 11, r2
        SUMI r10, 21, r10
        SUMI r1, 273, r1
        SUMI r2, 546, r2
        DLII r10, 11, r10
        SUMI r0, 0, r11
        SUMI r0, 662, r6
        SUMI r10, 682, r10
        DLII r11, 11, r11
        DLII r6, 11, r6
        SUMI r0, 4660, r5
        SUMI r11, 23, r11
        SUMI r6, 1204, r6
        NOP
        DLII r11, 11, r11
        DLII r6, 11, r6
        NOP
        SUMI r11, 955, r11
        SUMI r6, 1445, r6
        NOP
        NOP
        SUMI r0, 0, r6 | LOADKEY r6, 0, 0
        FROUND r10, r11, 0, 0, r1, r2
        RDSR r20
        SUMI r0, 811, r5 | AUTH r5
        DLII r6, 11, r6 | RDSR r21
        NOP
        DLII r5, 11, r5
        SUMI r6, 548, r6
        NOP
        SUMI r5, 1986, r5
        DLII r6, 11, r6
        NOP
        DLII r5, 11, r5
        SUMI r6, 563, r6
        NOP
        SUMI r5, 564, r5
        NOP
        NOP
        SUMI r0, 0, r5 | AUTH r5
        RDSR r22
        SUMI r0, 273, r6 | LOADKEY r6, 0, 0
        NOP
        NOP
        DLII r6, 11, r6
        NOP
        NOP
        SUMI r6, 684, r6
        NOP
        NOP
        DLII r6, 11, r6
        NOP
        NOP
        SUMI r6, 1655, r6
        NOP
        NOP
        SUMI r0, 546, r6 | LOADKEY r6, 0, 1
        NOP
        NOP
        DLII r6, 11, r6
        NOP
        NOP
        SUMI r6, 821, r6
        NOP
        NOP
        DLII r6, 11, r6
        NOP
        NOP
        SUMI r6, 699, r6
        NOP
        NOP
        SUMI r0, 819, r6 | LOADKEY r6, 0, 2
        NOP
        NOP
        DLII r6, 11, r6
        NOP
        NOP
        SUMI r6, 957, r6
        NOP
        NOP
        DLII r6, 11, r6
        NOP
        NOP
        SUMI r6, 1791, r6
        NOP
        NOP
        SUMI r0, 46, r6 | LOADKEY r6, 0, 3
        NOP
        NOP
        DLII r6, 11, r6
        NOP
        NOP
        SUMI r6, 1470, r6
        NOP
        NOP
        DLII r6, 11, r6
        NOP
        NOP
        SUMI r6, 13, r6
        NOP
        NOP
        SUMI r0, 77, r6 | LOADKEY r6, 1, 0
        NOP
        NOP
        DLII r6, 11, r6
        NOP
        NOP
        SUMI r6, 740, r6
        NOP
        NOP
        DLII r6, 11, r6
        NOP
        NOP
        SUMI r6, 1128, r6
        NOP
        NOP
        SUMI r0, 890, r6 | LOADKEY r6, 1, 1
        NOP
        NOP
        DLII r6, 11, r6
        NOP
        NOP
        SUMI r6, 1463, r6
        NOP
        NOP
        DLII r6, 11, r6
        NOP
        NOP
        SUMI r6, 1775, r6
        NOP
        NOP
        SUMI r0, 4, r6 | LOADKEY r6, 1, 2
        NOP
        NOP
        DLII r6, 11, r6
        NOP
        NOP
        SUMI r6, 1128, r6
        NOP
        NOP
        DLII r6, 11, r6
        NOP
        NOP
        SUMI r6, 1383, r6
        NOP
        NOP
        SUM r0, r0, r6 | LOADKEY r6, 1, 3
        FROUND r10, r11, 0, 0, r3, r4
        FROUND r10, r11, 1, 0, r7, r8
        LOADKEY r0, 3, 3
        LOGOUT
        RDSR r23
        FROUND r10, r11, 0, 0, r1, r2
        RDSR r24
        NOP
        NOP
        FIN
