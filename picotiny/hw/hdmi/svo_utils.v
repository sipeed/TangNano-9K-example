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


// ----------------------------------------------------------------------
// module svo_axis_pipe
//
// this core is a simple helper for creating video pipeline cores with
// an axi stream interface.
// ----------------------------------------------------------------------

module svo_axis_pipe #(
	parameter TDATA_WIDTH = 8,
	parameter TUSER_WIDTH = 1
) (
	input clk, resetn,

	// axis input stream
	input in_axis_tvalid,
	output in_axis_tready,
	input [TDATA_WIDTH-1:0] in_axis_tdata,
	input [TUSER_WIDTH-1:0] in_axis_tuser,

	// axis output stream
	output out_axis_tvalid,
	input out_axis_tready,
	output [TDATA_WIDTH-1:0] out_axis_tdata,
	output [TUSER_WIDTH-1:0] out_axis_tuser,

	// pipeline i/o
	output [TDATA_WIDTH-1:0] pipe_in_tdata,
	input [TDATA_WIDTH-1:0] pipe_out_tdata,
	output [TUSER_WIDTH-1:0] pipe_in_tuser,
	input [TUSER_WIDTH-1:0] pipe_out_tuser,
	output pipe_in_tvalid,
	input pipe_out_tvalid,
	output pipe_enable
);
	reg tvalid_q0, tvalid_q1;
	reg [TDATA_WIDTH-1:0] tdata_q0, tdata_q1;
	reg [TUSER_WIDTH-1:0] tuser_q0, tuser_q1;

	assign in_axis_tready = !tvalid_q1;
	assign out_axis_tvalid = tvalid_q0 || tvalid_q1;
	assign out_axis_tdata = tvalid_q1 ? tdata_q1 : tdata_q0;
	assign out_axis_tuser = tvalid_q1 ? tuser_q1 : tuser_q0;

	assign pipe_enable = in_axis_tvalid && in_axis_tready;
	assign pipe_in_tdata = in_axis_tdata;
	assign pipe_in_tuser = in_axis_tuser;
	assign pipe_in_tvalid = in_axis_tvalid;

	always @(posedge clk) begin
		if (!resetn) begin
			tvalid_q0 <= 0;
			tvalid_q1 <= 0;
		end else begin
			if (pipe_enable) begin
				tdata_q0 <= pipe_out_tdata;
				tdata_q1 <= tdata_q0;
				tuser_q0 <= pipe_out_tuser;
				tuser_q1 <= tuser_q0;
				tvalid_q0 <= pipe_out_tvalid;
				tvalid_q1 <= tvalid_q0 && !out_axis_tready;
			end else if (out_axis_tready) begin
				if (tvalid_q1)
					tvalid_q1 <= 0;
				else
					tvalid_q0 <= 0;
			end
		end
	end
endmodule


// ----------------------------------------------------------------------
// module svo_buf
//
// just a buffer that adds an other ff layer to the stream.
// ----------------------------------------------------------------------

module svo_buf #(
	parameter TUSER_WIDTH = 1,
	`SVO_DEFAULT_PARAMS
) (
	input clk, resetn,

	// input stream
	//   tuser[0] ... start of frame
	input in_axis_tvalid,
	output in_axis_tready,
	input [SVO_BITS_PER_PIXEL-1:0] in_axis_tdata,
	input [TUSER_WIDTH-1:0] in_axis_tuser,

	// output stream
	//   tuser[0] ... start of frame
	output out_axis_tvalid,
	input out_axis_tready,
	output [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
	output [TUSER_WIDTH-1:0] out_axis_tuser
);
	`SVO_DECLS

	wire [SVO_BITS_PER_PIXEL-1:0] pipe_in_tdata;
	reg [SVO_BITS_PER_PIXEL-1:0] pipe_out_tdata;
	wire [TUSER_WIDTH-1:0] pipe_in_tuser;
	reg [TUSER_WIDTH-1:0] pipe_out_tuser;
	wire pipe_in_tvalid;
	reg pipe_out_tvalid;
	wire pipe_enable;

	always @(posedge clk) begin
		if (!resetn) begin
			pipe_out_tvalid <= 0;
		end else
		if (pipe_enable) begin
			pipe_out_tdata <= pipe_in_tdata;
			pipe_out_tuser <= pipe_in_tuser;
			pipe_out_tvalid <= pipe_in_tvalid;
		end
	end

	svo_axis_pipe #(
		.TDATA_WIDTH(SVO_BITS_PER_PIXEL),
		.TUSER_WIDTH(TUSER_WIDTH)
	) svo_axis_pipe (
		.clk(clk),
		.resetn(resetn),

		.in_axis_tvalid(in_axis_tvalid),
		.in_axis_tready(in_axis_tready),
		.in_axis_tdata(in_axis_tdata),
		.in_axis_tuser(in_axis_tuser),

		.out_axis_tvalid(out_axis_tvalid),
		.out_axis_tready(out_axis_tready),
		.out_axis_tdata(out_axis_tdata),
		.out_axis_tuser(out_axis_tuser),

		.pipe_in_tdata(pipe_in_tdata),
		.pipe_out_tdata(pipe_out_tdata),
		.pipe_in_tuser(pipe_in_tuser),
		.pipe_out_tuser(pipe_out_tuser),
		.pipe_in_tvalid(pipe_in_tvalid),
		.pipe_out_tvalid(pipe_out_tvalid),
		.pipe_enable(pipe_enable)
	);
