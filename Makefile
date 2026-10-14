# Makefile - Procesador VLIW Feistel4 (CE4301, grupo 2)
#
#   make sim                 regresion completa en Icarus Verilog (unitarios + programas)
#   make sim TB=tb_alu       un solo testbench
#   make test                resumen PASS/FAIL de toda la regresion
#   make lint                Verilator --lint-only -Wall
#   make sim-verilator PROG=programs/mixto.asm   simulacion con Verilator
#   make asm PROG=programs/x.asm                 ensambla a build/x.mem
#   make run PROG=programs/x.asm | BIN=archivo.bin   corre un programa
#   make wave TB=tb_top      abre el VCD en GTKWave
#   make vectors             vectores Feistel4 desde la referencia en C
#   make demo-archivo | demo-imagen | demo-compilador | demo | clean

IVERILOG ?= iverilog
VVP      ?= vvp
VERILATOR?= verilator
PYTHON   ?= python3
BUILD    := build

RTL := rtl/vliw_pkg.sv rtl/memory.sv rtl/regfile.sv rtl/alu.sv rtl/lsu.sv rtl/bru.sv \
       rtl/key_vault.sv rtl/crypto_unit.sv rtl/dispatch.sv rtl/fetch.sv rtl/core.sv rtl/top.sv
UNIT_TBS := tb_alu tb_regfile tb_lsu tb_bru tb_dispatch tb_key_vault tb_crypto_unit
TIMEOUT ?= 2000000

# Programas de regresion: cada uno tiene programs/<n>.asm y programs/<n>.expect
PROGS := isa_completa alu_paralelo memoria saltos fround feistel_bloque boveda mixto

.PHONY: all sim test lint sim-verilator asm run wave vectors clean demo demo-archivo demo-imagen demo-compilador

all: sim

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/feistel4_ref: tools/feistel4_ref.c | $(BUILD)
	gcc -O2 -Wall -Wextra -o $@ $<

vectors: $(BUILD)/feistel4_ref
	$(BUILD)/feistel4_ref vectors 16 00112233445566778899aabbccddeeff > $(BUILD)/vectors.hex

$(BUILD)/vectors.hex: $(BUILD)/feistel4_ref
	$(BUILD)/feistel4_ref vectors 16 00112233445566778899aabbccddeeff > $@

# ---- Testbenches unitarios ----
$(BUILD)/%.vvp: tb/%.sv $(RTL) | $(BUILD)
	$(IVERILOG) -g2012 -Wall -o $@ $(RTL) $<

ifdef TB
sim: $(BUILD)/$(TB).vvp $(BUILD)/vectors.hex
	$(VVP) -n $(BUILD)/$(TB).vvp
else
sim: unit progs
endif

unit: $(BUILD)/vectors.hex $(addprefix $(BUILD)/,$(addsuffix .vvp,$(UNIT_TBS)))
	@set -e; for t in $(UNIT_TBS); do $(VVP) -n $(BUILD)/$$t.vvp | grep -E "PASS|FAIL"; done

# ---- Testbench de sistema (tb_top) ----
$(BUILD)/tb_top.vvp: tb/tb_top.sv tb/hazard_monitor.sv $(RTL) | $(BUILD)
	$(IVERILOG) -g2012 -Wall -o $@ $(RTL) tb/hazard_monitor.sv tb/tb_top.sv

$(BUILD)/%.mem: programs/%.asm tools/vliwasm.py | $(BUILD)
	$(PYTHON) tools/vliwasm.py --check-hazards -o $(BUILD)/$*.mem --bin $(BUILD)/$*.bin --lst $(BUILD)/$*.lst $<

