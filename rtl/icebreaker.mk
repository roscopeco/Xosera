# icebreaker.mk - Xosera for iCEBreaker FPGA board
# vim: set noet ts=8 sw=8

# Using icestorm tools + yosys + nextpnr
# Modified from examples in icestorm distribution for
# up5k_vga by E. Brombaugh (emeb) and further extensively
# hacked by Xark for Xosera purposes

# Primary tools (official binaries available from https://github.com/YosysHQ/oss-cad-suite-build/releases/latest)
#       Yosys
#       nextpnr-ice40
#       Verilator               (optional)
#       Icarus Verilog          (optional)
#       Built using macOS BigSur 11.5.2 and GNU/Linux Ubuntu 20.04 distribution

# This is a hack to get make to exit if command fails (even if command after pipe succeeds, e.g., tee)
SHELL := /bin/bash -o pipefail

# Version bookkeeping
GITSHORTHASH := $(shell git rev-parse --short HEAD)
DIRTYFILES := $(shell git status --porcelain --untracked-files=no | grep rtl/ | grep -v _stats.txt | cut -d " " -f 3-)
ifeq ($(strip $(DIRTYFILES)),)
# "clean" (unmodified) from git
XOSERA_HASH := $(GITSHORTHASH)
XOSERA_CLEAN := 1
$(info === Xosera iCEBreaker [$(XOSERA_HASH)] is CLEAN from git)
else
# "dirty" (HDL modified) from git
XOSERA_HASH := $(GITSHORTHASH)
XOSERA_CLEAN := 0
$(info === Xosera iCEBreaker [$(XOSERA_HASH)] is DIRTY: $(DIRTYFILES))
endif

# Maximum number of CPU cores to use before waiting with FMAX_TEST
MAX_CPUS := 8

# Xosera video mode selection:
# Supported modes:                           (exact) (actual)
#       MODE_640x400    640x400@70Hz    clock 25.175 (25.125) MHz
#       MODE_640x480    640x480@60Hz    clock 25.175 (25.125) MHz
#       MODE_640x480_75 640x480@75Hz    clock 31.500 (31.500) MHz
#       MODE_640x480_85 640x480@85Hz    clock 36.000 (36.000) MHz
#       MODE_720x400    720x400@70Hz    clock 28.322 (28.500) MHz
#       MODE_848x480    848x480@60Hz    clock 33.750 (33.750) MHz (16:9 480p)
#       MODE_800x600    800x600@60Hz    clock 40.000 (39.750) MHz
#       MODE_1024x768   1024x768@60Hz   clock 65.000 (65.250) MHz [fails timing]
#       MODE_1280x720   1280x720@60Hz   clock 74.176 (73.500) MHz [fails timing]
VIDEO_MODE ?= MODE_848x480

# Xosera video output selection:
# Supported video outputs:
#   PMOD_1B2_DVI12              12-bit DVI, PMOD 1A&1B  https://1bitsquared.com/products/pmod-digital-video-interface
#   PMOD_DIGILENT_VGA           12-bit VGA, PMOD 1A&1B  https://store.digilentinc.com/pmod-vga-video-graphics-array/
#   PMOD_XESS_VGA                9-bit VGA, PMOD 1A&1B  http://www.xess.com/shop/product/stickit-vga/
#   PMOD_XESS_VGA_SINGLE         6-bit VGA, PMOD 1B     http://www.xess.com/shop/product/stickit-vga/ (half used)
VIDEO_OUTPUT ?= PMOD_1B2_DVI12

