
PYTHON_NAME ?= python
RISCV_NAME 	?= riscv-none-embed
RISCV_PATH 	?= D:/gnu-mcu-eclipse-riscv-none-gcc-8.2.0
MAKE		?= make

FW_FILE 	 = fw/fw-flash/build/fw-flash.v

PROG_FILE	?= $(FW_FILE)
COMx	 	?= COM14

export PYTHON_NAME
export RISCV_NAME
export RISCV_PATH


.PHONY: all brom flash clean program

all: brom flash

$(FW_FILE): flash

brom:
	$(MAKE) -C fw/fw-brom

flash:
	$(MAKE) -C fw/fw-flash

clean:
	$(MAKE) -C fw/fw-brom clean
	$(MAKE) -C fw/fw-flash clean

program: $(PROG_FILE)
	$(PYTHON_NAME) sw/pico-programmer.py $(PROG_FILE) $(COMx)
