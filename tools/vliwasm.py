#!/usr/bin/env python3
"""vliwasm.py - Ensamblador propio del procesador VLIW Feistel4 (CE4301, grupo 2).

Cada linea es un bundle; los slots se separan con '|'. Cada instruccion se coloca
sola en el slot que le corresponde por su tipo y los slots omitidos se rellenan
con NOP. Dos pasadas: la primera asigna direcciones a las etiquetas, la segunda
codifica. Sintaxis completa en docs/isa.md (adenda v1.1).

Uso: vliwasm.py [--check-hazards] [-o salida.mem] [--bin salida.bin] [--lst salida.lst] fuente.asm
"""
import argparse
import re
import struct
import sys

DATA_BASE = 0x10000
STACK_TOP = 0x100000
NOPS = [0x78, 0x7A, 0x7B, 0x7C]

REG_ALIAS = {"zero": 0, "gp": 28, "sp": 29, "fp": 30, "ra": 31}
REG_F = {"SUM": 0, "REST": 1, "MUL": 2, "DIV": 3, "OLY": 4, "OLO": 5, "LOE": 6, "DLI": 7, "DLD": 8, "COMP": 9}
IMM_F = {"SUMI": 0, "RESTI": 1, "MULI": 2, "DIVI": 3, "DLII": 4, "DLDI": 5}
COND_F = {"SIG": 0, "SNIG": 1, "SMI": 2, "SMQ": 3}
JMP_F = {"S": 4, "SYE": 5}


class AsmError(Exception):
    pass


def slot_of(mn):
    if mn in REG_F or mn in IMM_F:
        return 0
    if mn in ("CP", "AP"):
        return 1
    if mn in COND_F or mn in JMP_F or mn in ("SRG", "FIN"):
        return 2
    if mn in ("LOADKEY", "FROUND", "AUTH", "LOGOUT", "RDSR"):
        return 3
    return None


