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
// module svo_pong
//
// a clone of the Atari 1972 game PONG. this is implemented as a video
// filter with enable input. when enabled it will overlay the game on the
// video stream. connect .auto_btn with .btn to let the game play against
// itself.
// ----------------------------------------------------------------------

module svo_pong #( `SVO_DEFAULT_PARAMS ) (
	input clk, resetn, resetn_game, enable,

	input [3:0] btn,
	output [3:0] auto_btn,

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

	wire [11:0] p1_pos, p2_pos;
	wire [6:0] p1_points, p2_points;
	wire [11:0] puck_x, puck_y;
	wire flash;

	svo_pong_control #( `SVO_PASS_PARAMS ) svo_pong_control (
		.clk(clk),
		.resetn(resetn && resetn_game),
		.enable(in_axis_tvalid && in_axis_tready && in_axis_tuser && enable),

		.btn(btn),
		.auto_btn(auto_btn),

		.flash(flash),
		.p1_pos(p1_pos),
		.p2_pos(p2_pos),
		.p1_points(p1_points),
		.p2_points(p2_points),
		.puck_x(puck_x),
		.puck_y(puck_y)
	);

	svo_pong_video #( `SVO_PASS_PARAMS ) svo_pong_video (
		.clk(clk),
		.resetn(resetn),
		.enable(enable),

		.flash(flash),
		.p1_pos(p1_pos),
		.p2_pos(p2_pos),
		.p1_points(p1_points),
		.p2_points(p2_points),
		.puck_x(puck_x),
		.puck_y(puck_y),

		.in_axis_tvalid(in_axis_tvalid),
		.in_axis_tready(in_axis_tready),
		.in_axis_tdata(in_axis_tdata),
		.in_axis_tuser(in_axis_tuser),

		.out_axis_tvalid(out_axis_tvalid),
		.out_axis_tready(out_axis_tready),
		.out_axis_tdata(out_axis_tdata),
		.out_axis_tuser(out_axis_tuser)
	);
endmodule


// ----------------------------------------------------------------------
// module svo_pong_control
//
// the actual game logic. this is only enabled once for each frame.
// ----------------------------------------------------------------------

