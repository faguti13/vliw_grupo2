#!/usr/bin/env python3
"""gen_programs.py - Genera los programas ASM de prueba que requieren constantes de 32 bits
(fround, feistel_bloque, boveda, mixto) y sus .expect. Usa un planificador voraz minimo
que respeta la latencia de 3 bundles y la regla de un slot por unidad.

    python3 tools/gen_programs.py [directorio_programas]
"""
import os
import re
import sys

M = 0xFFFFFFFF
KEY = [0x00112233, 0x44556677, 0x8899AABB, 0xCCDDEEFF]
KEY1 = [0x0BADF00D, 0x13572468, 0xDEADBEEF, 0x01234567]


def rol(x, r):
    return ((x << r) | (x >> (32 - r))) & M


def F(x, k):
    return (((rol(x, 5) + k) & M) ^ rol(x, 13)) & M


def enc(L, R, key):
    for k in key:
        L, R = R, L ^ F(R, k)
    return L, R


def dec(L, R, key):
    for k in reversed(key):
        L, R = R ^ F(L, k), L
    return L, R


SLOT = {"SUM": 0, "REST": 0, "MUL": 0, "DIV": 0, "SUMI": 0, "DLII": 0, "DLDI": 0, "RESTI": 0, "OLO": 0,
        "CP": 1, "AP": 1, "LOADKEY": 3, "FROUND": 3, "AUTH": 3, "LOGOUT": 3, "RDSR": 3}


class Sched:
    """Planificador voraz de codigo lineal: un bundle por linea."""

    def __init__(self):
        self.b = []          # lista de dicts slot->texto
        self.ready = {}      # reg -> primer bundle donde se puede leer
        self.lastwrite = {}  # reg -> bundle de la ultima escritura
        self.lastread = {}
        self.last_slot = {1: -1, 3: -1}
        self.floor = 0

    def barrier(self):
        self.floor = len(self.b)

    def put(self, mn, text, reads, writes):
        s = SLOT[mn]
        t = self.floor
        for r in reads:
            if r:
                t = max(t, self.ready.get(r, 0))
        for w in writes:
            if w:
                t = max(t, self.lastwrite.get(w, -1) + 1, self.lastread.get(w, -1))
        if s in self.last_slot:
            t = max(t, self.last_slot[s] + 1)
        while True:
            while len(self.b) <= t:
                self.b.append({})
            if s not in self.b[t]:
                break
            t += 1
        self.b[t][s] = text
        for r in reads:
            if r:
                self.lastread[r] = max(self.lastread.get(r, -1), t)
        for w in writes:
            if w:
                self.ready[w] = t + 3
                self.lastwrite[w] = t
        if s in self.last_slot:
            self.last_slot[s] = t
        return t

    def const(self, reg, v):
        v &= M
        if v < 0x4000:
            self.put("SUMI", f"SUMI r0, {v}, r{reg}", [], [reg])
            return
        hi, mid, lo = v >> 22, (v >> 11) & 0x7FF, v & 0x7FF
        self.put("SUMI", f"SUMI r0, {hi}, r{reg}", [], [reg])
        self.put("DLII", f"DLII r{reg}, 11, r{reg}", [reg], [reg])
        self.put("SUMI", f"SUMI r{reg}, {mid}, r{reg}", [reg], [reg])
        self.put("DLII", f"DLII r{reg}, 11, r{reg}", [reg], [reg])
        self.put("SUMI", f"SUMI r{reg}, {lo}, r{reg}", [reg], [reg])

    def gp(self):
        self.put("SUMI", "SUMI r0, 1, r28", [], [28])
        self.put("DLII", "DLII r28, 16, r28", [28], [28])

    def ap(self, off, reg):
        self.put("AP", f"AP {off}(r28), r{reg}", [28, reg], [])

    def text(self, drain=True):
        if drain:
            self.drain()
        out = []
        for d in self.b:
            parts = [d[s] for s in sorted(d)]
            out.append("        " + " | ".join(parts) if parts else "        NOP")
        return out

    def drain(self):
        # esperar a que toda escritura se complete antes de FIN/salto
        end = max(list(self.ready.values()) + [len(self.b)])
        while len(self.b) < end:
            self.b.append({})


def hexw(v):
    return f"{v & M:#x}"


def write(d, name, header, lines, expect):
    with open(os.path.join(d, name + ".asm"), "w") as f:
        f.write("\n".join(header + [".text"] + lines) + "\n")
    with open(os.path.join(d, name + ".expect"), "w") as f:
        f.write("\n".join(expect) + "\n")


def auth(s, cred=0xCAFE1234, reg=5):
    s.const(reg, cred)
    s.put("AUTH", f"AUTH r{reg}", [reg], [])