endmodule


// ----------------------------------------------------------------------
// module svo_dim
//
// this core dims the video data (half each r/g/b sample value) when
// the enable input is high. it is also a nice demo of how to create
// simple pipelines that integrate with axi4 streams.
// ----------------------------------------------------------------------

module svo_dim #( `SVO_DEFAULT_PARAMS ) (
	input clk, resetn, enable,

	// input stream
	//   tuser[0] ... start of frame
	input in_axis_tvalid,
	output in_axis_tready,
	input [SVO_BITS_PER_PIXEL-1:0] in_axis_tdata,
	input [0:0] in_axis_tuser,

	// output stream
	//   tuser[0] ... start of frame
	output out_axis_tvalid,
	input out_axis_tready,
	output [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
	output [0:0] out_axis_tuser
);
	`SVO_DECLS

	wire [SVO_BITS_PER_PIXEL-1:0] pipe_in_tdata;
	reg [SVO_BITS_PER_PIXEL-1:0] pipe_out_tdata;
	wire pipe_in_tuser;
	reg pipe_out_tuser;
	wire pipe_in_tvalid;
	reg pipe_out_tvalid;
	wire pipe_enable;

	always @(posedge clk) begin
		if (!resetn) begin
			pipe_out_tvalid <= 0;
		end else
		if (pipe_enable) begin
			pipe_out_tdata <= enable ? svo_rgba(svo_r(pipe_in_tdata) >> 1, svo_g(pipe_in_tdata) >> 1, svo_b(pipe_in_tdata) >> 1, svo_a(pipe_in_tdata)) : pipe_in_tdata;
			pipe_out_tuser <= pipe_in_tuser;
			pipe_out_tvalid <= pipe_in_tvalid;
		end
	end

	svo_axis_pipe #(
		.TDATA_WIDTH(SVO_BITS_PER_PIXEL),
		.TUSER_WIDTH(1)
	) svo_axis_pipe (
		.clk(clk),
		.resetn(resetn),

		.in_axis_tvalid(in_axis_tvalid),
		.in_axis_tready(in_axis_tready),
		.in_axis_tdata(in_axis_tdata),
		.in_axis_tuser(in_axis_tuser),

		.out_axis_tvalid(out_axis_tvalid),
		.out_axis_tready(out_axis_tready),
		.out_axis_tdata(out_axis_tdata),
		.out_axis_tuser(out_axis_tuser),

		.pipe_in_tdata(pipe_in_tdata),
		.pipe_out_tdata(pipe_out_tdata),
		.pipe_in_tuser(pipe_in_tuser),
		.pipe_out_tuser(pipe_out_tuser),
		.pipe_in_tvalid(pipe_in_tvalid),
		.pipe_out_tvalid(pipe_out_tvalid),
		.pipe_enable(pipe_enable)
	);
endmodule


// ----------------------------------------------------------------------
// module svo_overlay
//
// overlay one video stream ontop of another one
// ----------------------------------------------------------------------

module svo_overlay #( `SVO_DEFAULT_PARAMS ) (
	input clk, resetn, enable,

	// input stream
	//   tuser[0] ... start of frame
	input in_axis_tvalid,
	output in_axis_tready,
	input [SVO_BITS_PER_PIXEL-1:0] in_axis_tdata,
	input [0:0] in_axis_tuser,

	// overlay stream
	//   tuser[0] ... start of frame
	//   tuser[1] ... use overlay pixel
	input over_axis_tvalid,
	output over_axis_tready,
	input [SVO_BITS_PER_PIXEL-1:0] over_axis_tdata,
	input [1:0] over_axis_tuser,

	// output stream
	//   tuser[0] ... start of frame
	output out_axis_tvalid,
	input out_axis_tready,
	output [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
	output [0:0] out_axis_tuser
);
	`SVO_DECLS

	wire buf_in_axis_tvalid;
	wire buf_in_axis_tready;
	wire [SVO_BITS_PER_PIXEL-1:0] buf_in_axis_tdata;
	wire [0:0] buf_in_axis_tuser;

	wire buf_over_axis_tvalid;
	wire buf_over_axis_tready;
	wire [SVO_BITS_PER_PIXEL-1:0] buf_over_axis_tdata;
	wire [1:0] buf_over_axis_tuser;

	wire buf_out_axis_tvalid;
	wire buf_out_axis_tready;
	wire [SVO_BITS_PER_PIXEL-1:0] buf_out_axis_tdata;
	wire [0:0] buf_out_axis_tuser;

	// -------------------------------------------------------------------

	wire active = buf_in_axis_tvalid && buf_over_axis_tvalid;
	wire skip_in = !buf_in_axis_tuser[0] && buf_over_axis_tuser[0];
	wire skip_over = buf_in_axis_tuser[0] && !buf_over_axis_tuser[0];

	assign buf_in_axis_tready = active && (skip_in || (!skip_over && buf_out_axis_tready));
	assign buf_over_axis_tready = active && (skip_over || (!skip_in && buf_out_axis_tready));

	assign buf_out_axis_tvalid = active && !skip_in && !skip_over;
	assign buf_out_axis_tdata = enable && buf_over_axis_tuser[1] ? buf_over_axis_tdata : buf_in_axis_tdata;
	assign buf_out_axis_tuser = enable && buf_over_axis_tuser[1] ? buf_over_axis_tuser : buf_in_axis_tuser;

	// -------------------------------------------------------------------

	svo_buf #( `SVO_PASS_PARAMS ) svo_buf_in (
		.clk(clk), .resetn(resetn),

		.in_axis_tvalid(in_axis_tvalid),
		.in_axis_tready(in_axis_tready),
		.in_axis_tdata(in_axis_tdata),
		.in_axis_tuser(in_axis_tuser),

		.out_axis_tvalid(buf_in_axis_tvalid),
		.out_axis_tready(buf_in_axis_tready),
		.out_axis_tdata(buf_in_axis_tdata),
		.out_axis_tuser(buf_in_axis_tuser)
	);

	svo_buf #( .TUSER_WIDTH(2), `SVO_PASS_PARAMS ) svo_buf_over (
		.clk(clk), .resetn(resetn),

		.in_axis_tvalid(over_axis_tvalid),
		.in_axis_tready(over_axis_tready),
		.in_axis_tdata(over_axis_tdata),
		.in_axis_tuser(over_axis_tuser),

		.out_axis_tvalid(buf_over_axis_tvalid),
		.out_axis_tready(buf_over_axis_tready),
		.out_axis_tdata(buf_over_axis_tdata),
		.out_axis_tuser(buf_over_axis_tuser)
	);

	svo_buf #( `SVO_PASS_PARAMS ) svo_buf_out (
		.clk(clk), .resetn(resetn),

		.in_axis_tvalid(buf_out_axis_tvalid),
		.in_axis_tready(buf_out_axis_tready),
		.in_axis_tdata(buf_out_axis_tdata),
		.in_axis_tuser(buf_out_axis_tuser),

		.out_axis_tvalid(out_axis_tvalid),
		.out_axis_tready(out_axis_tready),
		.out_axis_tdata(out_axis_tdata),
		.out_axis_tuser(out_axis_tuser)
	);
