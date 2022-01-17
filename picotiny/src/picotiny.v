`timescale 1ns/1ps

module picotiny (
 input clk,
 input resetn,

 input  ser_rx,
 output ser_tx,
 inout [31:0] gpio
);
 wire sys_resetn;
 wire w4;
 wire w7;
 wire w8;
 wire w9;
 wire w10;
 wire w11;
 wire w12;
 wire mem_valid;
 wire mem_ready;
 wire [31:0] mem_addr;
 wire [31:0] mem_wdata;
 wire [3:0] mem_wstrb;
 wire [31:0] mem_rdata;
 wire w19;
 wire w20;
 wire [31:0] w21;
 wire [31:0] w22;
 wire [3:0] w23;
 wire [31:0] w24;
 wire w25;
 wire w26;
 wire [31:0] w27;
 wire [31:0] w28;
 wire [3:0] w29;
 wire [31:0] w30;
 wire w31;
 wire w32;
 wire [31:0] w33;
 wire [31:0] w34;
 wire [3:0] w35;
 wire [31:0] w36;
 wire w37;
 wire w38;
 wire [31:0] w39;
 wire [31:0] w40;
 wire [3:0] w41;
 wire [31:0] w42;
 
picorv32 u_picorv32 (
   .clk(clk),
   .resetn(resetn),
   .trap(),
   .mem_valid(mem_valid),
   .mem_instr(),
   .mem_ready(mem_ready),
   .mem_addr(mem_addr),
   .mem_wdata(mem_wdata),
   .mem_wstrb(mem_wstrb),
   .mem_rdata(mem_rdata),
   .irq(32'b0),
   .eoi()
 );

 Reset_Sync u_Reset_Sync (
  .resetn(sys_resetn),
  .ext_reset(resetn),
  .clk(clk)
 );
 
 PicoMem_UART u_PicoMem_UART (
  .resetn(sys_resetn),
  .clk(clk),
  .mem_s_valid(w31),
  .mem_s_ready(w32),
  .mem_s_addr(w33),
  .mem_s_wdata(w34),
  .mem_s_wstrb(w35),
  .mem_s_rdata(w36),
  .ser_rx(ser_rx),
  .ser_tx(ser_tx)
 );

 PicoMem_GPIO u_PicoMem_GPIO (
  .resetn(sys_resetn),
  .io(gpio),
  .clk(clk),
  .busin_valid(w25),
  .busin_ready(w26),
  .busin_addr(w27),
  .busin_wdata(w28),
  .busin_wstrb(w29),
  .busin_rdata(w30)
 );
 
 PicoMem_SRAM_EG4_4KB u_PicoMem_SRAM_EG4_4KB_6 (
  .resetn(sys_resetn),
  .clk(clk),
  .mem_s_valid(w37),
  .mem_s_ready(w38),
  .mem_s_addr(w39),
  .mem_s_wdata(w40),
  .mem_s_wstrb(w41),
  .mem_s_rdata(w42)
 );

 PicoMem_SRAM_EG4_16KB u_PicoMem_SRAM_EG4_16KB_7 (
  .resetn(sys_resetn),
  .clk(clk),
  .mem_s_valid(w19),
  .mem_s_ready(w20),
  .mem_s_addr(w21),
  .mem_s_wdata(w22),
  .mem_s_wstrb(w23),
  .mem_s_rdata(w24)
 );
 
 PicoMem_Mux_1_4 u_PicoMem_Mux_1_4_8 (
  .picom_valid(mem_valid),
  .picom_ready(mem_ready),
  .picom_addr(mem_addr),
  .picom_wdata(mem_wdata),
  .picom_wstrb(mem_wstrb),
  .picom_rdata(mem_rdata),
  .picos1_valid(w19),
  .picos1_ready(w20),
  .picos1_addr(w21),
  .picos1_wdata(w22),
  .picos1_wstrb(w23),
  .picos1_rdata(w24),
  .picos2_valid(w25),
  .picos2_ready(w26),
  .picos2_addr(w27),
  .picos2_wdata(w28),
  .picos2_wstrb(w29),
  .picos2_rdata(w30),
  .picos3_valid(w31),
  .picos3_ready(w32),
  .picos3_addr(w33),
  .picos3_wdata(w34),
  .picos3_wstrb(w35),
  .picos3_rdata(w36),
  .picos0_valid(w37),
  .picos0_ready(w38),
  .picos0_addr(w39),
  .picos0_wdata(w40),
  .picos0_wstrb(w41),
  .picos0_rdata(w42)
 );
 
endmodule