progs: $(BUILD)/tb_top.vvp $(addprefix $(BUILD)/,$(addsuffix .mem,$(PROGS))) $(BUILD)/feistel4_ref
	@set -e; for p in $(PROGS); do \
	  $(VVP) -n $(BUILD)/tb_top.vvp +PROG=$(BUILD)/$$p.mem +REGS=$(BUILD)/$$p.regs +DUMP=$(BUILD)/$$p.dump \
	      +DUMPLO=65536 +DUMPHI=69631 +TIMEOUT=$(TIMEOUT) > $(BUILD)/$$p.log; \
	  $(PYTHON) tools/check_dump.py --regs $(BUILD)/$$p.regs --dump $(BUILD)/$$p.dump \
	      --expect programs/$$p.expect --name $$p --log $(BUILD)/$$p.log; \
	done

test: sim

# ---- Ensamblar / ejecutar un programa ----
asm: $(BUILD)
	$(PYTHON) tools/vliwasm.py --check-hazards -o $(BUILD)/$(basename $(notdir $(PROG))).mem \
	    --bin $(BUILD)/$(basename $(notdir $(PROG))).bin --lst $(BUILD)/$(basename $(notdir $(PROG))).lst $(PROG)

run: $(BUILD)/tb_top.vvp
	@set -e; \
	if [ -n "$(BIN)" ]; then $(PYTHON) tools/bin2mem.py $(BIN) $(BUILD)/run.mem; M=$(BUILD)/run.mem; \
	else $(MAKE) -s asm PROG=$(PROG); M=$(BUILD)/$(basename $(notdir $(PROG))).mem; fi; \
	$(VVP) -n $(BUILD)/tb_top.vvp +PROG=$$M $(if $(DATA),+DATA=$(DATA),) +REGS=$(BUILD)/run.regs \
	    +DUMP=$(BUILD)/memory_dump.txt +DUMPLO=$${DUMPLO:-65536} +DUMPHI=$${DUMPHI:-1048575} +VCD=$(BUILD)/waves/run.vcd \
	    $(if $(TRACE),+TRACE,) +TIMEOUT=$(TIMEOUT)

# ---- Ondas ----
wave:  
	gtkwave $(BUILD)/waves/run.vcd tb/waves/tb_top.gtkw &

# ---- Verilator ----
VLINT := -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PINCONNECTEMPTY
lint:
	$(VERILATOR) --lint-only $(VLINT) --top-module top $(RTL)

$(BUILD)/vl/Vtb_top: $(RTL) tb/tb_top.sv tb/hazard_monitor.sv | $(BUILD)
	$(VERILATOR) --binary --timing --trace -Wno-fatal -Wno-lint -Wno-style -Wno-WIDTH --top-module tb_top \
	    -Mdir $(BUILD)/vl $(RTL) tb/hazard_monitor.sv tb/tb_top.sv

sim-verilator: $(BUILD)/vl/Vtb_top
	@set -e; $(MAKE) -s asm PROG=$(PROG); \
	$(BUILD)/vl/Vtb_top +PROG=$(BUILD)/$(basename $(notdir $(PROG))).mem +REGS=$(BUILD)/vl.regs +TIMEOUT=$(TIMEOUT)

# ---- Demos ----
demo-archivo: $(BUILD)/tb_top.vvp $(BUILD)/feistel4_ref
	bash tools/demo.sh texto

demo-imagen: $(BUILD)/tb_top.vvp $(BUILD)/feistel4_ref
	bash tools/demo.sh imagen

demo-compilador: $(BUILD)/tb_top.vvp
	$(MAKE) -C ../P1_CE1108 e2e VLIW_DIR=$(CURDIR)

demo: sim demo-archivo demo-imagen

clean:
	rm -rf $(BUILD)

# Mismos registros finales en Icarus y Verilator para todos los programas de regresion
.PHONY: cmp-sims
cmp-sims: $(BUILD)/vl/Vtb_top progs
	@set -e; for p in $(PROGS); do \
	  $(BUILD)/vl/Vtb_top +PROG=$(BUILD)/$$p.mem +REGS=$(BUILD)/$$p.vl.regs +TIMEOUT=$(TIMEOUT) > /dev/null; \
	  if cmp -s $(BUILD)/$$p.regs $(BUILD)/$$p.vl.regs; then echo "cmp-sims $$p: IGUAL"; else echo "cmp-sims $$p: DIFIERE"; exit 1; fi; \
	done
