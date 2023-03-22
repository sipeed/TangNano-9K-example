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

module svo_enc #( `SVO_DEFAULT_PARAMS ) (
	input clk, resetn,

	// input stream
	//   tuser[0] ... start of frame
	input in_axis_tvalid,
	output reg in_axis_tready,
	input [SVO_BITS_PER_PIXEL-1:0] in_axis_tdata,
	input [0:0] in_axis_tuser,

	// output stream
	//   tuser[0] ... start of frame
	//   tuser[1] ... hsync
	//   tuser[2] ... vsync
	//   tuser[3] ... blank
	output reg out_axis_tvalid,
	input out_axis_tready,
	output reg [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
	output reg [3:0] out_axis_tuser
);
	`SVO_DECLS

	reg [`SVO_XYBITS-1:0] hcursor;
	reg [`SVO_XYBITS-1:0] vcursor;

	reg [3:0] ctrl_fifo [0:3];
	reg [1:0] ctrl_fifo_wraddr, ctrl_fifo_rdaddr;

	reg [SVO_BITS_PER_PIXEL:0] pixel_fifo [0:7];
	reg [2:0] pixel_fifo_wraddr, pixel_fifo_rdaddr;

	reg [SVO_BITS_PER_PIXEL+3:0] out_fifo [0:3];
	reg [1:0] out_fifo_wraddr, out_fifo_rdaddr;

	wire [1:0]  ctrl_fifo_fill =  ctrl_fifo_wraddr -  ctrl_fifo_rdaddr;
	wire [2:0] pixel_fifo_fill = pixel_fifo_wraddr - pixel_fifo_rdaddr;
	wire [1:0]   out_fifo_fill =   out_fifo_wraddr -   out_fifo_rdaddr;

	reg is_hsync, is_vsync, is_blank;

	always @(posedge clk) begin
		if (!resetn) begin
			ctrl_fifo_wraddr <= 0;
			hcursor = 0;
			vcursor = 0;
		end else if (ctrl_fifo_wraddr + 2'd1 != ctrl_fifo_rdaddr) begin
			is_blank = 0;
			is_hsync = 0;
			is_vsync = 0;

			if (hcursor < SVO_HOR_FRONT_PORCH) begin
				is_blank = 1;
			end else if (hcursor < SVO_HOR_FRONT_PORCH + SVO_HOR_SYNC) begin
				is_blank = 1;
				is_hsync = 1;
			end else if (hcursor < SVO_HOR_FRONT_PORCH + SVO_HOR_SYNC + SVO_HOR_BACK_PORCH) begin
				is_blank = 1;
			end

			if (vcursor < SVO_VER_FRONT_PORCH) begin
				is_blank = 1;
			end else if (vcursor < SVO_VER_FRONT_PORCH + SVO_VER_SYNC) begin
				is_blank = 1;
				is_vsync = 1;
			end else if (vcursor < SVO_VER_FRONT_PORCH + SVO_VER_SYNC + SVO_VER_BACK_PORCH) begin
				is_blank = 1;
			end

			ctrl_fifo[ctrl_fifo_wraddr] <= {is_blank, is_vsync, is_hsync, !hcursor && !vcursor};
			ctrl_fifo_wraddr <= ctrl_fifo_wraddr + 1;

			if (hcursor == SVO_HOR_TOTAL-1) begin
				hcursor = 0;
				vcursor = vcursor == SVO_VER_TOTAL-1 ? 0 : vcursor + 1;
			end else begin
				hcursor = hcursor + 1;
			end
		end
	end

	always @(posedge clk) begin
		if (!resetn) begin
			pixel_fifo_wraddr <= 0;
			in_axis_tready <= 0;
		end else begin
			if (in_axis_tvalid && in_axis_tready) begin
				pixel_fifo[pixel_fifo_wraddr] <= {in_axis_tuser, in_axis_tdata};
				pixel_fifo_wraddr <= pixel_fifo_wraddr + 1;
			end
			in_axis_tready <= pixel_fifo_wraddr + 3'd2 != pixel_fifo_rdaddr && pixel_fifo_wraddr + 3'd1 != pixel_fifo_rdaddr;
		end
	end

	always @(posedge clk) begin
		if (!resetn) begin
			ctrl_fifo_rdaddr <= 0;
			pixel_fifo_rdaddr <= 0;
			out_fifo_wraddr <= 0;
		end else begin
			if (ctrl_fifo_rdaddr != ctrl_fifo_wraddr && pixel_fifo_rdaddr != pixel_fifo_wraddr && out_fifo_wraddr + 2'd1 != out_fifo_rdaddr) begin
				if (ctrl_fifo[ctrl_fifo_rdaddr][0] && !pixel_fifo[pixel_fifo_rdaddr][SVO_BITS_PER_PIXEL]) begin
					// drop pixels until frame start is in sync
					pixel_fifo_rdaddr <= pixel_fifo_rdaddr + 1;
				end else
				if (ctrl_fifo[ctrl_fifo_rdaddr][3]) begin
					out_fifo[out_fifo_wraddr] <= {ctrl_fifo[ctrl_fifo_rdaddr], {SVO_BITS_PER_PIXEL{1'b0}}};
					out_fifo_wraddr <= out_fifo_wraddr + 1;
					ctrl_fifo_rdaddr <= ctrl_fifo_rdaddr + 1;
				end else begin
					out_fifo[out_fifo_wraddr] <= {ctrl_fifo[ctrl_fifo_rdaddr], pixel_fifo[pixel_fifo_rdaddr][SVO_BITS_PER_PIXEL-1:0]};
					out_fifo_wraddr <= out_fifo_wraddr + 1;
					ctrl_fifo_rdaddr <= ctrl_fifo_rdaddr + 1;
					pixel_fifo_rdaddr <= pixel_fifo_rdaddr + 1;
				end
			end
		end
	end

	reg [1:0] next_out_fifo_rdaddr;
	reg [1:0] wait_for_fifos;

	always @(posedge clk) begin
		if (!resetn) begin
			wait_for_fifos <= 0;
			out_fifo_rdaddr <= 0;
			out_axis_tvalid <= 0;
			out_axis_tdata <= 0;
			out_axis_tuser <= 0;
		end else if (wait_for_fifos < 3 || out_fifo_fill == 0) begin
			if (ctrl_fifo_fill < 3 || pixel_fifo_fill < 6 || out_fifo_fill < 3)
				wait_for_fifos <= 0;
			else
				wait_for_fifos <= wait_for_fifos + 1;
		end else begin
			next_out_fifo_rdaddr = out_fifo_rdaddr;
			if (out_axis_tvalid && out_axis_tready)
				next_out_fifo_rdaddr = next_out_fifo_rdaddr + 1;

			out_axis_tvalid <= next_out_fifo_rdaddr != out_fifo_wraddr;
			{out_axis_tuser, out_axis_tdata} <= out_fifo[next_out_fifo_rdaddr];

			out_fifo_rdaddr <= next_out_fifo_rdaddr;
		end
	end
endmodule