def loadkeys(s, key, kidx, tmp=6):
    for i, k in enumerate(key):
        s.const(tmp, k)
        s.put("LOADKEY", f"LOADKEY r{tmp}, {kidx}, {i}", [tmp], [])
    s.put("SUM", f"SUM r0, r0, r{tmp}", [], [tmp])   # borra la ultima subllave del GPR


def gen_fround(d):
    s = Sched()
    s.gp()
    auth(s)
    loadkeys(s, KEY, 0)
    L, R = 0x25DBFAC1, 0x4B5C952C
    s.const(1, L)
    s.const(2, R)
    s.put("FROUND", "FROUND r1, r2, 0, 0, r3, r4", [1, 2], [3, 4])
    s.ap(0, 3)
    s.ap(4, 4)
    nl, nr = R, L ^ F(R, KEY[0])
    exp = ["# una ronda: L' = R, R' = L ^ F(R, K0)", f"mem 0x10000 = {hexw(nl)}", f"mem 0x10004 = {hexw(nr)}",
           f"r3 = {hexw(nl)}", f"r4 = {hexw(nr)}", "sr = 0x1"] + [f"forbid {hexw(k)}" for k in KEY]
    write(d, "fround", ["; fround.asm - AUTH, carga de la llave 0 y una ronda FROUND (generado por tools/gen_programs.py)"],
          s.text() + ["        FIN"], exp)


def gen_feistel(d):
    s = Sched()
    s.gp()
    auth(s)
    loadkeys(s, KEY, 0)
    L, R = 0x25DBFAC1, 0x4B5C952C
    s.const(1, L)
    s.const(2, R)
    # cifrado: 4 rondas encadenadas
    pairs = [(1, 2), (3, 4)]
    cur = 0
    for r in range(4):
        a, b = pairs[cur]
        c, e = pairs[1 - cur]
        s.put("FROUND", f"FROUND r{a}, r{b}, 0, {r}, r{c}, r{e}", [a, b], [c, e])
        cur = 1 - cur
    a, b = pairs[cur]           # tras 4 rondas queda en (r1,r2)
    s.ap(0, a)
    s.ap(4, b)
    cl, cr = enc(L, R, KEY)
    # descifrado: rondas 3..0 con operandos cruzados (FROUND rR, rL, k, r, rR, rL)
    for r in (3, 2, 1, 0):
        a, b = pairs[cur]
        c, e = pairs[1 - cur]
        s.put("FROUND", f"FROUND r{b}, r{a}, 0, {r}, r{e}, r{c}", [b, a], [e, c])
        cur = 1 - cur
    a, b = pairs[cur]
    s.ap(8, a)
    s.ap(12, b)
    exp = ["# cifrado de 4 rondas contra la referencia en C y descifrado de vuelta",
           f"mem 0x10000 = {hexw(cl)}", f"mem 0x10004 = {hexw(cr)}",
           f"mem 0x10008 = {hexw(L)}", f"mem 0x1000c = {hexw(R)}"] + [f"forbid {hexw(k)}" for k in KEY]
    write(d, "feistel_bloque", ["; feistel_bloque.asm - Cifrado y descifrado Feistel4 de un bloque con 8 FROUND"],
          s.text() + ["        FIN"], exp)


