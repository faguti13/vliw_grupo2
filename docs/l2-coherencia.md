# Caché L2 inclusiva e invalidación hacia atrás

La L2 del Proyecto II es **inclusiva** por decisión de diseño. No hay otra política de
inclusión en el RTL: el parámetro se eliminó de `l2_cache`, `mem_subsystem` y `top`.

## Geometría

| | |
|---|---|
| Capacidad | 16 KB |
| Asociatividad | 4 vías |
| Línea | 32 B (8 palabras) |
| Conjuntos | 128 |
| Tag / índice / offset | `addr[15:12]` / `addr[11:5]` / `addr[4:0]` |
| Reemplazo | Tree-PLRU (3 bits por conjunto) |
| Escritura | write-back + write-allocate |
| Hit visible al pipeline | 8 ciclos de stall (búsqueda interna `HIT_LAT - 3 = 5`) |

L1-D es 4 KB. Cabe entera dentro de L2 (16 KB), así que la inclusión es barata: cada línea
válida en L1 tiene (o debe tener) copia en L2.

## Por qué inclusiva

- Un solo núcleo: el invariante L1 ⊆ L2 simplifica el razonamiento y el testbench
  (vista coherente L1 > write buffer > L2 > eviction buffer > DRAM).
- El enunciado pide justificar la política y demostrar la invalidación hacia atrás.
- La comparación de la rúbrica se hace por **profundidad de jerarquía** (`MODE`: sin caché /
  solo L1 / L1+L2), no por varias políticas de inclusión.

## Invalidación hacia atrás

1. Miss de L2 elige víctima (vía libre o Tree-PLRU).
2. Si la víctima es válida → `snoop_req = 1` con `snoop_la` de esa línea.
3. L1 responde `snoop_hit` / `snoop_dirty` / `snoop_line`.
4. Si estaba sucia en L1, esa línea (no la de L2) se empuja al eviction buffer.
5. L1 pierde la copia; la próxima lectura a esa dirección vuelve a fallar en L1 y a pedir L2
   (o DRAM / forwarding del eviction buffer).

`tb/tb_l2_coherence.sv` cubre víctima limpia, víctima sucia en L2, snoop con L1 sucia, orden
PLRU de 4 vías y forwarding desde el eviction buffer.
