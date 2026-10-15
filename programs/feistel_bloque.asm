; feistel_bloque.asm - Cifrado y descifrado Feistel4 de un bloque con 8 FROUND
.text
        SUMI r0, 1, r28
        SUMI r0, 811, r5
        SUMI r0, 0, r6
        DLII r28, 16, r28
        DLII r5, 11, r5
        DLII r6, 11, r6
        SUMI r0, 151, r1
        SUMI r5, 1986, r5
        SUMI r6, 548, r6
        DLII r1, 11, r1
        DLII r5, 11, r5
        DLII r6, 11, r6
        SUMI r1, 895, r1
        SUMI r5, 564, r5
        SUMI r6, 563, r6
        DLII r1, 11, r1
        SUMI r0, 301, r2 | AUTH r5
        SUMI r0, 273, r6 | LOADKEY r6, 0, 0
        SUMI r1, 705, r1
        DLII r2, 11, r2
        DLII r6, 11, r6
        NOP
        SUMI r2, 914, r2
        SUMI r6, 684, r6
        NOP
        DLII r2, 11, r2
        DLII r6, 11, r6
        NOP
        SUMI r2, 1324, r2
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
        SUM r0, r0, r6 | LOADKEY r6, 0, 3
        FROUND r1, r2, 0, 0, r3, r4
        NOP
        NOP
        FROUND r3, r4, 0, 1, r1, r2
        NOP
        NOP
        FROUND r1, r2, 0, 2, r3, r4
        NOP
        NOP
        FROUND r3, r4, 0, 3, r1, r2
        NOP
        NOP
        AP 0(r28), r1 | FROUND r2, r1, 0, 3, r4, r3
        AP 4(r28), r2
        NOP
        FROUND r4, r3, 0, 2, r2, r1
        NOP
        NOP
        FROUND r2, r1, 0, 1, r4, r3
        NOP
        NOP
        FROUND r4, r3, 0, 0, r2, r1
        NOP
        NOP
        AP 8(r28), r1
        AP 12(r28), r2
        FIN
