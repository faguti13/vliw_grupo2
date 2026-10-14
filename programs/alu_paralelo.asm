; alu_paralelo.asm - Operaciones de ALU ejecutadas en paralelo con LSU, BRU y cripto/seguridad
; dentro del mismo bundle.
.text
        SUMI r0, 1, r28
        SUMI r0, 7, r1
        SUMI r0, 9, r2
        DLII r28, 16, r28
        SUMI r0, 85, r5            ; 0x55
        NOP
        NOP
        AP 0(r28), r5              ; mem[gp] = 0x55
        NOP
        NOP
        NOP
; Un bundle con los 4 slots activos: ALU + LSU + BRU (no tomado) + RDSR
        SUM r1, r2, r3 | CP 0(r28), r4 | SNIG r0, r0, Lno | RDSR r6
        SUMI r1, 1, r7 | AP 8(r28), r2
        NOP
Lno:    NOP
        NOP
; ALU + salto tomado en el mismo bundle: la ALU si se ejecuta
        SUMI r2, 100, r8 | SIG r0, r0, Ltom
        SUMI r0, 0x111, r9         ; veneno
        SUMI r0, 0x111, r10        ; veneno
Ltom:   NOP
        NOP
        NOP
        NOP
        FIN