module svo_pong_control #( `SVO_DEFAULT_PARAMS ) (
	input clk, resetn, enable,

	input [3:0] btn,
	output reg [3:0] auto_btn,

	output flash,
	output reg [11:0] p1_pos, p2_pos,
	output reg [6:0] p1_points, p2_points,
	output reg [11:0] puck_x, puck_y
);
	`SVO_DECLS

	function integer score_max_vy;
		input integer max_vx, max_vy, max_x, max_y;
		begin
			score_max_vy = (2*max_x*max_vy / max_vx) % (2*max_y) - max_y;
			score_max_vy = score_max_vy < 0 ? -score_max_vy : score_max_vy;
		end
	endfunction

	function integer best_max_vy;
		input integer max_vx, max_x, max_y, from_i, to_i;
		integer i;
		begin
			best_max_vy = from_i;
			for (i = from_i; i != to_i; i = i+1)
				if (score_max_vy(max_vx, i, max_x, max_y) < score_max_vy(max_vx, best_max_vy, max_x, max_y))
					best_max_vy = i;
		end
	endfunction

	localparam max_vx = 15;
	localparam max_vy = best_max_vy(max_vx, SVO_HOR_PIXELS, SVO_VER_PIXELS, 8, 12);

	reg signed [11:0] p1y, p2y;
	reg signed [4:0] p1vy, p2vy;
	reg signed [11:0] px, py;
	reg signed [4:0] pvx, pvy;
	reg [7:0] rng_q;

	reg signed [11:0] ppx, ppy;
	reg pp_state;

	reg [3:0] flash_count;
	assign flash = |flash_count;

	reg [2:0] state;

	reg detect_left_paddle;
	reg detect_right_paddle;

	always @(posedge clk) begin
		if (!resetn)
			rng_q <= 1;
		else if (^{btn, ppx, ppy})
			rng_q <= {rng_q[6:0], rng_q[7] ^ rng_q[5] ^ rng_q[4] ^ rng_q[3]};

		if (!resetn) begin

			flash_count <= 0;
			p1_points <= 0;
			p2_points <= 0;
			p1_pos <= SVO_VER_PIXELS / 2 - 50;
			p2_pos <= SVO_VER_PIXELS / 2 - 50;
			puck_x <= SVO_HOR_PIXELS / 2;
			puck_y <= SVO_VER_PIXELS / 2;
			pp_state <= 0;
			state <= 0;

			px = SVO_HOR_PIXELS / 2;
			py = SVO_VER_PIXELS / 2;
			pvx = 3;
			pvy = 4;
			p1y = SVO_VER_PIXELS / 2 - 50;
			p2y = SVO_VER_PIXELS / 2 - 50;
			p1vy = 0;
			p2vy = 0;
			ppx = SVO_HOR_PIXELS / 2;
			ppy = SVO_VER_PIXELS / 2;

		end else if (state == 0) begin

			// handle goals (left)

			if (pvx < 0 && px < 5) begin
				px = SVO_HOR_PIXELS-6;
				pvx = rng_q[0] ? -2 : -3;
				pvy = pvy < 0 ? (rng_q[1] ? -3 : -4) : (rng_q[2] ? 3 : 4);
				p2_points <= p2_points == 99 ? 0 : p2_points + 1;
				flash_count <= 6;
			end

			state <= 1;
		end else if (state == 1) begin

			// handle goals (right)

			if (pvx > 0 && px > SVO_HOR_PIXELS-6) begin
				px = 5;
				pvx = rng_q[0] ? 2 : 3;
				pvy = pvy < 0 ? (rng_q[1] ? -3 : -4) : (rng_q[2] ? 3 : 4);
				p1_points <= p1_points == 99 ? 0 : p1_points + 1;
				flash_count <= 6;
			end

			state <= 2;
		end else if (state == 2) begin

			// move puck (1/3)

			px = px + pvx;
			py = py + pvy;

			if (py < 5) begin
				py = 2*5 - py;
				pvy = -pvy == max_vy ? max_vy : -pvy+1;
				pp_state <= 0;
			end else
			if (py > SVO_VER_PIXELS-6) begin
				py = 2*(SVO_VER_PIXELS-6) - py;
				pvy = pvy == max_vy ? -max_vy : -pvy-1;
				pp_state <= 0;
			end

			state <= 3;
		end else if (state == 3) begin

			// move puck (2/3)

			detect_left_paddle = pvx < 0 && 5 < px && px < 22 && p1y - 5 < py && py < p1y + 105;
			detect_right_paddle = pvx > 0 && SVO_HOR_PIXELS-23 < px && px < SVO_HOR_PIXELS-6 && p2y - 5 < py && py < p2y + 105;
			
			state <= 4;
		end else if (state == 4) begin

			// move puck (3/3)

			if (detect_left_paddle) begin
				px = 2*22 - px;
				pvx = -pvx == max_vx ? max_vx : -pvx+1;
				pp_state <= 0;
			end else
			if (detect_right_paddle) begin
				px = 2*(SVO_HOR_PIXELS-23) - px;
				pvx = pvx == max_vx ? -max_vx : -pvx-1;
				pp_state <= 0;
			end

			state <= 5;
		end else if (state == 5) begin

			// move player 1 paddle

			p1y = p1y + p1vy;
			if (p1y < 0) p1y = 0;
			if (p1y > SVO_VER_PIXELS-102) p1y = SVO_VER_PIXELS-102;

			p1vy = p1vy + btn[3] - btn[2];
			if (!btn[3:2] && p1vy)
				p1vy = p1vy < 0 ? p1vy+1 : p1vy-1;

			if (p1vy > +10) p1vy = +10;
			if (p1vy < -10) p1vy = -10;

			state <= 6;
		end else if (state == 6) begin

			// move player 2 paddle

			p2y = p2y + p2vy;
			if (p2y < 0) p2y = 0;
			if (p2y > SVO_VER_PIXELS-102) p2y = SVO_VER_PIXELS-102;

			p2vy = p2vy + btn[0] - btn[1];
			if (!btn[1:0] && p2vy)
				p2vy = p2vy < 0 ? p2vy+1 : p2vy-1;

			if (p2vy > +10) p2vy = +10;
			if (p2vy < -10) p2vy = -10;

			state <= 7;
		end else if (enable) begin

			// primitive auto pilot

			auto_btn <= 0;
			if (pvx < 0) begin
				if (px < SVO_VER_PIXELS-80) begin
					if (ppy < p1y + 30) auto_btn[2] <= 1;
					if (ppy > p1y + 70) auto_btn[3] <= 1;
				end
			end else begin
				if (px > SVO_HOR_PIXELS-SVO_VER_PIXELS+79) begin
					if (ppy < p2y + 30) auto_btn[1] <= 1;
					if (ppy > p2y + 70) auto_btn[0] <= 1;
				end
			end

			// update output signals bits

			p1_pos <= p1y;
			p2_pos <= p2y;
			puck_x <= px < 5 ? 5 : px > SVO_HOR_PIXELS-6 ? SVO_HOR_PIXELS-6 : px;
			puck_y <= py;

			if (flash_count > 0) flash_count <= flash_count-1;
			state <= 0;

		end else begin

			// move puck projection
			//
			// this is done every cycle until the puck hits the wall. then when the enable
			// signal is activated the next time, the registers ppy and ppx contain the
			// predicted coordinates the puck is heading. this is used for the autopilot.

			if (!pp_state) begin
				ppx = px;
				ppy = py + $signed(rng_q[4:0]);
				pp_state <= 1;
			end else begin
				if (20 < ppx && ppx < SVO_HOR_PIXELS-21) begin
					ppy = ppy + pvy;
					ppx = ppx + pvx;
				end else if (ppy < 5)
					ppy = 2*5 - ppy;
				else if (ppy > SVO_VER_PIXELS-6)
					ppy = 2*(SVO_VER_PIXELS-6) - ppy;
			end
		end
	end
endmodule


// ----------------------------------------------------------------------
// module svo_pong_video
//
// the video composition pipeline for the svo_pong module.
// ----------------------------------------------------------------------

module svo_pong_video #( `SVO_DEFAULT_PARAMS ) (
	input clk, resetn, enable, flash,

	input [11:0] p1_pos, p2_pos,
	input [6:0] p1_points, p2_points,
	input [11:0] puck_x, puck_y,

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


	// rectangle coordinates

	reg [11:0] rect1_x1, rect1_x2, rect1_y1, rect1_y2;
	reg [11:0] rect2_x1, rect2_x2, rect2_y1, rect2_y2;
	reg [11:0] rect3_x1, rect3_x2, rect3_y1, rect3_y2;

	always @(posedge clk) begin
		rect1_x1 <= 10;
		rect1_x2 <= 20;
		rect1_y1 <= p1_pos;
		rect1_y2 <= p1_pos + 100;

		rect2_x1 <= SVO_HOR_PIXELS - 20;
		rect2_x2 <= SVO_HOR_PIXELS - 10;
		rect2_y1 <= p2_pos;
		rect2_y2 <= p2_pos + 100;

		rect3_x1 <= puck_x - 5;
		rect3_x2 <= puck_x + 5;
		rect3_y1 <= puck_y - 5;
		rect3_y2 <= puck_y + 5;
	end


	// video pipeline

	localparam s_maxidx = 9;

	wire s_tvalid [0:s_maxidx], s_tready [0:s_maxidx];
	wire [SVO_BITS_PER_PIXEL-1:0] s_tdata [0:s_maxidx];
	wire [2:0] s_tuser [0:s_maxidx];

	assign s_tvalid[0] = in_axis_tvalid;
	assign in_axis_tready = s_tready[0];
	assign s_tdata[0] = in_axis_tdata;
	assign s_tuser[0] = in_axis_tuser;

	`define IN(_idx, _ubits)   .in_axis_tvalid(s_tvalid[_idx]),   .in_axis_tready(s_tready[_idx]),   .in_axis_tdata(s_tdata[_idx]),   .in_axis_tuser(s_tuser[_idx][(_ubits)-1:0])
	`define OVER(_idx, _ubits) .over_axis_tvalid(s_tvalid[_idx]), .over_axis_tready(s_tready[_idx]), .over_axis_tdata(s_tdata[_idx]), .over_axis_tuser(s_tuser[_idx][(_ubits)-1:0])
	`define OUT(_idx, _ubits)  .out_axis_tvalid(s_tvalid[_idx]),  .out_axis_tready(s_tready[_idx]),  .out_axis_tdata(s_tdata[_idx]),  .out_axis_tuser(s_tuser[_idx][(_ubits)-1:0])

	svo_dim #( `SVO_PASS_PARAMS ) compose_1 (
		.clk(clk), .resetn(resetn),
		.enable(enable && !flash),
		`IN(0, 1), `OUT(1, 1)
	);

	svo_rect #( `SVO_PASS_PARAMS ) compose_2 (
		.clk(clk), .resetn(resetn),
		.x1(rect1_x1), .y1(rect1_y1),
		.x2(rect1_x2), .y2(rect1_y2),
		`OUT(2, 3)
	);

	svo_overlay #( `SVO_PASS_PARAMS ) compose_3 (
		.clk(clk), .resetn(resetn), .enable(enable),
		`IN(1, 1), `OVER(2, 2), `OUT(3, 1)
	);

	svo_rect #( `SVO_PASS_PARAMS ) compose_4 (
		.clk(clk), .resetn(resetn),
		.x1(rect2_x1), .y1(rect2_y1),
		.x2(rect2_x2), .y2(rect2_y2),
		`OUT(4, 3)
	);

	svo_overlay #( `SVO_PASS_PARAMS ) compose_5 (
		.clk(clk), .resetn(resetn), .enable(enable),
		`IN(3, 1), `OVER(4, 2), `OUT(5, 1)
	);

	svo_pong_scores #( `SVO_PASS_PARAMS ) compose_6 (
		.clk(clk), .resetn(resetn),
		.p1_points(p1_points),
		.p2_points(p2_points),
		`OUT(6, 2)
	);

	svo_overlay #( `SVO_PASS_PARAMS ) compose_7 (
		.clk(clk), .resetn(resetn), .enable(enable),
		`IN(5, 1), `OVER(6, 2), `OUT(7, 1)
	);

	svo_rect #( `SVO_PASS_PARAMS ) compose_8 (
		.clk(clk), .resetn(resetn),
		.x1(rect3_x1), .y1(rect3_y1),
		.x2(rect3_x2), .y2(rect3_y2),
		`OUT(8, 3)
	);

	svo_overlay #( `SVO_PASS_PARAMS ) compose_9 (
		.clk(clk), .resetn(resetn), .enable(enable),
		`IN(7, 1), `OVER(8, 2), `OUT(9, 1)
	);

	`undef IN
	`undef OVER
	`undef OUT

	assign out_axis_tvalid = s_tvalid[s_maxidx];
	assign s_tready[s_maxidx] = out_axis_tready;
	assign out_axis_tdata = s_tdata[s_maxidx];
	assign out_axis_tuser = s_tuser[s_maxidx];
endmodule


// ----------------------------------------------------------------------
// module svo_pong_scores
//
// creates the overlay video stream with the current score
// ----------------------------------------------------------------------

module svo_pong_scores #( `SVO_DEFAULT_PARAMS ) (
	input clk, resetn,

	input [6:0] p1_points, p2_points,

	// output stream
	//   tuser[0] ... start of frame
	output out_axis_tvalid,
	input out_axis_tready,
	output [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
	output [1:0] out_axis_tuser
);
	`SVO_DECLS

	wire pipeline_enable = out_axis_tready || !out_axis_tvalid;

	reg [3:0] digit0, digit1, digit2, digit3;

	always @(posedge clk) begin
		digit0 = p1_points / 10;
		digit1 = p1_points % 10;
		digit2 = p2_points / 10;
		digit3 = p2_points % 10;
	end

	// ----------------------------------------------------------
	// first pipeline stage: create stream of x/y coordinates

	reg p1_valid;
	reg [`SVO_XYBITS-1:0] p1_x;
	reg [`SVO_XYBITS-1:0] p1_y;

	always @(posedge clk) begin:p1
		if (!resetn) begin
			p1_valid <= 0;
			p1_x <= 0;
			p1_y <= 0;
		end else if (pipeline_enable) begin
			if (p1_valid) begin
				if (p1_x == SVO_HOR_PIXELS-1) begin
					p1_x <= 0;
					p1_y <= (p1_y == SVO_VER_PIXELS-1) ? 0 : p1_y + 1;
				end else begin
					p1_x <= p1_x + 1;
				end
			end else
				p1_valid <= 1;
		end
	end


	// ----------------------------------------------------------
	// second stage: translate into relative digit coordinates

	reg p2_valid;
	reg p2_fstart;
	reg p2_outside;
	reg [1:0] p2_digit;
	reg [7:0] p2_x;
	reg [7:0] p2_y;

	localparam digit0_xoff =  80;
	localparam digit1_xoff = 180;
	localparam digit2_xoff = SVO_HOR_PIXELS - 270;
	localparam digit3_xoff = SVO_HOR_PIXELS - 170;

	localparam digit0_yoff = 15;
	localparam digit1_yoff = 15;
	localparam digit2_yoff = 15;
	localparam digit3_yoff = 15;

	localparam digit_width = 3*30 + 1;
	localparam digit_height = 5*30 + 1;

	always @(posedge clk) begin:p2
		if (!resetn) begin
			p2_valid <= 0;
		end else if (pipeline_enable) begin
			p2_valid <= p1_valid;
			p2_fstart <= !p1_x && !p1_y;
			if (digit0_xoff <= p1_x && p1_x < digit0_xoff + digit_width &&
			    digit0_yoff <= p1_y && p1_y < digit0_yoff + digit_height) begin
				p2_outside <= 0;
				p2_digit <= 0;
				p2_x <= p1_x - digit0_xoff;
				p2_y <= p1_y - digit0_yoff;
			end else
			if (digit1_xoff <= p1_x && p1_x < digit1_xoff + digit_width &&
			    digit1_yoff <= p1_y && p1_y < digit1_yoff + digit_height) begin
				p2_outside <= 0;
				p2_digit <= 1;
				p2_x <= p1_x - digit1_xoff;
				p2_y <= p1_y - digit1_yoff;
			end else
			if (digit2_xoff <= p1_x && p1_x < digit2_xoff + digit_width &&
			    digit2_yoff <= p1_y && p1_y < digit2_yoff + digit_height) begin
				p2_outside <= 0;
				p2_digit <= 2;
				p2_x <= p1_x - digit2_xoff;
				p2_y <= p1_y - digit2_yoff;
			end else
			if (digit3_xoff <= p1_x && p1_x < digit3_xoff + digit_width &&
			    digit3_yoff <= p1_y && p1_y < digit3_yoff + digit_height) begin
				p2_outside <= 0;
				p2_digit <= 3;
				p2_x <= p1_x - digit3_xoff;
				p2_y <= p1_y - digit3_yoff;
			end else begin
				p2_outside <= 1;
				p2_digit <= 'bx;
				p2_x <= 'bx;
				p2_y <= 'bx;
			end
		end
	end


	// ----------------------------------------------------------
	// third stage: translate into coarse grid coordinates

	// even x/y coordinates are on grid lines, odd coordinates the
	// space between the grid lines. the coordinates for a signle digit
	// use the following layout:
	//
	//               X-Coordinate
	//
	//             0  1  2  3  4  5  6
	//             v     v     v     v
	//         0-> +-----+-----+-----+
	//             |*****************|
	//         1   |*****************|
	//             |*****************|
	//    Y    2-> +-----+-----+*****+
	//    -                    |*****|
	//    C    3               |*****|
	//    o                    |*****|
	//    o    4-> +-----+-----+*****+
	//    r        |*****************|
	//    d    5   |*****************|
	//    i        |*****************|
	//    n    6-> +-----+-----+*****+
	//    a                    |*****|
	//    t    7               |*****|
	//    e                    |*****|
	//         8-> +-----+-----+*****+
	//             |*****************|
	//         9   |*****************|
	//             |*****************|
	//        10-> +-----+-----+-----+
	//
	reg p3_valid;
	reg p3_fstart;
	reg p3_outside;
	reg [1:0] p3_digit;
	reg [3:0] p3_value;
	reg [2:0] p3_x;
	reg [3:0] p3_y;

	always @(posedge clk) begin:p3
		reg [3:0] per_digit_y [0:3];
		if (!resetn) begin
			p3_valid <= 0;
		end else if (pipeline_enable) begin
			p3_valid <= p2_valid;
			p3_fstart <= p2_fstart;
			p3_outside <= p2_outside;
			p3_digit <= p2_digit;

			case (p2_x)
				 0: p3_x <= 0;
				30: p3_x <= 2;
				60: p3_x <= 4;
				90: p3_x <= 6;
			default:
				case (p3_x)
					0: p3_x <= 1;
					2: p3_x <= 3;
					4: p3_x <= 5;
				endcase
			endcase

			if (!p2_outside) begin
				case (p2_y)
					  0: per_digit_y[p2_digit] =  0;
					 30: per_digit_y[p2_digit] =  2;
					 60: per_digit_y[p2_digit] =  4;
					 90: per_digit_y[p2_digit] =  6;
					120: per_digit_y[p2_digit] =  8;
					150: per_digit_y[p2_digit] = 10;
				default:
					case (per_digit_y[p2_digit])
						0: per_digit_y[p2_digit] = 1;
						2: per_digit_y[p2_digit] = 3;
						4: per_digit_y[p2_digit] = 5;
						6: per_digit_y[p2_digit] = 7;
						8: per_digit_y[p2_digit] = 9;
					endcase
				endcase
			end

			p3_y <= per_digit_y[p2_digit];

			case (p2_digit)
				0: p3_value <= digit0;
				1: p3_value <= digit1;
				2: p3_value <= digit2;
				3: p3_value <= digit3;
			endcase
		end
	end


	// ----------------------------------------------------------
	// stage four: calc font addresses

	reg p4_valid;
	reg p4_fstart;
	reg p4_outside;
	reg p4_ongrid;
	reg [1:0] p4_digit;
	reg [3:0] p4_value;
	reg [3:0] p4_addr;
	reg [3:0] p4_addr_left_up;
	reg [3:0] p4_addr_right_up;
	reg [3:0] p4_addr_left_down;
	reg [3:0] p4_addr_right_down;

	always @(posedge clk) begin:p4
		reg [1:0] x_left;
		reg [1:0] x_right;
		reg [2:0] y_up;
		reg [2:0] y_down;
		if (!resetn) begin
			p4_valid <= 0;
		end else if (pipeline_enable) begin
			p4_valid <= p3_valid;
			p4_fstart <= p3_fstart;
			p4_outside <= p3_outside;
			p4_ongrid <= !p3_y[0] || !p3_x[0];
			p4_digit <= p3_digit;
			p4_value <= p3_value;

			case (p3_x)
				0: begin x_left = 3; x_right = 0; end
				1: begin x_left = 0; x_right = 0; end
				2: begin x_left = 0; x_right = 1; end
				3: begin x_left = 1; x_right = 1; end
				4: begin x_left = 1; x_right = 2; end
				5: begin x_left = 2; x_right = 2; end
				6: begin x_left = 2; x_right = 3; end
			endcase

			case (p3_y)
				 0: begin y_up = 7; y_down = 0; end
				 1: begin y_up = 0; y_down = 0; end
				 2: begin y_up = 0; y_down = 1; end
				 3: begin y_up = 1; y_down = 1; end
				 4: begin y_up = 1; y_down = 2; end
				 5: begin y_up = 2; y_down = 2; end
				 6: begin y_up = 2; y_down = 3; end
				 7: begin y_up = 3; y_down = 3; end
				 8: begin y_up = 3; y_down = 4; end
				 9: begin y_up = 4; y_down = 4; end
				10: begin y_up = 4; y_down = 7; end
			endcase

			p4_addr <= p3_y[3:1] + p3_x[2:1]*5;
			p4_addr_left_up    <= x_left  != 3 && y_up   != 7 ? y_up   + x_left  * 5 : 15;
			p4_addr_right_up   <= x_right != 3 && y_up   != 7 ? y_up   + x_right * 5 : 15;
			p4_addr_left_down  <= x_left  != 3 && y_down != 7 ? y_down + x_left  * 5 : 15;
			p4_addr_right_down <= x_right != 3 && y_down != 7 ? y_down + x_right * 5 : 15;
		end
	end


	// ----------------------------------------------------------
	// stage five: translate to rgb values

	reg p5_valid;
	reg p5_fstart;
	reg p5_outside;
	reg [SVO_BITS_PER_PIXEL-1:0] p5_color;

	reg [15:0] font [0:9];

	initial begin
		// 5'b 0000X, <- upper right corner is fixed.
		// 5'b 000/0,    the image is fliped along the
		// 5'b 00/00     diagonal when displayed.
		font[0] = { 1'b0,
			5'b 11111,
			5'b 10001,
			5'b 11111
		};
		font[1] = { 1'b0,
			5'b 00000,
			5'b 11111,
			5'b 00000
		};
		font[2] = { 1'b0,
			5'b 10111,
			5'b 10101,
			5'b 11101
		};
		font[3] = { 1'b0,
			5'b 11111,
			5'b 10101,
			5'b 10101
		};
		font[4] = { 1'b0,
			5'b 11111,
			5'b 00100,
			5'b 00111
		};
		font[5] = { 1'b0,
			5'b 11101,
			5'b 10101,
			5'b 10111
		};
		font[6] = { 1'b0,
			5'b 11101,
			5'b 10101,
			5'b 11111
		};
		font[7] = { 1'b0,
			5'b 11111,
			5'b 00001,
			5'b 00001
		};
		font[8] = { 1'b0,
			5'b 11111,
			5'b 10101,
			5'b 11111
		};
		font[9] = { 1'b0,
			5'b 11111,
			5'b 10101,
			5'b 10111
		};
	end

	always @(posedge clk) begin:p5
		reg [3:0] neigh;
		if (!resetn) begin
			p5_valid <= 0;
		end else if (pipeline_enable) begin
			p5_valid <= p4_valid;
			p5_fstart <= p4_fstart;
			if (p4_ongrid) begin
				neigh[0] = font[p4_value][p4_addr_left_up];
				neigh[1] = font[p4_value][p4_addr_right_up];
				neigh[2] = font[p4_value][p4_addr_left_down];
				neigh[3] = font[p4_value][p4_addr_right_down];
				if (&neigh) begin
					p5_outside <= p4_outside;
					p5_color <= ~0;
				end else
				if (|neigh) begin
					p5_outside <= p4_outside;
					p5_color <= 0;
				end else begin
					p5_outside <= 1;
					p5_color <= 'bx;
				end
			end else begin
				p5_outside <= p4_outside || !font[p4_value][p4_addr];
				p5_color <= ~0;
			end
		end
	end

	// ----------------------------------------------------------

	assign out_axis_tvalid = p5_valid;
	assign out_axis_tuser = {!p5_outside, p5_fstart};
	assign out_axis_tdata = p5_color;
endmodule
