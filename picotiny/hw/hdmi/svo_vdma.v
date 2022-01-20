/*
 *  SVO - Simple Video Out FPGA Core
 *
 *  Copyright (C) 2014  Clifford Wolf <clifford@clifford.at>
 *  
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *  
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

`timescale 1ns / 1ps
`include "svo_defines.vh"

module svo_vdma #(
	`SVO_DEFAULT_PARAMS,
	parameter MEM_ADDR_WIDTH = 32,
	parameter MEM_DATA_WIDTH = 64,
	parameter MEM_BURST_LEN = 8,
	parameter FIFO_DEPTH = 64
) (
	// All signal are synchronous to "clk", except out_axis_* which are synchronous to "oclk".

	input clk, oclk, resetn,
	output reg frame_irq,

	// config interface: axi4-lite slave
	//
	//    ADDR |31     24|23     16|15      8|7       0| 
	//   ------+---------+---------+---------+---------+----
	//    0x00 |    frame start addr (0 = inactive)    | RW
	//   ------+---------+---------+---------+---------+----
	//    0x04 |        active frame start addr        | RO
	//   ------+---------+---------+---------+---------+----
	//    0x08 |    y-resolution   |    x-resolution   | RO
	//   ------+---------+---------+---------+---------+----
	//    0x0C |       unused (always 0)     | OutChar | WO
	//   ------+---------+---------+---------+---------+----
	// 
	input             cfg_axi_awvalid,
	output            cfg_axi_awready,
	input      [ 7:0] cfg_axi_awaddr,

	input             cfg_axi_wvalid,
	output            cfg_axi_wready,
	input      [31:0] cfg_axi_wdata,

	output reg        cfg_axi_bvalid,
	input             cfg_axi_bready,

	input             cfg_axi_arvalid,
	output            cfg_axi_arready,
	input      [ 7:0] cfg_axi_araddr,

	output reg        cfg_axi_rvalid,
	input             cfg_axi_rready,
	output reg [31:0] cfg_axi_rdata,

	// memory interface: axi4 read-only master
	//
	output reg [MEM_ADDR_WIDTH-1:0] mem_axi_araddr,
	output     [               7:0] mem_axi_arlen,
	output     [               2:0] mem_axi_arsize,
	output     [               2:0] mem_axi_arprot,
	output     [               1:0] mem_axi_arburst,
	output reg                      mem_axi_arvalid,
	input                           mem_axi_arready,

	input      [MEM_DATA_WIDTH-1:0] mem_axi_rdata,
	input                           mem_axi_rvalid,
	output reg                      mem_axi_rready,

	// output stream
	//   tuser[0] ... start of frame
	//
	output                          out_axis_tvalid,
	input                           out_axis_tready,
	output [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
	output [                   0:0] out_axis_tuser,

	// terminal output stream
	// (optional interface to svo_term)
	//
	output reg       term_axis_tvalid,
	input            term_axis_tready,
	output reg [7:0] term_axis_tdata

);
	`SVO_DECLS

	localparam BYTES_PER_PIXEL = (SVO_BITS_PER_PIXEL + 7) / 8;
	localparam BYTES_PER_BURST = MEM_BURST_LEN * MEM_DATA_WIDTH / 8;

	localparam NUM_PIXELS = SVO_HOR_PIXELS * SVO_VER_PIXELS;
	localparam NUM_PIXELS_WIDTH = svo_clog2(NUM_PIXELS);
	
	localparam NUM_BURSTS = (NUM_PIXELS * BYTES_PER_PIXEL + BYTES_PER_BURST - 1) / BYTES_PER_BURST;
	localparam NUM_BURSTS_WIDTH = svo_clog2(NUM_BURSTS);
	
	localparam NUM_WORDS = MEM_BURST_LEN * NUM_BURSTS;
	localparam NUM_WORDS_WIDTH = svo_clog2(NUM_WORDS);

	localparam FIFO_ABITS = svo_clog2(FIFO_DEPTH);


	// iresetn is used in AR logic to make sure that we do not issue mem read requests
	// before the clock domain crossing fifo has been fully reset.

	reg [3:0] oresetn_q, iresetn_q;
	reg oresetn, iresetn;

	// synchronize oresetn with oclk
	always @(posedge oclk)
		{oresetn, oresetn_q} <= {oresetn_q, resetn};

	// synchronize iresetn with clk
	always @(posedge clk)
		{iresetn, iresetn_q} <= {iresetn_q, oresetn};


	// --------------------------------------------------------------
	// Configuration Interface
	// --------------------------------------------------------------

	reg [31:0] reg_startaddr;
	reg [31:0] reg_activeframe;
	wire [31:0] reg_resolution;

	assign reg_resolution[31:16] = SVO_VER_PIXELS, reg_resolution[15:0] = SVO_HOR_PIXELS;

	assign {cfg_axi_awready, cfg_axi_wready} = {2{resetn && cfg_axi_awvalid && cfg_axi_wvalid && (!cfg_axi_bvalid || cfg_axi_bready) && !term_axis_tvalid}};
	assign cfg_axi_arready = resetn && cfg_axi_arvalid && (!cfg_axi_rvalid || cfg_axi_rready);

	always @(posedge clk) begin
		if (!resetn) begin
			reg_startaddr <= 0;
			cfg_axi_bvalid <= 0;
			cfg_axi_rvalid <= 0;
			term_axis_tvalid <= 0;
		end else begin
			if (cfg_axi_bready)
				cfg_axi_bvalid <= 0;

			if (cfg_axi_rready)
				cfg_axi_rvalid <= 0;

			if (term_axis_tready)
				term_axis_tvalid <= 0;

			if (cfg_axi_awready) begin
				cfg_axi_bvalid <= 1;
				case (cfg_axi_awaddr)
					8'h00: reg_startaddr <= cfg_axi_wdata;
					8'h0C: begin
						term_axis_tvalid <= 1;
						term_axis_tdata <= cfg_axi_wdata;
					end
				endcase
			end

			if (cfg_axi_arready) begin
				cfg_axi_rvalid <= 1;
				case (cfg_axi_araddr)
					8'h00: cfg_axi_rdata <= reg_startaddr;
					8'h04: cfg_axi_rdata <= reg_activeframe;
					8'h08: cfg_axi_rdata <= reg_resolution;
					default: cfg_axi_rdata <= 'bx;
				endcase
			end
		end
	end


	// --------------------------------------------------------------
	// Memory AR channel
	// --------------------------------------------------------------

	reg [NUM_BURSTS_WIDTH-1:0] ar_burst_count;
	reg [3:0] ar_burst_delay;
	reg ar_flow_ctrl;

	assign mem_axi_arlen = MEM_BURST_LEN-1;
	assign mem_axi_arsize = svo_clog2(MEM_DATA_WIDTH/8);
	assign mem_axi_arprot = 0;
	assign mem_axi_arburst = 1;

	always @(posedge clk) begin
		frame_irq <= 0;
		if (ar_burst_delay)
			ar_burst_delay <= ar_burst_delay-1;
		if (!iresetn || !resetn) begin
			ar_burst_delay <= 0;
			ar_burst_count <= 0;
			mem_axi_araddr <= 0;
			mem_axi_arvalid <= 0;
			reg_activeframe <= 0;
		end else begin
			if (mem_axi_araddr == 0) begin
				mem_axi_araddr <= reg_startaddr;
				reg_activeframe <= reg_startaddr;
			end else
			if (mem_axi_arready && mem_axi_arvalid) begin
				mem_axi_arvalid <= 0;
				ar_burst_delay <= 6;
			end else
			if (ar_flow_ctrl && !mem_axi_arvalid && !ar_burst_delay) begin
				mem_axi_arvalid <= 1;

				if (ar_burst_count == NUM_BURSTS-1)
					ar_burst_count <= 0;
				else
					ar_burst_count <= ar_burst_count + 1;

				if (ar_burst_count == 0) begin
					mem_axi_araddr <= reg_startaddr;
					reg_activeframe <= reg_startaddr;
					if (!reg_startaddr) begin
						ar_burst_count <= 0;
						mem_axi_arvalid <= 0;
					end else
						frame_irq <= 1;
				end else begin
					mem_axi_araddr <= mem_axi_araddr + (MEM_BURST_LEN*MEM_DATA_WIDTH/8);
				end
			end
		end
	end


	// --------------------------------------------------------------
	// Memory R channel and flow control
	// --------------------------------------------------------------

	reg [NUM_WORDS_WIDTH-1:0] r_word_count;
	reg [FIFO_ABITS:0] requested_words;

	reg fifo_out_en;
	wire fifo_out_first_word;
	wire [MEM_DATA_WIDTH-1:0] fifo_out_data;
	wire [FIFO_ABITS-1:0] fifo_in_free;
	wire [FIFO_ABITS-1:0] fifo_out_avail;

	svo_vdma_crossclock_fifo #(
		.WIDTH(MEM_DATA_WIDTH+1),
		.DEPTH(FIFO_DEPTH),
		.ABITS(FIFO_ABITS)
	) fifo (
		.in_clk(clk),
		.in_resetn(resetn),
		.in_enable(mem_axi_rvalid && mem_axi_rready),
		.in_data({r_word_count == 0, mem_axi_rdata}),
		.in_free(fifo_in_free),

		.out_clk(oclk),
		.out_resetn(oresetn),
		.out_enable(fifo_out_en),
		.out_data({fifo_out_first_word, fifo_out_data}),
		.out_avail(fifo_out_avail)
	);

	always @(posedge clk) begin
		if (!resetn) begin
			requested_words = 0;
			mem_axi_rready <= 0;
			r_word_count <= 0;
			ar_flow_ctrl <= 0;
		end else begin
			if (mem_axi_arvalid && mem_axi_arready) begin
				requested_words = requested_words + MEM_BURST_LEN;
			end
			if (mem_axi_rvalid && mem_axi_rready) begin
				requested_words = requested_words - 1;
				r_word_count <= r_word_count == NUM_WORDS-1 ? 0 : r_word_count + 1;
			end

			ar_flow_ctrl <= requested_words + MEM_BURST_LEN + 4 < fifo_in_free;
			mem_axi_rready <= fifo_in_free > 4;
		end
	end


	// --------------------------------------------------------------
	// Output stream
	// --------------------------------------------------------------

	reg [MEM_DATA_WIDTH + 8*BYTES_PER_PIXEL - 9 : 0] outbuf;
	reg [7:0] outbuf_bytes;
	reg outbuf_framestart;

	wire pixel_rd;
	reg [NUM_PIXELS_WIDTH:0] pixel_count;
	reg [SVO_BITS_PER_PIXEL-1:0] pixel_data;

	integer i;

	always @(posedge oclk) begin
		fifo_out_en <= 0;
		if (!oresetn) begin
			outbuf_bytes = 0;
			pixel_count <= NUM_PIXELS;
		end else begin
			outbuf = outbuf;
			outbuf_bytes = outbuf_bytes;

			if (fifo_out_avail && outbuf_bytes < BYTES_PER_PIXEL && (!fifo_out_first_word || pixel_count >= NUM_PIXELS-1)) begin
				for (i = 0; i < BYTES_PER_PIXEL; i = i+1)
					if (outbuf_bytes == i || (!i && fifo_out_first_word)) begin
						outbuf = (fifo_out_data << (8*i)) | (outbuf & ~(~0 << (8*i)));
						outbuf_bytes = MEM_DATA_WIDTH/8 + i;
						fifo_out_en <= 1;
					end
				outbuf_framestart = fifo_out_first_word;
			end

			if (pixel_rd) begin
				pixel_data <= outbuf;
				if (outbuf_framestart || pixel_count > ((NUM_WORDS*(MEM_DATA_WIDTH/8) + BYTES_PER_PIXEL - 1) / BYTES_PER_PIXEL)) begin
					pixel_count <= 0;
				end else
					pixel_count <= pixel_count + 1;
				outbuf_bytes = outbuf_bytes < BYTES_PER_PIXEL ?
						0 : outbuf_bytes - BYTES_PER_PIXEL;
				outbuf = outbuf >> (8*BYTES_PER_PIXEL);
				outbuf_framestart = 0;
			end
		end
	end

	assign pixel_rd = out_axis_tready;
	assign out_axis_tvalid = pixel_count < NUM_PIXELS;
	assign out_axis_tdata = pixel_data;
	assign out_axis_tuser = !pixel_count;
endmodule


module svo_vdma_crossclock_fifo #(
	parameter WIDTH = 8,
	parameter DEPTH = 12,
	parameter ABITS = 4
) (
	input                  in_clk,
	input                  in_resetn,
	input                  in_enable,
	input      [WIDTH-1:0] in_data,
	output reg [ABITS-1:0] in_free,

	input                  out_clk,
	input                  out_resetn,
	input                  out_enable,
	output reg [WIDTH-1:0] out_data,
	output reg [ABITS-1:0] out_avail
);
	reg [WIDTH-1:0] fifo [0:DEPTH-1];
	reg [ABITS-1:0] in_ptr, in_ptr_gray;
	reg [ABITS-1:0] out_ptr, out_ptr_gray;

	reg [ABITS-1:0] out_ptr_for_in_clk, in_ptr_for_out_clk;
	reg [ABITS-1:0] sync_in_ptr_0, sync_out_ptr_0;
	reg [ABITS-1:0] sync_in_ptr_1, sync_out_ptr_1;
	reg [ABITS-1:0] sync_in_ptr_2, sync_out_ptr_2;

	function [ABITS-1:0] bin2gray(input [ABITS-1:0] in);
		integer i;
		reg [ABITS:0] temp;
		begin
			temp = in;
			for (i=0; i<ABITS; i=i+1)
				bin2gray[i] = ^temp[i +: 2];
		end
	endfunction

	function [ABITS-1:0] gray2bin(input [ABITS-1:0] in);
		integer i;
		begin
			for (i=0; i<ABITS; i=i+1)
				gray2bin[i] = ^(in >> i);
		end
	endfunction

	always @(posedge in_clk) begin
		if (!in_resetn) begin
			in_ptr <= 0;
			in_ptr_gray <= 0;
		end else begin
			if (in_enable) begin
				fifo[in_ptr] <= in_data;
				in_ptr <= in_ptr + 1'b1;
				in_ptr_gray <= bin2gray(in_ptr + 1'b1);
			end
		end

		sync_out_ptr_0 <= out_ptr_gray;
		sync_out_ptr_1 <= sync_out_ptr_0;
		sync_out_ptr_2 <= sync_out_ptr_1;
		out_ptr_for_in_clk <= gray2bin(sync_out_ptr_2);

		in_free <= DEPTH - in_ptr + out_ptr_for_in_clk - 1;
	end

	always @(posedge out_clk) begin
		if (!out_resetn) begin
			out_ptr <= 0;
			out_ptr_gray <= 0;
		end else begin
			if (out_enable) begin
				out_ptr <= out_ptr + 1'b1;
				out_ptr_gray <= bin2gray(out_ptr + 1'b1);
				out_data <= fifo[out_ptr + 1'b1];
			end else
				out_data <= fifo[out_ptr];
		end

		sync_in_ptr_0 <= in_ptr_gray;
		sync_in_ptr_1 <= sync_in_ptr_0;
		sync_in_ptr_2 <= sync_in_ptr_1;
		in_ptr_for_out_clk <= gray2bin(sync_in_ptr_2);

		out_avail <= in_ptr_for_out_clk - out_ptr;
	end
endmodule