endmodule


// ----------------------------------------------------------------------
// module svo_rect
//
// this core creates a video stream that contains a white rectangle with
// black outline. two additional tuser output fields are used to signal
// which pixels do belong to the rectangle.
// ----------------------------------------------------------------------

module svo_rect #( `SVO_DEFAULT_PARAMS ) (
	input clk, resetn,
	input [11:0] x1, y1, x2, y2,

	// output stream
	//   tuser[0] ... start of frame
	//   tuser[1] ... pixel in rectange
	//   tuser[2] ... pixel on rect. border
	output reg out_axis_tvalid,
	input out_axis_tready,
	output reg [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
	output reg [2:0] out_axis_tuser
);
	`SVO_DECLS

	reg [`SVO_XYBITS-1:0] x;
	reg [`SVO_XYBITS-1:0] y;
	reg on_x, on_y;
	reg in_x, in_y;
	reg border;

	always @(posedge clk) begin
		if (!resetn) begin
			x = 0;
			y = 0;
			in_x = 0;
			in_y = 0;
		end else begin
			if (out_axis_tvalid && out_axis_tready) begin
				if (x == SVO_HOR_PIXELS-1) begin
					x = 0;
					y = (y == SVO_VER_PIXELS-1) ? 0 : y + 1;
				end else begin
					x = x + 1;
				end
			end

			if (x == x1) in_x = 1;
			if (y == y1) in_y = 1;

			on_x = x == x1 || x == x2;
			on_y = y == y1 || y == y2;
			border =  in_x && in_y && (on_x || on_y);

			out_axis_tvalid <= 1;
			out_axis_tdata <= {SVO_BITS_PER_PIXEL{~border}};
			out_axis_tuser[0] <= !x && !y;
			out_axis_tuser[1] <= in_x && in_y;
			out_axis_tuser[2] <= border;

			if (x == x2) in_x = 0;
			if (y == y2 && x == x2) in_y = 0;
		end
	end
endmodule

