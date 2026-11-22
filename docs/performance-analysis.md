# Análisis de rendimiento (Proyecto II)

Metodología y resultados medidos en la rama de integración (`feat/integracion-p2`)
sobre el procesador Harvard con L1-D, L2 inclusiva, write/eviction buffers y DRAM
a 25 MHz (\(T_{mem} = 53\) ciclos de CPU). Los datos brutos están en
`docs/evidencias/l2-patrones.csv` (regenerar con `make bench-l2`).

## 1. Metodología

### 1.1 Matriz de esta entrega

| Eje | Valores |
|---|---|
| Programas | `bench_secuencial`, `bench_stride`, `bench_aleatorio` (patrones del enunciado) y `mixto` (referencia P1) |
| Configuraciones | `nocache` (MODE=1), `l1` (MODE=2), `base` (MODE=3, L1+L2 inclusiva, L1 WB+WA) |
| Métrica principal | `HALT cycles=` de `tb_top` (ciclos totales hasta FIN) |
| Corrección | `check_dump.py` contra `programs/<n>.expect` — todas PASS |

```
make bench-l2          # regenera el CSV
make run PROG=programs/bench_secuencial.asm CFG=nocache
make run PROG=programs/bench_secuencial.asm CFG=base
```

### 1.2 Fórmulas (enunciado)

\[
\mathrm{IPC} = \frac{\text{instrucciones no-NOP}}{\text{ciclos totales}}
\]

Con \(T_{L1}=1\), \(T_{L2}=8\), \(T_{mem}=53\) (\(f_{mem}=25\,\mathrm{MHz}\)):

\[
\mathrm{AMAT} = 1 + \mathrm{MR}_{L1}\,(8 + \mathrm{MR}_{L2}\cdot 53)
\quad\text{(base)}
\]

| Config | Costo efectivo de un acceso que falla en L1 |
|---|---|
| `nocache` | cada `CP`/`AP` paga \(T_{mem}=53\) |
| `l1` | miss → fill desde DRAM (\(3 + T_{mem}\) aprox.) |
| `base` | miss L1 → hit L2 (8) o miss L2 (\(8+T_{mem}\)) |

## 2. Resultados medidos

| Programa | nocache | solo L1 | base (L1+L2) | nocache / base |
|---|---:|---:|---:|---:|
| `bench_secuencial` | 919 | 126 | 132 | **6.96×** |
| `bench_stride` | 1031 | 462 | 504 | **2.05×** |
| `bench_aleatorio` | 919 | 291 | 315 | **2.92×** |
| `mixto` | 765 | 184 | 190 | **4.03×** |

Bundles ejecutados idénticos entre configs (p. ej. 68 en secuencial, 122 en
`mixto`): la diferencia de ciclos es **solo stalls de memoria**, no más trabajo
de ALU. Riesgos RAW/WAW del monitor: **0** en todas las corridas.

### 2.1 Lectura

- **nocache → L1.** El salto dominante: deja de pagarse \(T_{mem}\) en cada acceso
  con localidad. En secuencial (una línea, 1 miss + 7 hits) L1 basta (~7×).
- **L1 → base (L1+L2).** En estos programas chicos el working set cabe en L1; L2
  casi no acelera y a veces suma unos ciclos (snoop / fill inclusivo). Eso es
  coherente con el enunciado: L2 brilla cuando L1 hace thrashing (strides grandes
  / working set > 4 KB). Aquí la evidencia principal es **jerarquía vs sin caché**.
- **Inclusiva.** Política fija del equipo (ver `docs/l2-coherencia.md`): un solo
  núcleo; L1 ⊆ L2; invalidación hacia atrás al desalojar en L2.

### 2.2 Decisiones de diseño que afectan la cifra

| Decisión | Valor en `base` | Dónde |
|---|---|---|
| L1 escritura | write-back + write-allocate | `L1_WT=0`, `rtl/l1d_cache.sv` |
| L1 reemplazo | LRU 1 bit | `rtl/l1d_cache.sv` |
| L2 | WB, Tree-PLRU, inclusiva, hit 8 | `rtl/l2_cache.sv` |
| RAW en buffers | store-to-load forwarding | `BUFFER_FWD=1`, write/eviction buffer |
| \(f_{mem}\) | 25 MHz → \(T_{mem}=53\) | `MEM_CLK_DIV=4`, `rtl/dram_ctrl.sv` |

Comparar `CFG=wt` (L1 write-through) es opcional: `make run PROG=... CFG=wt`.

## 3. Cómo reproducir en defensa

```
cd vliw_grupo2
git checkout feat/integracion-p2   # o main tras el merge
make run PROG=programs/bench_secuencial.asm CFG=nocache   # ~919 ciclos
make run PROG=programs/bench_secuencial.asm CFG=base      # ~132 ciclos
make l2                                                    # tb L2 con stubs
make progs CFG=base                                        # regresion funcional
```

ASM a mano: respetar RAW ≥ 3 bundles (`tools/vliwasm.py --check-hazards`). Un miss
congela el **bundle completo** (`dmem_stall`); eso no se “arregla” con NOP de
registros — son stalls de la jerarquía.

## 4. Alcance respecto a la matriz compilador × caché

Esta entrega documenta la **jerarquía de memoria** con programas ASM del repo
(iteración 5 del enunciado: secuencial / stride / aleatorio). La matriz amplia
JAF (`-O0`/`-O2` × benchmarks `.oly`) vive en el flujo conjunto con `P1_CE1108`
cuando el compilador apunta `VLIW_DIR` a este repo; no se inventan esas cifras
aquí. Fórmulas y contadores (Cuadros 1–2) están cableados en `perf_counters` y
`mem_subsystem`.
