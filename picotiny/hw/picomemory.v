`timescale 1ns/1ps

`define __GOWIN__

module PicoMem_2kx8_SRAM_behav (
	input clk,
	input reset,
	inout ce,
	input oce,
	input wre,
	input [10:0] ad,
	input [7:0] din,
	output [7:0] dout
);

reg [7:0] mem [2047:0];
reg [7:0] mem_out;

always @(posedge clk) begin
    if (ce) begin
        if (wre) begin
			mem[ad] <= din;
		end
		mem_out <= mem[ad];
    end
end

assign dout = mem_out;

endmodule

module PicoMem_BOOT_SRAM_8KB (
 input clk,
 input resetn,
 input mem_s_valid,
 input [31:0] mem_s_addr,
 input [31:0] mem_s_wdata,
 input [3:0] mem_s_wstrb,
 output mem_s_ready,
 output [31:0] mem_s_rdata
);

reg mem_ready;
wire mem_ce;

assign mem_ce = mem_s_valid & ~mem_s_ready;

`ifdef __GOWIN__
bootram_2kx8_3 u_sram_3 (
`else
PicoMem_2kx8_SRAM_behav u_sram_3 (
`endif
	.clk(clk),
	.reset(~resetn),
	.ce(mem_ce),
	.oce(1'b1),
	.wre(mem_s_wstrb[3]),
	.ad(mem_s_addr[12:2]),
	.din(mem_s_wdata[31:24]),
	.dout(mem_s_rdata[31:24])
);
`ifdef __GOWIN__
bootram_2kx8_2 u_sram_2 (
`else
PicoMem_2kx8_SRAM_behav u_sram_2 (
`endif
	.clk(clk),
	.reset(~resetn),
	.ce(mem_ce),
	.oce(1'b1),
	.wre(mem_s_wstrb[2]),
	.ad(mem_s_addr[12:2]),
	.din(mem_s_wdata[23:16]),
	.dout(mem_s_rdata[23:16])
);
`ifdef __GOWIN__
bootram_2kx8_1 u_sram_1 (
`else
PicoMem_2kx8_SRAM_behav u_sram_1 (
`endif
	.clk(clk),
	.reset(~resetn),
	.ce(mem_ce),
	.oce(1'b1),
	.wre(mem_s_wstrb[1]),
	.ad(mem_s_addr[12:2]),
	.din(mem_s_wdata[15: 8]),
	.dout(mem_s_rdata[15: 8])
);
`ifdef __GOWIN__
bootram_2kx8_0 u_sram_0 (
`else
PicoMem_2kx8_SRAM_behav u_sram_0 (
`endif
	.clk(clk),
	.reset(~resetn),
	.ce(mem_ce),
	.oce(1'b1),
	.wre(mem_s_wstrb[0]),
	.ad(mem_s_addr[12:2]),
	.din(mem_s_wdata[ 7: 0]),
	.dout(mem_s_rdata[ 7: 0])
);

always @(posedge clk) begin
    if (~resetn) begin
        mem_ready <= 1'b0;
    end else begin
        if (mem_ready) begin
            mem_ready <= 1'b0;
        end else if (mem_s_valid) begin
            mem_ready <= 1'b1;
        end
    end
end

assign mem_s_ready = mem_ready;

endmodule


module PicoMem_SRAM_8KB (
 input clk,
 input resetn,
 input mem_s_valid,
 input [31:0] mem_s_addr,
 input [31:0] mem_s_wdata,
 input [3:0] mem_s_wstrb,
 output mem_s_ready,
 output [31:0] mem_s_rdata
);

reg mem_ready;
wire mem_ce;

assign mem_ce = mem_s_valid & ~mem_s_ready;

`ifdef __GOWIN__
sram_2kx8 u_sram_3 (
`else
PicoMem_2kx8_SRAM_behav u_sram_3 (
`endif
	.clk(clk),
	.reset(~resetn),
	.ce(mem_ce),
	.oce(1'b1),
	.wre(mem_s_wstrb[3]),
	.ad(mem_s_addr[12:2]),
	.din(mem_s_wdata[31:24]),
	.dout(mem_s_rdata[31:24])
);
`ifdef __GOWIN__
sram_2kx8 u_sram_2 (
`else
PicoMem_2kx8_SRAM_behav u_sram_2 (
`endif
	.clk(clk),
	.reset(~resetn),
	.ce(mem_ce),
	.oce(1'b1),
	.wre(mem_s_wstrb[2]),
	.ad(mem_s_addr[12:2]),
	.din(mem_s_wdata[23:16]),
	.dout(mem_s_rdata[23:16])
);
`ifdef __GOWIN__
sram_2kx8 u_sram_1 (
`else
PicoMem_2kx8_SRAM_behav u_sram_1 (
`endif
	.clk(clk),
	.reset(~resetn),
	.ce(mem_ce),
	.oce(1'b1),
	.wre(mem_s_wstrb[1]),
	.ad(mem_s_addr[12:2]),
	.din(mem_s_wdata[15: 8]),
	.dout(mem_s_rdata[15: 8])
);
`ifdef __GOWIN__
sram_2kx8 u_sram_0 (
`else
PicoMem_2kx8_SRAM_behav u_sram_0 (
`endif
	.clk(clk),
	.reset(~resetn),
	.ce(mem_ce),
	.oce(1'b1),
	.wre(mem_s_wstrb[0]),
	.ad(mem_s_addr[12:2]),
	.din(mem_s_wdata[ 7: 0]),
	.dout(mem_s_rdata[ 7: 0])
);

always @(posedge clk) begin
    if (~resetn) begin
        mem_ready <= 1'b0;
    end else begin
        if (mem_ready) begin
            mem_ready <= 1'b0;
        end else if (mem_s_valid) begin
            mem_ready <= 1'b1;
        end
    end
end

assign mem_s_ready = mem_ready;

endmodule