def gen_boveda(d):
    s = Sched()
    s.gp()
    SECRET = 0xA5A5A5A5
    s.const(1, 0x11111111)       # centinelas de destino
    s.const(2, 0x22222222)
    s.const(10, 0x0000AAAA)      # L
    s.const(11, 0x0000BBBB)      # R
    # 1) sin autenticar: LOADKEY y FROUND quedan bloqueados
    s.const(6, SECRET)
    s.put("LOADKEY", "LOADKEY r6, 0, 0", [6], [])
    s.put("FROUND", "FROUND r10, r11, 0, 0, r1, r2", [10, 11], [1, 2])
    s.put("RDSR", "RDSR r20", [], [20])               # esperado 0x06: VAULT_ERR + ERR_CODE=001
    # 2) AUTH incorrecto
    s.const(5, 0x1234)
    s.put("AUTH", "AUTH r5", [5], [])
    s.put("RDSR", "RDSR r21", [], [21])               # 0x0A: VAULT_ERR + ERR_CODE=010
    # 3) AUTH correcto (limpia errores)
    s.const(5, 0xCAFE1234)
    s.put("AUTH", "AUTH r5", [5], [])
    s.put("RDSR", "RDSR r22", [], [22])               # 0x01
    # 4) cargar las llaves 0 y 1 (distintas) y cifrar un bloque con cada una
    for kidx, key in ((0, KEY), (1, KEY1)):
        for i, k in enumerate(key):
            s.const(6, k)
            s.put("LOADKEY", f"LOADKEY r6, {kidx}, {i}", [6], [])
    s.put("SUM", "SUM r0, r0, r6", [], [6])           # borra el ultimo valor de llave del GPR
    s.const(5, 0)
    s.put("FROUND", "FROUND r10, r11, 0, 0, r3, r4", [10, 11], [3, 4])   # llave 0
    s.put("FROUND", "FROUND r10, r11, 1, 0, r7, r8", [10, 11], [7, 8])   # llave 1
    s.put("LOADKEY", "LOADKEY r0, 3, 3", [0], [])                         # escribe 0 en bovedas[3][3]
    # 5) LOGOUT y bloqueo
    s.put("LOGOUT", "LOGOUT", [], [])
    s.put("RDSR", "RDSR r23", [], [23])               # 0x00
    s.put("FROUND", "FROUND r10, r11, 0, 0, r1, r2", [10, 11], [1, 2])    # bloqueado: r1,r2 no cambian
    s.put("RDSR", "RDSR r24", [], [24])               # 0x06
    exp_r3 = (0xBBBB, 0xAAAA ^ F(0xBBBB, KEY[0]))
    exp_r7 = (0xBBBB, 0xAAAA ^ F(0xBBBB, KEY1[0]))
    exp = ["# la boveda bloquea sin AUTH, AUTH falla con credencial incorrecta, las llaves no son legibles",
           "r1 = 0x11111111", "r2 = 0x22222222", "r20 = 0x6", "r21 = 0xa", "r22 = 0x1", "r23 = 0x0", "r24 = 0x6",
           "sr = 0x6",
           f"r3 = {hexw(exp_r3[0])}", f"r4 = {hexw(exp_r3[1])}",
           f"r7 = {hexw(exp_r7[0])}", f"r8 = {hexw(exp_r7[1])}"] + \
          [f"forbid {hexw(k)}" for k in KEY + KEY1 + [SECRET]]
    write(d, "boveda", ["; boveda.asm - Control de acceso de la boveda: AUTH/LOGOUT/RDSR, bloqueo por hardware y aislamiento"],
          s.text() + ["        FIN"], exp)


def gen_mixto(d):
    s = Sched()
    s.gp()
    auth(s)
    loadkeys(s, KEY, 0)
    s.const(10, 0x10000)         # puntero al buffer (== gp)
    s.const(13, 0)               # contador
    s.const(14, 3)               # numero de bloques
    s.barrier()
    s.drain()
    pre = s.text(drain=False)
    body = []
    def B(*parts):
        body.append("        " + " | ".join(parts) if parts else "        NOP")
    # cuerpo del lazo: 18 bundles; ALU, LSU, BRU y cripto en los mismos bundles
    B("CP 0(r10), r1", "SUMI r10, 8, r12")
    B("CP 4(r10), r2", "SUMI r13, 1, r13")
    B(); B()
    B("SUMI r15, 1, r15", "FROUND r1, r2, 0, 0, r3, r4")
    B(); B()
    B("SUMI r15, 1, r15", "FROUND r3, r4, 0, 1, r1, r2")
    B(); B()
    B("SUMI r15, 1, r15", "FROUND r1, r2, 0, 2, r3, r4")
    B(); B()
    B("SUMI r15, 1, r15", "FROUND r3, r4, 0, 3, r1, r2")
    B(); B()
    B("AP 0(r10), r1")
    B("AP 4(r10), r2", "SUM r12, r0, r10", "SMQ r13, r14, Lloop")
    B(); B()
    # datos: 3 bloques de texto plano
    blocks = [(0x00000000, 0x00000000), (0x25DBFAC1, 0x4B5C952C), (0xDEADBEEF, 0x0BADCAFE)]
    exp = ["# lazo con ALU+LSU+BRU+cripto en los mismos bundles: cifra 3 bloques en el lugar", "r13 = 3", "r15 = 12"]
    data = [".data"]
    for i, (L, R) in enumerate(blocks):
        data.append(f"        .word {hexw(L)}, {hexw(R)}")
        cl, cr = enc(L, R, KEY)
        exp += [f"mem {0x10000 + 8*i:#x} = {hexw(cl)}", f"mem {0x10000 + 8*i + 4:#x} = {hexw(cr)}"]
    exp += [f"forbid {hexw(k)}" for k in KEY]
    lines = pre + ["Lloop:" + body[0][6:]] + body[1:]
    write(d, "mixto", ["; mixto.asm - Cifra 3 bloques de la memoria con un lazo que combina instrucciones tradicionales y FROUND"],
          lines + ["        FIN"] + data, exp)


