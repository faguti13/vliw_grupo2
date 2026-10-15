#!/usr/bin/env python3
"""traza.py (extra) - Anota la traza +TRACE de tb_top con las etiquetas del .lst del ensamblador."""
import re
import sys


def main():
    if len(sys.argv) != 3:
        print("uso: traza.py programa.lst traza.txt", file=sys.stderr)
        return 2
    labels = {}
    for line in open(sys.argv[1]):
        m = re.match(r"; ([0-9a-f]{8})  (\S+)$", line.strip())
        if m:
            labels[int(m.group(1), 16)] = m.group(2)
    for line in open(sys.argv[2]):
        m = re.search(r"EX pc=([0-9a-f]{8})", line)
        if m and int(m.group(1), 16) in labels:
            line = line.rstrip("\n") + f"   <{labels[int(m.group(1), 16)]}>\n"
        sys.stdout.write(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
