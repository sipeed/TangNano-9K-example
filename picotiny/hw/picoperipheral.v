`timescale 1ns/1ps

module Reset_Sync (
 input clk,
 input ext_reset,
 output resetn
);

 reg [3:0] reset_cnt = 0;
 
 always @(posedge clk or negedge ext_reset) begin
     if (~ext_reset)
         reset_cnt <= 4'b0;
     else
         reset_cnt <= reset_cnt + !resetn;
 end
 
 assign resetn = &reset_cnt;

endmodule

module PicoMem_UART (
 input clk,
 input resetn,
 input ser_rx,
 input mem_s_valid,
 input [31:0] mem_s_addr,
 input [31:0] mem_s_wdata,
 input [3:0] mem_s_wstrb,
 output ser_tx,
 output mem_s_ready,
 output [31:0] mem_s_rdata
);

 wire [31:0] reg_dat_do;
 wire [31:0] reg_div_do;
 
 assign mem_s_rdata = mem_s_addr[2] ?
                      reg_div_do :
                      reg_dat_do;
 
 wire reg_dat_sel = mem_s_valid && ~mem_s_addr[2];
 wire reg_div_sel = mem_s_valid && mem_s_addr[2];
 
 wire reg_dat_wait;
 
 assign mem_s_ready = reg_div_sel || (reg_dat_sel && ~reg_dat_wait);
 
 simpleuart u_simpleuart (
   .clk(clk),
   .resetn(resetn),
   .ser_tx(ser_tx),
   .ser_rx(ser_rx),
   .reg_div_we({4{reg_div_sel}} & mem_s_wstrb),
   .reg_div_di(mem_s_wdata),
   .reg_div_do(reg_div_do),
   .reg_dat_we(reg_dat_sel & mem_s_wstrb[0]),
   .reg_dat_re(reg_dat_sel & ~(|mem_s_wstrb)),
   .reg_dat_di(mem_s_wdata),
   .reg_dat_do(reg_dat_do),
   .reg_dat_wait(reg_dat_wait)
 );

endmodule

module PicoMem_GPIO (
 input clk,
 input resetn,
 input busin_valid,
 input [31:0] busin_addr,
 input [31:0] busin_wdata,
 input [3:0] busin_wstrb,
 output busin_ready,
 output [31:0] busin_rdata,
 inout [31:0] io
);
 reg [31:0] out_r;
 reg [31:0] oe_r;
 reg [31:0] rdata_r;
 reg ready_r;
 
    always @(posedge clk) begin
        if (!resetn) begin
            ready_r <= 1'b0;
            out_r <= 32'b0;
            oe_r <= 32'b0;
        end else begin
            ready_r <= 1'b0;
            if (busin_valid && !ready_r) begin
                ready_r <= 1'b1;
                case(busin_addr[3:2])
                2'b00: begin
                    if (busin_wstrb[3]) out_r[31:24] <= busin_wdata[31:24];
                    if (busin_wstrb[2]) out_r[24:16] <= busin_wdata[24:16];
                    if (busin_wstrb[1]) out_r[15: 8] <= busin_wdata[15: 8];
                    if (busin_wstrb[0]) out_r[ 7: 0] <= busin_wdata[ 7: 0];
                    // Read and write won't happen at same transaction so no issue on late updating
                    rdata_r <= out_r;
                end
                2'b01: begin
                    rdata_r <= io;
                end
                2'b10: begin
                    if (busin_wstrb[3]) oe_r[31:24] <= busin_wdata[31:24];
                    if (busin_wstrb[2]) oe_r[24:16] <= busin_wdata[24:16];
                    if (busin_wstrb[1]) oe_r[15: 8] <= busin_wdata[15: 8];
                    if (busin_wstrb[0]) oe_r[ 7: 0] <= busin_wdata[ 7: 0];
                    // Read and write won't happen at same transaction so no issue on late updating
                    rdata_r <= oe_r;
                end
                default: rdata_r <= 32'hDEADBEEF;
                endcase
            end
        end
    end
 
 assign busin_ready = ready_r;
 assign busin_rdata = rdata_r;
 
 genvar i;
 generate
     for (i = 0; i < 32; i = i + 1) begin
         assign io[i] = oe_r[i] ? out_r[i] : 1'bz;
     end
 endgenerate
 
endmodule

module PicoMem_SPI_Flash (
 input clk,
 input resetn,
 input flash_mem_valid,
 input [31:0] flash_mem_addr,
 input [31:0] flash_mem_wdata,
 input [3:0] flash_mem_wstrb,
 input flash_cfg_valid,
 input [31:0] flash_cfg_addr,
 input [31:0] flash_cfg_wdata,
 input [3:0] flash_cfg_wstrb,
 output flash_mem_ready,
 output [31:0] flash_mem_rdata,
 output flash_cfg_ready,
 output [31:0] flash_cfg_rdata,
 output flash_clk,
 output flash_csb,
 inout  flash_mosi,
 inout  flash_miso
);

wire flash_io0_oe;
wire flash_io0_di;
wire flash_io0_do;
wire flash_io1_oe;
wire flash_io1_di;
wire flash_io1_do;

 spimemio_puya u_spimemio (
     .clk(clk),
     .resetn(resetn),

     .valid(flash_mem_valid),
     .ready(flash_mem_ready),
     .addr(flash_mem_addr[23:0]),
     .rdata(flash_mem_rdata),

     .cfgreg_we( {4{flash_cfg_valid}} & flash_cfg_wstrb ),
     .cfgreg_di(flash_cfg_wdata),
     .cfgreg_do(flash_cfg_rdata),
	 
	 .flash_clk(flash_clk),
	 .flash_csb(flash_csb),

     .flash_io0_oe(flash_io0_oe),
     .flash_io0_di(flash_io0_di),
     .flash_io0_do(flash_io0_do),

     .flash_io1_oe(flash_io1_oe),
     .flash_io1_di(flash_io1_di),
     .flash_io1_do(flash_io1_do)
 );
 assign flash_cfg_ready = flash_cfg_valid;

 assign flash_mosi = flash_io0_oe ? flash_io0_do : 1'bz;
 assign flash_io0_di = flash_mosi;
 assign flash_miso = flash_io1_oe ? flash_io1_do : 1'bz;
 assign flash_io1_di = flash_miso;

endmodule


module PicoMem_Mux_1_4 #(
 parameter PICOS0_ADDR_BASE = 32'h0000_0000,
 parameter PICOS0_ADDR_MASK = 32'hC000_0000,
 parameter PICOS1_ADDR_BASE = 32'h4000_0000,
 parameter PICOS1_ADDR_MASK = 32'hC000_0000,
 parameter PICOS2_ADDR_BASE = 32'h8000_0000,
 parameter PICOS2_ADDR_MASK = 32'hC000_0000,
 parameter PICOS3_ADDR_BASE = 32'hC000_0000,
 parameter PICOS3_ADDR_MASK = 32'hC000_0000
) (
 input picos0_ready,
 input [31:0] picos0_rdata,
 input picos1_ready,
 input [31:0] picos1_rdata,
 input picom_valid,
 input [31:0] picom_addr,
 input [31:0] picom_wdata,
 input [3:0] picom_wstrb,
 input picos2_ready,
 input [31:0] picos2_rdata,
 input picos3_ready,
 input [31:0] picos3_rdata,
 output picos0_valid,
 output [31:0] picos0_addr,
 output [31:0] picos0_wdata,
 output [3:0] picos0_wstrb,
 output picos1_valid,
 output [31:0] picos1_addr,
 output [31:0] picos1_wdata,
 output [3:0] picos1_wstrb,
 output picom_ready,
 output [31:0] picom_rdata,
 output picos2_valid,
 output [31:0] picos2_addr,
 output [31:0] picos2_wdata,
 output [3:0] picos2_wstrb,
 output picos3_valid,
 output [31:0] picos3_addr,
 output [31:0] picos3_wdata,
 output [3:0] picos3_wstrb
);
 wire picos0_match = ~|((picom_addr ^ PICOS0_ADDR_BASE) & PICOS0_ADDR_MASK);
 wire picos1_match = ~|((picom_addr ^ PICOS1_ADDR_BASE) & PICOS1_ADDR_MASK);
 wire picos2_match = ~|((picom_addr ^ PICOS2_ADDR_BASE) & PICOS2_ADDR_MASK);
 wire picos3_match = ~|((picom_addr ^ PICOS3_ADDR_BASE) & PICOS3_ADDR_MASK);
 
 wire picos0_sel = picos0_match;
 wire picos1_sel = picos1_match & (~picos0_match);
 wire picos2_sel = picos2_match & (~picos0_match) & (~picos1_match);
 wire picos3_sel = picos3_match & (~picos0_match) & (~picos1_match) & (~picos2_match);
 
 // master
 assign picom_rdata = picos0_sel ? picos0_rdata :
                      picos1_sel ? picos1_rdata :
                      picos2_sel ? picos2_rdata :
                      picos3_sel ? picos3_rdata :
                      32'b0;
 
 assign picom_ready = picos0_sel ? picos0_ready :
                      picos1_sel ? picos1_ready :
                      picos2_sel ? picos2_ready :
                      picos3_sel ? picos3_ready :
                      1'b0;
 
 // slave 0
 assign picos0_valid = picom_valid & picos0_sel;
 assign picos0_addr = picom_addr;
 assign picos0_wdata = picom_wdata;
 assign picos0_wstrb = picom_wstrb;
 
 // slave 1
 assign picos1_valid = picom_valid & picos1_sel;
 assign picos1_addr = picom_addr;
 assign picos1_wdata = picom_wdata;
 assign picos1_wstrb = picom_wstrb;
 
 // slave 2
 assign picos2_valid = picom_valid & picos2_sel;
 assign picos2_addr = picom_addr;
 assign picos2_wdata = picom_wdata;
 assign picos2_wstrb = picom_wstrb;
 
 // slave 3
 assign picos3_valid = picom_valid & picos3_sel;
 assign picos3_addr = picom_addr;
 assign picos3_wdata = picom_wdata;
 assign picos3_wstrb = picom_wstrb;
endmodule
