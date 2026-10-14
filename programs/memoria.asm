; memoria.asm - CP/AP: orden big-endian, offsets negativos, AP seguido de CP en bundles consecutivos.
.text
        SUMI r0, 1, r28
        SUMI r0, 0x1122, r1
        NOP
        DLII r28, 16, r28
        DLII r1, 16, r2            ; 0x11220000
        NOP
        NOP
        SUMI r2, 0x3344, r2        ; 0x11223344
        SUMI r0, 100, r4
        NOP
        NOP
        AP 0(r28), r2              ; mem[gp+0] = 0x11223344
        CP 0(r28), r5              ; AP en el bundle i es visible para el CP del bundle i+1
        NOP
        NOP
        SUMI r28, 32, r6           ; r6 = gp+32
        NOP
        NOP
        AP -8(r6), r4              ; offset negativo: mem[gp+24] = 100
        NOP
        CP 24(r28), r7
        NOP
        NOP
        NOP
        NOP
        FIN
