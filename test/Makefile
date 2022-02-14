.PHONY: all clean


export TOP := $(shell git rev-parse --show-toplevel)

export TEST_DIR     := $(TOP)/test
export SRC_DIR      := $(TOP)/rtl/asic/work
export BASEJUMP_DIR := $(TOP)/import/basejump_stl


all: flist.vcs
	vcs -full64 -f flist.vcs -sverilog -assert svaext +define+TARGET_FPGA +incdir+$(BASEJUMP_SRC)/bsg_misc/
flist.vcs:
	cat flist.template | envsubst > $@
test:
	./simv && diff tx.txt rx.txt
clean:
	rm -rf csrc simv simv.daidir dump.vcd flist.vcs ucli.key tx.txt rx.txt vc_hdrs.h
