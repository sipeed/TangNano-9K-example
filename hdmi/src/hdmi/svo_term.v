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

module svo_term #(
	`SVO_DEFAULT_PARAMS,
	parameter MEM_DEPTH = 2048
) (
	// resetn clock domain: clk
	input clk, oclk, resetn,

	// input stream
	//
	// clock domain: clk
	//
	input        in_axis_tvalid,
	output       in_axis_tready,
	input  [7:0] in_axis_tdata,

	// output stream
	//   tuser[0] ... start of frame
	//
	// tdata[1:0] values:
	//   2'b00 ... no character
	//   2'b01 ... character background
	//   2'b10 ... character foreground
	//   2'b11 ... reserved
	//
	// clock domain: oclk
	//
	output       out_axis_tvalid,
	input        out_axis_tready,
	output [1:0] out_axis_tdata,
	output [0:0] out_axis_tuser
);
	`SVO_DECLS

	wire pipeline_en;

	// --------------------------------------------------------------
	// Text Memory
	// --------------------------------------------------------------

	localparam MEM_ABITS = svo_clog2(MEM_DEPTH);

	reg [7:0] mem [0:MEM_DEPTH-1];
	reg [MEM_ABITS-1:0] mem_start, mem_stop;

	reg [MEM_ABITS-1:0] mem_portA_addr;
	reg [7:0] mem_portA_rdata;
	reg [7:0] mem_portA_wdata;
	reg mem_portA_wen;

	reg [MEM_ABITS-1:0] mem_portB_addr;
	reg [7:0] mem_portB_rdata;

	reg [MEM_ABITS-1:0] mem_start_GR, mem_stop_GR;
	reg [MEM_ABITS-1:0] mem_start_B1, mem_stop_B1;
	reg [MEM_ABITS-1:0] mem_start_B2, mem_stop_B2;
	reg [MEM_ABITS-1:0] mem_start_B3, mem_stop_B3;
	reg [MEM_ABITS-1:0] mem_start_B,  mem_stop_B;

	function [MEM_ABITS-1:0] mem_bin2gray(input [MEM_ABITS-1:0] in);
		integer i;
		reg [MEM_ABITS:0] temp;
		begin
			temp = in;
			for (i=0; i<MEM_ABITS; i=i+1)
				mem_bin2gray[i] = ^temp[i +: 2];
		end
	endfunction

	function [MEM_ABITS-1:0] mem_gray2bin(input [MEM_ABITS-1:0] in);
		integer i;
		begin
			for (i=0; i<MEM_ABITS; i=i+1)
				mem_gray2bin[i] = ^(in >> i);
		end
	endfunction

	always @(posedge clk) begin
		if (mem_portA_wen) begin
			mem_portA_rdata <= 'bx;
			mem[mem_portA_addr] <= mem_portA_wdata;
		end else begin
			mem_portA_rdata <= mem[mem_portA_addr];
		end

		mem_start_GR <= mem_bin2gray(mem_start);
		mem_stop_GR <= mem_bin2gray(mem_stop);
	end

	always @(posedge oclk) begin
		if (pipeline_en)
			mem_portB_rdata <= mem_portB_addr != mem_stop_B ? mem[mem_portB_addr] : 0;

		mem_start_B1 <= mem_start_GR;
		mem_start_B2 <= mem_start_B1;
		mem_start_B3 <= mem_gray2bin(mem_start_B2);

		mem_stop_B1 <= mem_stop_GR;
		mem_stop_B2 <= mem_stop_B1;
		mem_stop_B3 <= mem_gray2bin(mem_stop_B2);
	end


	// --------------------------------------------------------------
	// Input Interface
	// --------------------------------------------------------------

	reg request_remove_line_oclk;
	reg request_remove_line_syn1;
	reg request_remove_line_syn2;
	reg request_remove_line_syn3;
	reg request_remove_line;

	always @(posedge clk) begin
		request_remove_line_syn1 <= request_remove_line_oclk;
		request_remove_line_syn2 <= request_remove_line_syn1;
		request_remove_line_syn3 <= request_remove_line_syn2;
		request_remove_line <= request_remove_line_syn2 != request_remove_line_syn3;
	end

	reg remove_line;
	wire [MEM_ABITS-1:0] next_mem_start, next_mem_stop;
	assign next_mem_start = mem_start == MEM_DEPTH-1 ? 0 : mem_start + 1;
	assign next_mem_stop = mem_stop == MEM_DEPTH-1 ? 0 : mem_stop + 1;
	assign in_axis_tready = next_mem_stop != mem_start && !remove_line;

	always @(posedge clk) begin
		mem_portA_wen <= 0;
		mem_portA_wdata <= in_axis_tdata;
		mem_portA_addr <= mem_start;

		if (request_remove_line && mem_start != mem_stop) begin
			mem_portA_addr <= next_mem_start;
			mem_start <= next_mem_start;
			remove_line <= 1;
		end

		if (!resetn) begin
			remove_line <= 0;
			mem_start <= 0;
			mem_stop <= 0;
		end else begin
			if (remove_line) begin
				if (mem_portA_rdata == "\n" || mem_start == mem_stop) begin
					remove_line <= 0;
				end else begin
					mem_portA_addr <= next_mem_start;
					mem_start <= next_mem_start;
				end
			end else
			if (next_mem_stop == mem_start) begin
				if (mem_portA_addr == mem_start) begin
					mem_portA_addr <= next_mem_start;
					mem_start <= next_mem_start;
					remove_line <= 1;
				end
			end else
			if (in_axis_tvalid && in_axis_tready) begin
				if (in_axis_tdata >= 32 || in_axis_tdata == "\n") begin
					mem_stop <= next_mem_stop;
					mem_portA_addr <= mem_stop;
					mem_portA_wen <= 1;
				end else
				if (in_axis_tdata == 4) begin
					// EOT clears the screen
					mem_stop <= mem_start;
				end else
				if (in_axis_tdata == 8) begin
					// BS removes the last char
					if (mem_stop != mem_start)
						mem_stop <= mem_stop == 0 ? MEM_DEPTH-1 : mem_stop-1;
				end
			end
		end
	end


	// --------------------------------------------------------------
	// Font Memory
	// --------------------------------------------------------------

	localparam [8191:0] fontmem = {
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b01100000, 8'b10010010, 8'b00001100, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00001100, 8'b00010000, 8'b00010000, 8'b00100000, 8'b00010000, 8'b00010000, 8'b00001100,
		8'b00000000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00010000,
		8'b00000000, 8'b00110000, 8'b00001000, 8'b00001000, 8'b00000100, 8'b00001000, 8'b00001000, 8'b00110000,
		8'b00000000, 8'b00111100, 8'b00001000, 8'b00010000, 8'b00100000, 8'b00111100, 8'b00000000, 8'b00000000,
		8'b00111000, 8'b01000000, 8'b01110000, 8'b01001000, 8'b01001000, 8'b01001000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b01000100, 8'b00101000, 8'b00010000, 8'b00101000, 8'b01000100, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b01000100, 8'b10101010, 8'b10010010, 8'b10000010, 8'b10000010, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00010000, 8'b00101000, 8'b01000100, 8'b01000100, 8'b01000100, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b01011000, 8'b00100100, 8'b00100100, 8'b00100100, 8'b00100100, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00111000, 8'b00010000, 8'b00000000,
		8'b00000000, 8'b00011100, 8'b00100000, 8'b00011000, 8'b00000100, 8'b00111000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000100, 8'b00000100, 8'b00000100, 8'b00001100, 8'b00110100, 8'b00000000, 8'b00000000,
		8'b00100000, 8'b00100000, 8'b00111000, 8'b00100100, 8'b00100100, 8'b01011000, 8'b00000000, 8'b00000000,
		8'b00001000, 8'b00001000, 8'b00111000, 8'b01001000, 8'b01001000, 8'b00110100, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00111000, 8'b01000100, 8'b01000100, 8'b01000100, 8'b00111000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b01001000, 8'b01001000, 8'b01001000, 8'b01001000, 8'b00110100, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b10000010, 8'b10000010, 8'b10010010, 8'b10010010, 8'b01101101, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00011000,
		8'b00000000, 8'b00100100, 8'b00010100, 8'b00001100, 8'b00010100, 8'b00100100, 8'b00000100, 8'b00000100,
		8'b00001100, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00000000, 8'b00010000, 8'b00000000,
		8'b00000000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00000000, 8'b00010000, 8'b00000000,
		8'b00000000, 8'b01000100, 8'b01000100, 8'b01000100, 8'b01001100, 8'b00110100, 8'b00000100, 8'b00000100,
		8'b00111000, 8'b01000000, 8'b01111000, 8'b01000100, 8'b01000100, 8'b10111000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00001000, 8'b00001000, 8'b00001000, 8'b00011100, 8'b00001000, 8'b01001000, 8'b00110000,
		8'b00000000, 8'b00111000, 8'b00000100, 8'b01111100, 8'b01000100, 8'b00111000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b10110000, 8'b01001000, 8'b01001000, 8'b01001000, 8'b01110000, 8'b01000000, 8'b01000000,
		8'b00000000, 8'b00111000, 8'b00000100, 8'b00000100, 8'b00000100, 8'b00111000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00110100, 8'b01001000, 8'b01001000, 8'b01001000, 8'b00111000, 8'b00001000, 8'b00001000,
		8'b00000000, 8'b10111000, 8'b01000100, 8'b01000100, 8'b01111000, 8'b01000000, 8'b00111000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00010000, 8'b00001000,
		8'b11111110, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b01000100, 8'b00101000, 8'b00010000,
		8'b00000000, 8'b00111000, 8'b00100000, 8'b00100000, 8'b00100000, 8'b00100000, 8'b00100000, 8'b00111000,
		8'b00000000, 8'b10000000, 8'b01000000, 8'b00100000, 8'b00010000, 8'b00001000, 8'b00000100, 8'b00000010,
		8'b00000000, 8'b00111000, 8'b00001000, 8'b00001000, 8'b00001000, 8'b00001000, 8'b00001000, 8'b00111000,
		8'b00000000, 8'b01111100, 8'b00000100, 8'b00001000, 8'b00010000, 8'b00100000, 8'b01000000, 8'b01111100,
		8'b00000000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00101000, 8'b01000100, 8'b01000100,
		8'b00000000, 8'b01000100, 8'b01000100, 8'b00101000, 8'b00010000, 8'b00101000, 8'b01000100, 8'b01000100,
		8'b00000000, 8'b00101000, 8'b00101000, 8'b01010100, 8'b01010100, 8'b10000010, 8'b10000010, 8'b10000010,
		8'b00000000, 8'b00010000, 8'b00010000, 8'b00101000, 8'b00101000, 8'b01000100, 8'b01000100, 8'b01000100,
		8'b00000000, 8'b00111000, 8'b01000100, 8'b01000100, 8'b01000100, 8'b01000100, 8'b01000100, 8'b01000100,
		8'b00000000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b01111100,
		8'b00000000, 8'b00111000, 8'b01000100, 8'b01000000, 8'b00111000, 8'b00000100, 8'b01000100, 8'b00111000,
		8'b00000000, 8'b01000100, 8'b00100100, 8'b00010100, 8'b00111100, 8'b01000100, 8'b01000100, 8'b00111100,
		8'b01100000, 8'b00111000, 8'b01000100, 8'b01000100, 8'b01000100, 8'b01000100, 8'b01000100, 8'b00111000,
		8'b00000000, 8'b00001000, 8'b00001000, 8'b00001000, 8'b00111000, 8'b01001000, 8'b01001000, 8'b00111000,
		8'b00000000, 8'b00111000, 8'b01000100, 8'b01000100, 8'b01000100, 8'b01000100, 8'b01000100, 8'b00111000,
		8'b00000000, 8'b01000100, 8'b01000100, 8'b01100100, 8'b01010100, 8'b01010100, 8'b01001100, 8'b01000100,
		8'b00000000, 8'b10000010, 8'b10000010, 8'b10000010, 8'b10010010, 8'b10101010, 8'b11000110, 8'b10000010,
		8'b00000000, 8'b01111000, 8'b00001000, 8'b00001000, 8'b00001000, 8'b00001000, 8'b00001000, 8'b00001000,
		8'b00000000, 8'b01000100, 8'b01000100, 8'b00100100, 8'b00011100, 8'b00100100, 8'b01000100, 8'b01000100,
		8'b00000000, 8'b00011000, 8'b00100100, 8'b00100100, 8'b00100000, 8'b00100000, 8'b00100000, 8'b01110000,
		8'b00000000, 8'b00111000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00111000,
		8'b00000000, 8'b01000100, 8'b01000100, 8'b01000100, 8'b01111100, 8'b01000100, 8'b01000100, 8'b01000100,
		8'b00000000, 8'b00111000, 8'b01000100, 8'b01000100, 8'b01110100, 8'b00000100, 8'b01000100, 8'b00111000,
		8'b00000000, 8'b00000100, 8'b00000100, 8'b00000100, 8'b01111100, 8'b00000100, 8'b00000100, 8'b01111100,
		8'b00000000, 8'b01111100, 8'b00000100, 8'b00000100, 8'b00111100, 8'b00000100, 8'b00000100, 8'b01111100,
		8'b00000000, 8'b00111100, 8'b01000100, 8'b01000100, 8'b01000100, 8'b01000100, 8'b01000100, 8'b00111100,
		8'b00000000, 8'b00111000, 8'b01000100, 8'b00000100, 8'b00000100, 8'b00000100, 8'b01000100, 8'b00111000,
		8'b00000000, 8'b00111100, 8'b01000100, 8'b01000100, 8'b00111100, 8'b01000100, 8'b01000100, 8'b00111100,
		8'b00000000, 8'b01000100, 8'b01000100, 8'b01000100, 8'b01111100, 8'b01000100, 8'b01000100, 8'b00111000,
		8'b00000000, 8'b00111000, 8'b00000100, 8'b01110100, 8'b01010100, 8'b01110100, 8'b01000100, 8'b00111000,
		8'b00000000, 8'b00010000, 8'b00000000, 8'b00010000, 8'b00100000, 8'b01000000, 8'b01000100, 8'b00111000,
		8'b00000000, 8'b00000100, 8'b00001000, 8'b00010000, 8'b00100000, 8'b00010000, 8'b00001000, 8'b00000100,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b11111110, 8'b00000000, 8'b11111110, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00100000, 8'b00010000, 8'b00001000, 8'b00000100, 8'b00001000, 8'b00010000, 8'b00100000,
		8'b00010000, 8'b00100000, 8'b00110000, 8'b00110000, 8'b00000000, 8'b00110000, 8'b00110000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00110000, 8'b00110000, 8'b00000000, 8'b00110000, 8'b00110000, 8'b00000000,
		8'b00000000, 8'b00111000, 8'b01000100, 8'b01000000, 8'b01111000, 8'b01000100, 8'b01000100, 8'b00111000,
		8'b00000000, 8'b00111000, 8'b01000100, 8'b01000100, 8'b00111000, 8'b01000100, 8'b01000100, 8'b00111000,
		8'b00000000, 8'b00001000, 8'b00001000, 8'b00001000, 8'b00010000, 8'b00100000, 8'b01000000, 8'b01111100,
		8'b00000000, 8'b00111000, 8'b01000100, 8'b01000100, 8'b00111100, 8'b00000100, 8'b01000100, 8'b00111000,
		8'b00000000, 8'b00111000, 8'b01000100, 8'b01000000, 8'b00111100, 8'b00000100, 8'b00000100, 8'b01111100,
		8'b00000000, 8'b01110000, 8'b00100000, 8'b00100000, 8'b01111100, 8'b00100100, 8'b00101000, 8'b00110000,
		8'b00000000, 8'b00111000, 8'b01000100, 8'b01000000, 8'b00110000, 8'b01000000, 8'b01000100, 8'b00111000,
		8'b00000000, 8'b01111100, 8'b00001000, 8'b00010000, 8'b00100000, 8'b01000000, 8'b01000100, 8'b00111000,
		8'b00000000, 8'b00111000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00011000, 8'b00010000,
		8'b00000000, 8'b00111000, 8'b01000100, 8'b01000100, 8'b01010100, 8'b01000100, 8'b01000100, 8'b00111000,
		8'b00000000, 8'b00000010, 8'b00000100, 8'b00001000, 8'b00010000, 8'b00100000, 8'b01000000, 8'b10000000,
		8'b00000000, 8'b00110000, 8'b00110000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b11111110, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00010000, 8'b00100000, 8'b00110000, 8'b00110000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b11111110, 8'b00010000, 8'b00010000, 8'b00010000,
		8'b00000000, 8'b00010000, 8'b10010010, 8'b01010100, 8'b00111000, 8'b01010100, 8'b10010010, 8'b00010000,
		8'b00000000, 8'b00001000, 8'b00010000, 8'b00100000, 8'b00100000, 8'b00100000, 8'b00010000, 8'b00001000,
		8'b00000000, 8'b00100000, 8'b00010000, 8'b00001000, 8'b00001000, 8'b00001000, 8'b00010000, 8'b00100000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00010000, 8'b00010000,
		8'b00000000, 8'b01011100, 8'b00100010, 8'b01100010, 8'b00010100, 8'b00001000, 8'b00010100, 8'b00011000,
		8'b00000000, 8'b00000000, 8'b01100100, 8'b01101000, 8'b00010000, 8'b00101100, 8'b01001100, 8'b00000000,
		8'b00000000, 8'b00010000, 8'b00111100, 8'b01010000, 8'b00111000, 8'b00010100, 8'b01111000, 8'b00010000,
		8'b00000000, 8'b00101000, 8'b00101000, 8'b11111110, 8'b00101000, 8'b11111110, 8'b00101000, 8'b00101000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00101000, 8'b00101000,
		8'b00000000, 8'b00010000, 8'b00000000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00010000, 8'b00010000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000,
		8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000, 8'b00000000
	};

	function font(input [7:0] c, input [2:0] x, input [2:0] y);
		font = fontmem[{c, y, x}];
	endfunction


	// --------------------------------------------------------------
	// Video Pipeline
	// --------------------------------------------------------------

	reg [3:0] oresetn_q;
	reg oresetn;

	// synchronize oresetn with oclk
	always @(posedge oclk)
		{oresetn, oresetn_q} <= {oresetn_q, resetn};

	// --------------------------------------------------------------
	// Pipeline stage 1: basic video timing

	reg p1_start_of_frame;
	reg p1_start_of_line;
	reg p1_valid;

	reg [`SVO_XYBITS-1:0] p1_xpos, p1_ypos;

	always @(posedge oclk) begin
		if (!oresetn) begin
			p1_xpos <= 0;
			p1_ypos <= 0;
			p1_valid <= 0;
		end else
		if (pipeline_en) begin
			p1_valid <= 1;
			p1_start_of_frame <= !p1_xpos && !p1_ypos;
			p1_start_of_line <= !p1_xpos;
			if (p1_xpos == SVO_HOR_PIXELS-1) begin
				p1_xpos <= 0;
				p1_ypos <= p1_ypos == SVO_VER_PIXELS-1 ? 0 : p1_ypos + 1;
			end else begin
				p1_xpos <= p1_xpos + 1;
			end
		end
	end

	// --------------------------------------------------------------
	// Pipeline stage 2: text memory addr generator

	reg [2:0] p2_x, p2_y;
	reg p2_start_of_frame;
	reg p2_start_of_line;
	reg p2_valid;

	reg p2_found_end, p2_last_req_remline;
	reg [MEM_ABITS-1:0] p2_line_start_addr;
	wire [MEM_ABITS-1:0] next_mem_portB_addr;
	assign next_mem_portB_addr = mem_portB_addr == MEM_DEPTH-1 ? 0 : mem_portB_addr + 1;

	always @(posedge oclk) begin
		if (!oresetn) begin
			p2_valid <= 0;
			p2_found_end <= 1;
			p2_last_req_remline <= 1;
			request_remove_line_oclk <= 0;
		end else
		if (pipeline_en) begin
			p2_start_of_frame <= p1_start_of_frame;
			p2_start_of_line <= p1_start_of_line;
			p2_valid <= p1_valid;

			if (mem_portB_addr == mem_stop_B)
				p2_found_end <= 1;

			if (p1_start_of_frame) begin
				if (!p2_found_end && !p2_last_req_remline) begin
					request_remove_line_oclk <= ~request_remove_line_oclk;
					p2_last_req_remline <= 1;
				end else
					p2_last_req_remline <= 0;

				mem_stop_B <= mem_stop_B3;
				mem_start_B <= mem_start_B3;
				mem_portB_addr <= mem_start_B3;
				p2_line_start_addr <= mem_start_B3;
				p2_found_end <= 0;
				p2_x <= 0;
				p2_y <= 0;
			end else
			if (p1_start_of_line) begin
				if (p2_y == 7) begin
					if (mem_portB_addr != mem_stop_B) begin
						mem_portB_addr <= next_mem_portB_addr;
						p2_line_start_addr <= next_mem_portB_addr;
					end else begin
						p2_line_start_addr <= mem_stop_B;
					end
				end else begin
					mem_portB_addr <= p2_line_start_addr;
				end
				p2_x <= 0;
				p2_y <= p2_y + 1;
			end else begin
				if (p2_x == 7) begin
					if (mem_portB_addr != mem_stop_B && mem_portB_rdata != "\n")
						mem_portB_addr <= next_mem_portB_addr;
				end
				p2_x <= p2_x + 1;
			end
		end
	end

	// --------------------------------------------------------------
	// Pipeline stage 3: wait for memory

	reg [2:0] p3_x, p3_y;
	reg p3_start_of_frame;
	reg p3_start_of_line;
	reg p3_valid;

	always @(posedge oclk) begin
		if (!oresetn) begin
			p3_valid <= 0;
		end else
		if (pipeline_en) begin
			p3_x <= p2_x;
			p3_y <= p2_y;
			p3_start_of_frame <= p2_start_of_frame;
			p3_start_of_line <= p2_start_of_line;
			p3_valid <= p2_valid;
		end
	end

	// --------------------------------------------------------------
	// Pipeline stage 4: read char

	reg [7:0] p4_c;
	reg [2:0] p4_x, p4_y;
	reg p4_start_of_frame;
	reg p4_valid;

	always @(posedge oclk) begin
		if (!oresetn) begin
			p4_valid <= 0;
		end else
		if (pipeline_en) begin
			p4_c <= mem_portB_rdata;
			p4_x <= p3_x;
			p4_y <= p3_y;
			p4_start_of_frame <= p3_start_of_frame;
			p4_valid <= p3_valid;
		end
	end

	// --------------------------------------------------------------
	// Pipeline stage 5: font lookup

	reg [1:0] p5_outval;
	reg p5_start_of_frame;
	reg p5_valid;

	always @(posedge oclk) begin
		if (!oresetn) begin
			p5_valid <= 0;
		end else
		if (pipeline_en) begin
			if (32 <= p4_c && p4_c < 128)
				p5_outval <= font(p4_c, p4_x, p4_y) ? 2'b10 : 2'b01;
			else
				p5_outval <= 0;
			p5_start_of_frame <= p4_start_of_frame;
			p5_valid <= p4_valid;
		end
	end

	// --------------------------------------------------------------
	// Pipeline output stage

	assign pipeline_en = !p5_valid || out_axis_tready;

	assign out_axis_tvalid = p5_valid;
	assign out_axis_tdata = p5_outval;
	assign out_axis_tuser = p5_start_of_frame;
endmodule