def parse_key_hex(s):
    h = re.sub(r"(?i)^0x", "", re.sub(r"[\s_]", "", s))
    if len(h) != 32 or any(c not in "0123456789abcdefABCDEF" for c in h):
        sys.stderr.write("llave: 32 digitos hex (4 subllaves de 8), p.ej. 00112233445566778899aabbccddeeff\n")
        sys.exit(2)
    return [int(h[i:i + 8], 16) for i in range(0, 32, 8)]


def asm_buffer(modo, key):
    """Bundles para cifrar o descifrar el buffer del buzon 0x1FFF0 con `key` en la llave 0."""
    s = Sched()
    s.gp()
    auth(s)
    loadkeys(s, key, 0)
    s.const(27, 0x1FFF0)
    s.put("CP", "CP 0(r27), r10", [27], [10])     # direccion del buffer
    s.put("CP", "CP 8(r27), r14", [27], [14])     # cantidad de bloques de 8 bytes
    s.const(13, 0)
    s.barrier()
    s.drain()
    pre = s.text(drain=False)
    body = []
    def B(*parts):
        body.append("        " + " | ".join(parts) if parts else "        NOP")
    if modo == "cifrar":
        rounds = ["FROUND r1, r2, 0, 0, r3, r4", "FROUND r3, r4, 0, 1, r1, r2",
                  "FROUND r1, r2, 0, 2, r3, r4", "FROUND r3, r4, 0, 3, r1, r2"]
    else:
        rounds = ["FROUND r2, r1, 0, 3, r4, r3", "FROUND r4, r3, 0, 2, r2, r1",
                  "FROUND r2, r1, 0, 1, r4, r3", "FROUND r4, r3, 0, 0, r2, r1"]
    B("CP 0(r10), r1", "SUMI r10, 8, r12")
    B("CP 4(r10), r2", "SUMI r13, 1, r13")
    B(); B()
    for r in rounds:
        B(r)
        B(); B()
    B("AP 0(r10), r1")
    B("AP 4(r10), r2", "SUM r12, r0, r10", "SMQ r13, r14, Lloop")
    B(); B()
    header = [f"; {modo}_buffer.asm - {modo.capitalize()} en el lugar el buffer indicado por el buzon de E/S (0x1FFF0)"]
    lines = pre + ["Lloop:" + body[0][6:]] + body[1:] + ["        FIN"]
    return header, lines


def gen_buffer(d, modo, key=None):
    """cifrar_buffer / descifrar_buffer: leen el buzon 0x1FFF0 (direccion, tamano, bloques) y
    transforman el buffer en el lugar con la llave indicada (por omision la de demostracion)."""
    header, lines = asm_buffer(modo, key or KEY)
    write(d, modo + "_buffer", header, lines, [])
    os.remove(os.path.join(d, modo + "_buffer.expect"))


def emit_buffer(path, modo, key):
    header, lines = asm_buffer(modo, key)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        f.write("\n".join(header + [".text"] + lines) + "\n")


def main():
    argv = sys.argv[1:]
    if argv and argv[0] in ("-h", "--help"):
        print("uso: gen_programs.py [dir]                  # regenera programs/*.asm")
        print("     gen_programs.py --buffer cifrar|descifrar --key HEX --out archivo.asm")
        return
    if argv and argv[0] == "--buffer":
        modo = argv[1] if len(argv) > 1 else ""
        if modo in ("enc", "encrypt"):
            modo = "cifrar"
        if modo in ("dec", "decrypt"):
            modo = "descifrar"
        if modo not in ("cifrar", "descifrar"):
            sys.stderr.write("uso: gen_programs.py --buffer cifrar|descifrar --key HEX --out archivo.asm\n")
            sys.exit(2)
        key, out = KEY, None
        i = 2
        while i < len(argv):
            if argv[i] == "--key" and i + 1 < len(argv):
                key = parse_key_hex(argv[i + 1]); i += 2
            elif argv[i] == "--out" and i + 1 < len(argv):
                out = argv[i + 1]; i += 2
            else:
                sys.stderr.write(f"argumento no reconocido: {argv[i]}\n")
                sys.exit(2)
        if not out:
            sys.stderr.write("falta --out archivo.asm\n")
            sys.exit(2)
        emit_buffer(out, modo, key)
        return
    d = argv[0] if argv else os.path.join(os.path.dirname(__file__), "..", "programs")
    gen_fround(d)
    gen_feistel(d)
    gen_boveda(d)
    gen_mixto(d)
    gen_buffer(d, "cifrar")
    gen_buffer(d, "descifrar")


if __name__ == "__main__":
    main()
