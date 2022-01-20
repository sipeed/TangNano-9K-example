# PicoTiny Example Project

A PicoRV32-based SoC example with HDMI terminal from SimpleVout, SPI Flash XIP from picosoc, and custom UART ISP for flash programming.

## Project Structure

```text
\picotiny
- \fw
    - \fw-brom
        Project for BROM ISP flasher firmware
    - \fw-flash
        Project for user firmware
- \sw
    Tools for BROM building and ISP flashing
- \hw
    RTL sources for the PicoTiny system
- \project
    Gowin FPGA project file and constraints
- \gowin_ip
    IP cores for the FPGA project
- \sim
    Testbench and helper modules
```

## Hardware

### Module Config

- PicoRV32

    Base RV32I config, SP set through crt.S

- spimemio

    Added DSPI recovery and extra delay cycles for $t_{RES1} of Winbond, GigaDevice, and Puya SPI flash. QSPI function disabled as TangNano-9K only supports DSPI operation.

- SimpleVOut

    Configured for 640x480@60 HDMI output with Gowin OSER and ELVDS macro. The module sends a terminal with testcard as the background. Characters sent from PicoRV32 to the UART will also be displayed on the terminal.

### Address Mapping

- 0x00000000 - 0x007FFFFF 8MiB SPI Flash XIP
- 0x40000000 - 0x40001FFF 8KiB SRAM
- 0x80000000 - 0x8FFFFFFF PicoPeripherals
  - 0x80000000 - 0x80001FFF 8KiB BROM
  - 0x81000000 - 0x8100000F SPI Flash Config / Bitbang IO
  - 0x82000000 - 0x8200000F GPIO
  - 0x83000000 - 0x8300000F UART
- 0xC0000000 - 0xFFFFFFFF Reserved for custom peripherals

## Firmware

### Dependencies

- python >= 3.6

    Set $PYTHON_NAME to python executive if the desired python is not in the $PATH
- pyserial
- RISC-V GCC

    Set $RISCV_NAME to GCC prefix and $RISCV_PATH to GCC root folder

The variables above could be configured by setting environment variables or modifying Makefile.

### Firmware Build

- Build BROM ISP Flasher image

    ```bash
    make brom
    ```

- Build user firmware image

    ```bash
    make flash
    ```

### Firmware ISP Program

The ISP firmware will wait for ISP command for <1s, then jump to main program if ISP command received. Thus, the programming sequence requires manually pressing and releasing the reset button (**S1**) after prompted by the flasher.

- Program user firmware image through ISP

    ```bash
    make program COMx=<UART port>
    ```

- Program custom firmware image through ISP

    ```bash
    make program PROG_FILE=<objdump Verilog file> COMx=<UART port>
    ```

### Example Firmware

The firmware has a UART terminal on the integrated USB-UART with baudrate `115200`. Terminal output will be send to both the UART and the HDMI terminal. The terminal contains LED toggling, flash mode configuration, and a simple benchmark from the original picosoc.
