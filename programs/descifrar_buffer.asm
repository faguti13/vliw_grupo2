; descifrar_buffer.asm - Descifrar en el lugar el buffer indicado por el buzon de E/S (0x1FFF0)
.text
        SUMI r0, 1, r28
        SUMI r0, 811, r5
        SUMI r0, 0, r6
        DLII r28, 16, r28
        DLII r5, 11, r5
        DLII r6, 11, r6
        SUMI r0, 0, r27
        SUMI r5, 1986, r5
        SUMI r6, 548, r6
        DLII r27, 11, r27
        DLII r5, 11, r5
        DLII r6, 11, r6
        SUMI r27, 63, r27
        SUMI r5, 564, r5
        SUMI r6, 563, r6
        DLII r27, 11, r27
        SUMI r0, 0, r13 | AUTH r5
        SUMI r0, 273, r6 | LOADKEY r6, 0, 0
        SUMI r27, 2032, r27
        NOP
        DLII r6, 11, r6
        CP 0(r27), r10
        CP 8(r27), r14
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
        SUM r0, r0, r6 | LOADKEY r6, 0, 3
        NOP
        NOP
Lloop:  CP 0(r10), r1 | SUMI r10, 8, r12
        CP 4(r10), r2 | SUMI r13, 1, r13
        NOP
        NOP
        FROUND r2, r1, 0, 3, r4, r3
        NOP
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
        AP 0(r10), r1
        AP 4(r10), r2 | SUM r12, r0, r10 | SMQ r13, r14, Lloop
        NOP
        NOP
        FIN
