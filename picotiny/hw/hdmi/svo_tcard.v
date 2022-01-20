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

module svo_tcard #( `SVO_DEFAULT_PARAMS ) (
	input clk, resetn,

	// output stream
	//   tuser[0] ... start of frame
	output reg out_axis_tvalid,
	input out_axis_tready,
	output reg [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
	output reg [0:0] out_axis_tuser
);
	`SVO_DECLS

	localparam HOFFSET = ((32 - (SVO_HOR_PIXELS % 32)) % 32) / 2;
	localparam VOFFSET = ((32 - (SVO_VER_PIXELS % 32)) % 32) / 2;

	localparam HOR_CELLS = (SVO_HOR_PIXELS + 31) / 32;
	localparam VER_CELLS = (SVO_VER_PIXELS + 31) / 32;

	localparam BAR_W = (HOR_CELLS - 8 - HOR_CELLS%2) / 2;

	localparam X1 =  2;
	localparam X2 = 2 + BAR_W;
	localparam X3 = HOR_CELLS - 4 - BAR_W;
	localparam X4 = HOR_CELLS - 4;

	function integer best_y_params;
		input integer n, which;
		integer best_y_blk;
		integer best_y_off;
		integer best_y_gap;
		begin
			best_y_blk = 0;
			best_y_gap = 0;
			best_y_off = 0;

			if (SVO_VER_PIXELS == 480) begin
				best_y_blk = 3;
				best_y_gap = 1;
				best_y_off = 1;
			end

			if (SVO_VER_PIXELS == 600) begin
				best_y_blk = 3;
				best_y_gap = 2;
				best_y_off = 2;
			end

			if (SVO_VER_PIXELS == 768) begin
				best_y_blk = 4;
				best_y_gap = 3;
				best_y_off = 2;
			end

			if (SVO_VER_PIXELS == 1080) begin
				best_y_blk = 6;
				best_y_gap = 2;
				best_y_off = 5;
			end

			if (which == 1) best_y_params = best_y_blk;
			if (which == 2) best_y_params = best_y_gap;
			if (which == 3) best_y_params = best_y_off;
		end
	endfunction

	localparam Y_BLK = best_y_params(VER_CELLS, 1);
	localparam Y_GAP = best_y_params(VER_CELLS, 2);
	localparam Y_OFF = best_y_params(VER_CELLS, 3);

	localparam Y1 = 0*Y_BLK + 0*Y_GAP + Y_OFF;
	localparam Y2 = 1*Y_BLK + 0*Y_GAP + Y_OFF;
	localparam Y3 = 1*Y_BLK + 1*Y_GAP + Y_OFF;
	localparam Y4 = 2*Y_BLK + 1*Y_GAP + Y_OFF;
	localparam Y5 = 2*Y_BLK + 2*Y_GAP + Y_OFF;
	localparam Y6 = 3*Y_BLK + 2*Y_GAP + Y_OFF;

	reg [`SVO_XYBITS-1:0] hcursor;
	reg [`SVO_XYBITS-1:0] vcursor;

	reg [`SVO_XYBITS-6:0] x;
	reg [`SVO_XYBITS-6:0] y;

	reg [4:0] xoff, yoff;

	reg [31:0] rng;
	reg [SVO_BITS_PER_RED-1:0] r;
	reg [SVO_BITS_PER_GREEN-1:0] g;
	reg [SVO_BITS_PER_BLUE-1:0] b;

	wire [32*32-1:0] bolt_bitmap = {
		32'b 00000000000000000000000000000000,
		32'b 01111111000000000000000001111111,
		32'b 01111100000000000000000000011111,
		32'b 01110000000000000000000000000111,
		32'b 01100000000000000000000000000011,
		32'b 01100000000000000000000000000011,
		32'b 01000000000000000000000000000001,
		32'b 01000000000000000000000000000001,
		32'b 00000000000000000000000000000000,
		32'b 00000000000000000000000000000000,
		32'b 00000000000000000000000000000000,
		32'b 00000000000000000000000000000000,
		32'b 00000000000000111100000000000000,
		32'b 00000000000001111110000000000000,
		32'b 00000000000011111111000000000000,
		32'b 00000000000011111111000000000000,
		32'b 00000000000011111111000000000000,
		32'b 00000000000011111111000000000000,
		32'b 00000000000001111110000000000000,
		32'b 00000000000000111100000000000000,
		32'b 00000000000000000000000000000000,
		32'b 00000000000000000000000000000000,
		32'b 00000000000000000000000000000000,
		32'b 00000000000000000000000000000000,
		32'b 00000000000000000000000000000000,
		32'b 01000000000000000000000000000001,
		32'b 01000000000000000000000000000001,
		32'b 01100000000000000000000000000011,
		32'b 01100000000000000000000000000011,
		32'b 01110000000000000000000000000111,
		32'b 01111100000000000000000000011111,
		32'b 01111111000000000000000001111111
	};

	always @(posedge clk) begin
		if (!resetn) begin
			hcursor <= 0;
			vcursor <= 0;
			x <= 0;
			y <= 0;
			xoff <= HOFFSET;
			yoff <= VOFFSET;
			out_axis_tvalid <= 0;
			out_axis_tdata <= 0;
			out_axis_tuser <= 0;
		end else
		if (!out_axis_tvalid || out_axis_tready) begin
			if (hcursor == 0)
				rng = y ^ 123456789;

			rng = rng ^ (rng << 13);
			rng = rng ^ (rng >> 17);
			rng = rng ^ (rng <<  5);

			if (!xoff || hcursor == 0) begin
				r = 16 * rng[0] + 16 * rng[1] + 31 * rng[2];
				g = 16 * rng[3] + 16 * rng[4] + 31 * rng[5];
				b = 16 * rng[6] + 16 * rng[7] + 31 * rng[8];

				if ({r, g, b} == 0) begin
					r = 32;
					g = 32;
					b = 32;
				end
			end

			if (&xoff || &yoff) begin
				r = 0;
				g = 0;
				b = 0;
			end

			if (SVO_VER_PIXELS >= 480) begin
				if (X1 < x && x <= X2 && Y1 < y && y <= Y2) begin
					r = 63;
					g = 0;
					b = 0;
				end

				if (X1 < x && x <= X2 && Y3 < y && y <= Y4) begin
					r = 0;
					g = 63;
					b = 0;
				end

				if (X1 < x && x <= X2 && Y5 < y && y <= Y6) begin
					r = 0;
					g = 0;
					b = 63;
				end

				if (X3 < x && x <= X4 && Y1 < y && y <= Y2) begin
					r = 0;
					g = 63;
					b = 63;
				end

				if (X3 < x && x <= X4 && Y3 < y && y <= Y4) begin
					r = 63;
					g = 0;
					b = 63;
				end

				if (X3 < x && x <= X4 && Y5 < y && y <= Y6) begin
					r = 63;
					g = 63;
					b = 0;
				end

				if (&xoff && (x == X2 || x == X4)) begin
					r = 0;
					g = 0;
					b = 0;
				end

				if (&yoff && (y == Y2 || y == Y4 || y == Y6)) begin
					r = 0;
					g = 0;
					b = 0;
				end
			end

			out_axis_tvalid <= 1;
			if ((x == 1 || x == HOR_CELLS-2) && (y == 1 || y == VER_CELLS-2))
				out_axis_tdata <= bolt_bitmap[{yoff,  xoff}] ? ~0 : 0;
			else
				out_axis_tdata <= {b, g, r};
			out_axis_tuser[0] <= !hcursor && !vcursor;

			if (hcursor == SVO_HOR_PIXELS-1) begin
				hcursor <= 0;
				x <= 0;
				xoff <= HOFFSET;
				if (vcursor == SVO_VER_PIXELS-1) begin
					vcursor <= 0;
					y <= 0;
					yoff <= VOFFSET;
				end else begin
					vcursor <= vcursor + 1;
					if (&yoff)
						y <= y + 1;
					yoff <= yoff + 1;
				end
			end else begin
				hcursor <= hcursor + 1;
				if (&xoff)
					x <= x + 1;
				xoff <= xoff + 1;
			end
		end
	end
endmodule