FONTFILES := $(wildcard tilesets/*.mem)

# RTL source and include directory
SRCDIR := .

# log output directory
LOGS := icebreaker/logs

# Xosera project setup for iCEBreaker FPGA
TOP := xosera_iceb
PIN_DEF := icebreaker/icebreaker.pcf
DEVICE := up5k
PACKAGE := sg48

# Verilog source directories
VPATH := $(SRCDIR) icebreaker

# Verilog source files for design
SRC := icebreaker/$(TOP).sv $(wildcard $(SRCDIR)/*.sv)

# Verilog include files for design
INC := $(wildcard $(SRCDIR)/*.svh)

# dot graphic diagram files
DOT := $(SRC:.sv=.dot)

# icestorm tools
YOSYS := yosys
YOSYS_CONFIG := yosys-config
ICEPACK := icepack
ICETIME := icetime
ICEPROG := iceprog
ICEMULTI := icemulti

# Yosys synthesis arguments
#FLOW3 :=
#YOSYS_SYNTH_ARGS := -device u -dsp -abc2 -relut -retime -top $(TOP)
#YOSYS_SYNTH_ARGS := -device u -dsp -abc9 -relut -top $(TOP)
YOSYS_SYNTH_ARGS := -device u -dsp -abc9 -top $(TOP)
FLOW3 := ; scratchpad -copy abc9.script.flow3 abc9.script

# Verilog preprocessor definitions common to all modules
DEFINES := -DNO_ICE40_DEFAULT_ASSIGNMENTS -DGITCLEAN=$(XOSERA_CLEAN) -DGITHASH=$(XOSERA_HASH) -D$(VIDEO_MODE) -D$(VIDEO_OUTPUT) -DICE40UP5K -DICEBREAKER -DSPI_INTERFACE

# Verilator tool (used for "lint")
VERILATOR := verilator
VERILATOR_ARGS := --sv --language 1800-2012 -I$(SRCDIR) -Werror-UNUSED -Wall -Wno-DECLFILENAME
TECH_LIB := $(shell $(YOSYS_CONFIG) --datdir/ice40/cells_sim.v)

# nextPNR tools
NEXTPNR := nextpnr-ice40
NEXTPNR_ARGS :=  --randomize-seed --promote-logic --opt-timing --placer heap

ifeq ($(strip $(VIDEO_OUTPUT)), PMOD_1B2_DVI12)
OUTSUFFIX := dvi_$(subst MODE_,,$(VIDEO_MODE))
else
OUTSUFFIX := vga_$(subst MODE_,,$(VIDEO_MODE))
endif

OUTNAME := $(TOP)_$(OUTSUFFIX)

# defult target is make bitstream
all: icebreaker/$(OUTNAME).bin icebreaker.mk
	@echo === Finished Building iCEBreaker Xosera: $(VIDEO_OUTPUT) $(SPI_INTERFACE) ===

# program iCEBreaker FPGA via USB (may need udev rules or sudo on Linux)
prog: icebreaker/$(OUTNAME).bin icebreaker.mk
	@echo === Programming iCEBreaker Xosera: $(VIDEO_OUTPUT) $(SPI_INTERFACE) ===
	$(ICEPROG) -d i:0x0403:0x6010 $(TOP).bin

# run icetime to generate a timing report
timing: icebreaker/$(OUTNAME).rpt icebreaker.mk
	@echo iCETime timing report: $(TOP).rpt

# run Yosys to generate a "dot" graphical representation of each design file
show: $(DOT) icebreaker.mk

# run Yosys with "noflatten", which will produce a resource count per module
count: $(SRC) $(INC) $(FONTFILES) icebreaker.mk
	@mkdir -p $(LOGS)
	$(YOSYS) -l $(LOGS)/$(OUTNAME)_yosys_count.log -w ".*" -q -p 'verilog_defines $(DEFINES) ; read_verilog -I$(SRCDIR) -sv $(SRC) $(FLOW3) ; synth_ice40 $(YOSYS_SYNTH_ARGS) -noflatten'

# run Verilator to check for Verilog issues
lint: $(SRC) $(INC) $(FONTFILES) icebreaker.mk
	$(VERILATOR) $(VERILATOR_ARGS) --lint-only $(DEFINES) --top-module $(TOP) $(TECH_LIB) $(SRC)

$(DOT): %.dot: %.sv icebreaker.mk
	mkdir -p icebreaker/dot
	$(YOSYS) -l $(LOGS)/$(OUTNAME)_yosys.log -w ".*" -q -p 'verilog_defines $(DEFINES) -DSHOW ; read_verilog -I$(SRCDIR) -sv $< ; show -enum -stretch -signed -width -prefix icebreaker/dot/$(basename $(notdir $<)) $(basename $(notdir $<))'

# synthesize Verilog and create json description
%.json: $(SRC) $(INC) $(FONTFILES) icebreaker.mk
	@echo === Building iCEBreaker Xosera ===
	@rm -f $@
	@mkdir -p $(LOGS)
	$(VERILATOR) $(VERILATOR_ARGS) --lint-only $(DEFINES) --top-module $(TOP) $(TECH_LIB) $(SRC) 2>&1 | tee $(LOGS)/$(OUTNAME)_verilator.log
	$(YOSYS) -l $(LOGS)/$(OUTNAME)_yosys.log -w ".*" -q -p 'verilog_defines $(DEFINES) ; read_verilog -I$(SRCDIR) -sv $(SRC) $(FLOW3) ; synth_ice40 $(YOSYS_SYNTH_ARGS) -json $@'

# make ASCII bitstream from JSON description and device parameters
icebreaker/%_$(OUTSUFFIX).asc: icebreaker/%_$(OUTSUFFIX).json $(PIN_DEF) icebreaker.mk
	@rm -f $@
	@mkdir -p $(LOGS)
	@-cp $(OUTNAME)_stats.txt $(LOGS)/$(OUTNAME)_stats_last.txt
ifdef FMAX_TEST	# run nextPNR FMAX_TEST times to determine "Max frequency" range
	@echo === Synthesizing $(FMAX_TEST) bitstreams for best fMAX
	@echo $(NEXTPNR) -l $(LOGS)/$(OUTNAME)_nextpnr.log -q $(NEXTPNR_ARGS) --$(DEVICE) --package $(PACKAGE) --json $< --pcf $(PIN_DEF) --asc $@
	@mkdir -p $(LOGS)/fmax
	@rm -f $(LOGS)/fmax/*
	@cp $< $(LOGS)/fmax
	@num=1 ; while [[ $$num -le $(FMAX_TEST) ]] ; do \
	  ( \
	    $(NEXTPNR) -l "$(LOGS)/fmax/$(OUTNAME)_$${num}_nextpnr.log" -q --timing-allow-fail $(NEXTPNR_ARGS) --$(DEVICE) --package $(PACKAGE) --json $< --pcf $(PIN_DEF) --asc $(LOGS)/fmax/$(OUTNAME)_$${num}.asc ; \
	    grep "Max frequency" $(LOGS)/fmax/$(OUTNAME)_$${num}_nextpnr.log | tail -1 | cut -d " " -f 2- ; \
	  ) & \
	  pids[$${num}]=$$! ; \
	  ((num = num + 1)) ; \
	  if ((num > ($(MAX_CPUS) - 1))) ; then \
	    if ((num % $(MAX_CPUS) == ($(MAX_CPUS) - 1))); then \
	      ((wnum = num - $(MAX_CPUS))) ; \
	      wait $${pid[wnum]} ; \
	    fi ; \
	  fi ; \
	done ; \
	wait
	@num=1 ; while [[ $$num -le $(FMAX_TEST) ]] ; do \
	  grep "Max frequency" $(LOGS)/fmax/$(OUTNAME)_$${num}_nextpnr.log | tail -1 | cut -d " " -f 7 >"$(LOGS)/fmax/fmax_temp.txt" ; \
	  FMAX=$$(cat "$(LOGS)/fmax/fmax_temp.txt") ; \
	  echo $${num} $${FMAX} "$(LOGS)/fmax/$(OUTNAME)_$${num}.asc" >> $(LOGS)/fmax/$(OUTNAME)_list.log ; \
	  ((num = num + 1)) ; \
	done
	@echo === fMAX after $(FMAX_TEST) runs: ===
	@awk '{ total += $$2 ; minv = (minv == 0 || minv > $$2 ? $$2 : minv) ; maxv = (maxv < $$2 ? $$2 : maxv) ; count++ } END \
	  { print "fMAX: Minimum frequency:", minv ; print "fMAX: Average frequency:", total/count ; print "fMAX: Maximum frequency:", maxv, "   <== selected as best" ; }' $(LOGS)/fmax/$(OUTNAME)_list.log
	@echo === fMAX after $(FMAX_TEST) runs: === > $(LOGS)/$(OUTNAME)_fmax.txt
	@awk '{ total += $$2 ; minv = (minv == 0 || minv > $$2 ? $$2 : minv) ; maxv = (maxv < $$2 ? $$2 : maxv) ; count++ } END \
	  { print "fMAX: Minimum frequency:", minv ; print "fMAX: Average frequency:", total/count ; print "fMAX: Maximum frequency:", maxv, "   <== selected as best" ; }' $(LOGS)/fmax/$(OUTNAME)_list.log >> $(LOGS)/$(OUTNAME)_fmax.txt
	@awk '{ if (maxv < $$2) { best = $$1 ; maxv = $$2 ; } ; } END { print best, maxv ; }' $(LOGS)/fmax/$(OUTNAME)_list.log  > "$(LOGS)/fmax/fmax_temp.txt"
	@BEST=$$(cut -d " " -f1 "$(LOGS)/fmax/fmax_temp.txt") FMAX=$$(cut -d " " -f2 "$(LOGS)/fmax/fmax_temp.txt") ; \
	  cp "$(LOGS)/fmax/$(OUTNAME)_$${BEST}_nextpnr.log" "$(LOGS)/$(OUTNAME)_nextpnr.log" ; \
	  cp "$(LOGS)/fmax/$(OUTNAME)_$${BEST}.asc" $@
	@rm "$(LOGS)/fmax/fmax_temp.txt"
else
ifdef NO_PNR_RETRY
	@echo NO_PNR_RETRY set, so failure IS an option...
	$(NEXTPNR) -l $(LOGS)/$(OUTNAME)_nextpnr.log -q $(NEXTPNR_ARGS) --$(DEVICE) --package $(PACKAGE) --json $< --pcf $(PIN_DEF) --asc $@
else
	@echo $(NEXTPNR) -l $(LOGS)/$(OUTNAME)_nextpnr.log -q $(NEXTPNR_ARGS) --$(DEVICE) --package $(PACKAGE) --json $< --pcf $(PIN_DEF) --asc $@
	@until $$($(NEXTPNR) -l $(LOGS)/$(OUTNAME)_nextpnr.log -q $(NEXTPNR_ARGS) --$(DEVICE) --package $(PACKAGE) --json $< --pcf $(PIN_DEF) --asc $@) ; do \
	  echo 'Retrying nextpnr-ice40 with new seed...' ; \
	done
endif
endif
	@echo === iCEBreaker Xosera: $(VIDEO_OUTPUT) $(VIDEO_MODE) $(SPI_INTERFACE) | tee $(OUTNAME)_stats.txt
	@-tabbyadm version | grep "Package" | tee -a $(OUTNAME)_stats.txt
	@$(YOSYS) -V 2>&1 | tee -a $(OUTNAME)_stats.txt
	@$(NEXTPNR) -V 2>&1 | tee -a $(OUTNAME)_stats.txt
	@sed -n '/Device utilisation/,/Info: Placed/p' $(LOGS)/$(OUTNAME)_nextpnr.log | sed '$$d' | grep -v ":     0/" | tee -a $(OUTNAME)_stats.txt
	@grep "Max frequency" $(LOGS)/$(OUTNAME)_nextpnr.log | tail -1 | tee -a $(OUTNAME)_stats.txt
	@-diff -U0 $(LOGS)/$(OUTNAME)_stats_last.txt $(OUTNAME)_stats.txt | grep -v "\(^@\|^+\|^---\)" | while read line; do echo "PREVIOUS: $$line" ; done >$(LOGS)/$(OUTNAME)_stats_delta.txt
	@-diff -U0 $(LOGS)/$(OUTNAME)_stats_last.txt $(OUTNAME)_stats.txt | grep -v "\(^@\|^+++\|^-\)" | while read line; do echo "CURRENT : $$line" ; done >>$(LOGS)/$(OUTNAME)_stats_delta.txt
	@echo
	@-cat $(LOGS)/$(OUTNAME)_stats_delta.txt

# make binary bitstream from ASCII bitstream
icebreaker/%_$(OUTSUFFIX).bin: icebreaker/%_$(OUTSUFFIX).asc icebreaker.mk
	@rm -f $@
	$(ICEPACK) $< $@
	$(ICEMULTI) -v -v -p0 icebreaker/*.bin -o $(TOP).bin

# make timing report from ASCII bitstream
icebreaker/%_$(OUTSUFFIX).rpt: icebreaker/%_$(OUTSUFFIX).asc icebreaker.mk
	@rm -f $@
	$(ICETIME) -d $(DEVICE) -m -t -r $@ $<

# delete all targets that will be re-generated
clean:
	rm -f xosera_iceb.bin $(wildcard icebreaker/*.json) $(wildcard icebreaker/*.asc) $(wildcard icebreaker/*.rpt) $(wildcard icebreaker/*.bin)

# prevent make from deleting any intermediate files
.SECONDARY:

# inform make about "phony" convenience targets
.PHONY: all prog timing count lint show clean