class Assembler:
    def __init__(self):
        self.equ = {}
        self.labels = {}      # etiqueta -> direccion absoluta
        self.bundles = []     # (lineno, texto, [instrs por slot], direccion)
        self.data = bytearray()
        self.data_labels = {}

    # ------------------------------------------------------------ utilidades
    def err(self, ln, msg):
        raise AsmError(f"linea {ln}: {msg}")

    def reg(self, tok, ln):
        t = tok.strip().lower()
        if t in REG_ALIAS:
            return REG_ALIAS[t]
        m = re.fullmatch(r"r(\d+)", t)
        if not m or int(m.group(1)) > 31:
            self.err(ln, f"registro invalido '{tok}'")
        return int(m.group(1))

    def num(self, tok, ln):
        t = tok.strip()
        if t in self.equ:
            return self.equ[t]
        if t in self.labels:
            return self.labels[t]
        try:
            return int(t, 0)
        except ValueError:
            self.err(ln, f"valor invalido '{tok}'")

    @staticmethod
    def split_ops(s):
        return [x.strip() for x in s.split(",")] if s.strip() else []

    # ------------------------------------------------------------ parseo
    def parse(self, text):
        section = "text"
        pending_labels = []
        addr = 0
        for ln, raw in enumerate(text.splitlines(), 1):
            line = raw.split(";")[0].strip()
            if not line:
                continue
            while True:
                m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$", line)
                if not m:
                    break
                pending_labels.append(m.group(1))
                line = m.group(2).strip()
            if not line:
                continue
            if line.startswith("."):
                parts = line.split(None, 1)
                d = parts[0].lower()
                arg = parts[1] if len(parts) > 1 else ""
                if d == ".text":
                    section = "text"
                elif d == ".data":
                    section = "data"
                elif d == ".equ":
                    a = self.split_ops(arg)
                    if len(a) != 2:
                        self.err(ln, ".equ nombre, valor")
                    self.equ[a[0]] = self.num(a[1], ln)
                elif d == ".word" and section == "data":
                    for lab in pending_labels:
                        self.labels[lab] = DATA_BASE + len(self.data)
                    pending_labels = []
                    for v in self.split_ops(arg):
                        self.data += struct.pack(">I", self.num(v, ln) & 0xFFFFFFFF)
                elif d == ".space" and section == "data":
                    for lab in pending_labels:
                        self.labels[lab] = DATA_BASE + len(self.data)
                    pending_labels = []
                    self.data += bytes(self.num(arg, ln))
                elif d == ".align":
                    n = self.num(arg, ln)
                    if section == "data":
                        while len(self.data) % n:
                            self.data.append(0)
                    else:
                        self.err(ln, ".align solo aplica en .data (los bundles ya estan alineados a 16)")
                else:
                    self.err(ln, f"directiva no valida en la seccion {section}: {d}")
                continue
            if section != "text":
                self.err(ln, "instruccion fuera de .text")
            for lab in pending_labels:
                if lab in self.labels:
                    self.err(ln, f"etiqueta repetida '{lab}'")
                self.labels[lab] = addr
            pending_labels = []
            slots = [None] * 4
            for part in line.split("|"):
                part = part.strip()
                if not part:
                    continue
                toks = part.split(None, 1)
                mn = toks[0].upper()
                ops = self.split_ops(toks[1]) if len(toks) > 1 else []
                if mn == "NOP":
                    continue
                s = slot_of(mn)
                if s is None:
                    self.err(ln, f"instruccion desconocida '{toks[0]}'")
                if slots[s] is not None:
                    self.err(ln, f"el slot {s} ya esta ocupado en este bundle (opcode fuera de su slot o 2 instrucciones del mismo tipo)")
                slots[s] = (mn, ops)
            self.bundles.append((ln, line, slots, addr))
            addr += 16
        if pending_labels:
            for lab in pending_labels:
                self.labels[lab] = addr
        return addr

    # ------------------------------------------------------------ codificacion
    def fits(self, v, bits, ln, what):
        lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
        if not lo <= v <= hi:
            self.err(ln, f"{what} fuera de rango ({v}, {bits} bits con signo)")
        return v & ((1 << bits) - 1)

    def enc(self, mn, ops, ln, addr):
        def need(n):
            if len(ops) != n:
                self.err(ln, f"{mn} espera {n} operandos")
        if mn in REG_F:
            need(3)
            return (self.reg(ops[0], ln) << 17) | (self.reg(ops[1], ln) << 12) | (self.reg(ops[2], ln) << 7) | (REG_F[mn] << 3)
        if mn in IMM_F:
            need(3)
            v = self.num(ops[1], ln)
            if mn in ("DLII", "DLDI"):
                if not 0 <= v <= 31:
                    self.err(ln, "desplazamiento inmediato fuera de 0..31")
                im = v
            else:
                im = self.fits(v, 15, ln, "inmediato")
            return (((im >> 14) & 1) << 31) | (self.reg(ops[0], ln) << 26) | ((im & 0x3FFF) << 12) | \
                   (self.reg(ops[2], ln) << 7) | (IMM_F[mn] << 3) | 1
        if mn in ("CP", "AP"):
            need(2)
            m = re.fullmatch(r"(.*)\((\w+)\)", ops[0].replace(" ", ""))
            if not m:
                self.err(ln, f"{mn} espera off(rbase), reg")
            im = self.fits(self.num(m.group(1) or "0", ln), 15, ln, "offset")
            return (((im >> 14) & 1) << 31) | (self.reg(m.group(2), ln) << 26) | ((im & 0x3FFF) << 12) | \
                   (self.reg(ops[1], ln) << 7) | ((0 if mn == "CP" else 1) << 3) | 2
        if mn in COND_F:
            need(3)
            off = self.branch_off(ops[2], addr, ln, 15)
            return (off << 17) | (self.reg(ops[0], ln) << 12) | (self.reg(ops[1], ln) << 7) | (COND_F[mn] << 3) | 3
        if mn in JMP_F:
            need(1)
            off = self.branch_off(ops[0], addr, ln, 25)
            return (off << 7) | (JMP_F[mn] << 3) | 3
        if mn == "SRG":
            need(1)
            return (self.reg(ops[0], ln) << 12) | (6 << 3) | 3
        if mn == "FIN":
            need(0)
            return (7 << 3) | 3
        if mn == "LOADKEY":
            need(3)
            k, s = self.num(ops[1], ln), self.num(ops[2], ln)
            if not (0 <= k < 4 and 0 <= s < 4):
                self.err(ln, "key_idx/subkey_idx deben estar en 0..3")
            return (s << 19) | (k << 17) | (self.reg(ops[0], ln) << 7) | (0 << 3) | 4
        if mn == "FROUND":
            need(6)
            k, r = self.num(ops[2], ln), self.num(ops[3], ln)
            if not (0 <= k < 4 and 0 <= r < 4):
                self.err(ln, "key_idx/round_idx deben estar en 0..3")
            dl, dr = self.reg(ops[4], ln), self.reg(ops[5], ln)
            if dl == dr:
                self.err(ln, "FROUND: rd_L y rd_R deben ser distintos")
            return (dl << 26) | (dr << 21) | (r << 19) | (k << 17) | (self.reg(ops[0], ln) << 12) | \
                   (self.reg(ops[1], ln) << 7) | (1 << 3) | 4
        if mn == "AUTH":
            need(1)
            return (self.reg(ops[0], ln) << 7) | (0 << 3) | 5
        if mn == "LOGOUT":
            need(0)
            return (1 << 3) | 5
        if mn == "RDSR":
            need(1)
            return (self.reg(ops[0], ln) << 7) | (2 << 3) | 5
        self.err(ln, f"instruccion no soportada '{mn}'")

    def branch_off(self, tok, addr, ln, bits):
        t = tok.strip()
        if t not in self.labels:
            self.err(ln, f"etiqueta no definida '{t}'")
        delta = self.labels[t] - (addr + 16)
        if delta % 16:
            self.err(ln, "destino no alineado a bundle")
        return self.fits(delta // 16, bits, ln, "offset de salto")

    def assemble(self):
        out = []
        for ln, line, slots, addr in self.bundles:
            words = []
            for s in range(4):
                if slots[s] is None:
                    words.append(NOPS[s])
                else:
                    words.append(self.enc(slots[s][0], slots[s][1], ln, addr))
            dests = []
            for s in range(4):
                if slots[s] is None:
                    continue
                mn, ops = slots[s]
                if mn in REG_F or mn in IMM_F:
                    d = self.reg(ops[2], ln)
                elif mn == "CP":
                    d = self.reg(ops[1], ln)
                elif mn == "SYE":
                    d = 31
                elif mn == "FROUND":
                    dests += [self.reg(ops[4], ln), self.reg(ops[5], ln)]
                    continue
                elif mn == "RDSR":
                    d = self.reg(ops[0], ln)
                else:
                    continue
                dests.append(d)
            dests = [d for d in dests if d != 0]
            if len(dests) != len(set(dests)):
                self.err(ln, "dos slots del bundle escriben el mismo registro")
            out.append((ln, line, words, addr))
        return out


def check_hazards(asm, assembled):
    """Advertencias RAW lineales: lectura a menos de 3 bundles de la escritura."""
    last = {}
    warns = []
    for idx, (ln, line, words, addr) in enumerate(assembled):
        slots = asm.bundles[idx][2]
        reads, writes = [], []
        for s, ins in enumerate(slots):
            if ins is None:
                continue
            mn, ops = ins
            R = lambda t: asm.reg(t, ln)
            if mn in REG_F:
                reads += [R(ops[0]), R(ops[1])]; writes.append(R(ops[2]))
            elif mn in IMM_F:
                reads.append(R(ops[0])); writes.append(R(ops[2]))
            elif mn == "CP":
                reads.append(R(re.fullmatch(r"(.*)\((\w+)\)", ops[0].replace(" ", "")).group(2))); writes.append(R(ops[1]))
            elif mn == "AP":
                reads += [R(re.fullmatch(r"(.*)\((\w+)\)", ops[0].replace(" ", "")).group(2)), R(ops[1])]
            elif mn in COND_F:
                reads += [R(ops[0]), R(ops[1])]
            elif mn == "SYE":
                writes.append(31)
            elif mn == "SRG":
                reads.append(R(ops[0]))
            elif mn == "LOADKEY":
                reads.append(R(ops[0]))
            elif mn == "FROUND":
                reads += [R(ops[0]), R(ops[1])]; writes += [R(ops[4]), R(ops[5])]
            elif mn == "AUTH":
                reads.append(R(ops[0]))
            elif mn == "RDSR":
                writes.append(R(ops[0]))
        for r in reads:
            if r != 0 and r in last and idx - last[r] < 3:
                warns.append(f"linea {ln}: advertencia RAW r{r} leido a {idx - last[r]} bundle(s) de su escritura (se requieren >= 3)")
        for w in writes:
            if w != 0:
                last[w] = idx
    return warns


def main():
    ap = argparse.ArgumentParser(description="Ensamblador VLIW Feistel4")
    ap.add_argument("fuente")
    ap.add_argument("-o", "--mem", help="salida .mem (un byte por linea, con @direccion)")
    ap.add_argument("--bin", help="salida .bin (encabezado + codigo + datos)")
    ap.add_argument("--lst", help="listado (direccion, hexadecimal, fuente)")
    ap.add_argument("--check-hazards", action="store_true", help="advierte dependencias RAW a menos de 3 bundles")
    a = ap.parse_args()
    asm = Assembler()
    try:
        with open(a.fuente, encoding="utf-8") as f:
            asm.parse(f.read())
        assembled = asm.assemble()
    except AsmError as e:
        print(f"{a.fuente}: error: {e}", file=sys.stderr)
        return 1
    code = bytearray()
    for _, _, words, _ in assembled:
        for w in words:
            code += struct.pack(">I", w)
    if a.check_hazards:
        for w in check_hazards(asm, assembled):
            print(f"{a.fuente}: {w}", file=sys.stderr)
    if a.mem:
        with open(a.mem, "w") as f:
            f.write("@00000000\n")
            for b in code:
                f.write(f"{b:02x}\n")
            if asm.data:
                f.write(f"@{DATA_BASE:08x}\n")
                for b in asm.data:
                    f.write(f"{b:02x}\n")
    if a.bin:
        with open(a.bin, "wb") as f:
            f.write(b"VLW1" + struct.pack(">7I", 1, 0, 0, len(code), DATA_BASE, len(asm.data), STACK_TOP))
            f.write(code)
            f.write(asm.data)
    if a.lst:
        with open(a.lst, "w") as f:
            for ln, line, words, addr in assembled:
                f.write(f"{addr:08x}  {words[0]:08x} {words[1]:08x} {words[2]:08x} {words[3]:08x}  ; {line}\n")
            f.write("\n; tabla de etiquetas\n")
            for k, v in sorted(asm.labels.items(), key=lambda kv: kv[1]):
                f.write(f"; {v:08x}  {k}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
