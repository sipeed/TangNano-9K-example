`timescale 1ns/1ps

// `define __GOWIN__


`ifndef __GOWIN__

module Gowin_rPLL (
    input   wire        clkin,
    output  wire        clkout,
    output  wire        lock
);

assign clkout = clkin;
assign lock = 1'b1;

endmodule

module Gowin_CLKDIV (
    input   wire        hclkin,
    input   wire        resetn,
    output  wire        clkout
);

assign clkout = resetn ? hclkin : 1'b0;

endmodule

module OSER10 (
    input   wire        PCLK,
    input   wire        FCLK,
    input   wire        RESET,

    input   wire        D0,
    input   wire        D1,
    input   wire        D2,
    input   wire        D3,
    input   wire        D4,
    input   wire        D5,
    input   wire        D6,
    input   wire        D7,
    input   wire        D8,
    input   wire        D9,

    output  wire        Q
);

reg [9:0] ser_sr;
reg q_out;

always @ (posedge RESET) begin
    ser_sr <= 10'b0;
end

always @ (posedge PCLK) begin
    ser_sr <= {D9, D8, D7, D6, D5, D4, D3, D2, D1, D0};
end

always @ (posedge FCLK) begin
    {ser_sr, q_out} <= {1'b0, ser_sr};
end

always @ (negedge FCLK) begin
    {ser_sr, q_out} <= {1'b0, ser_sr};
end

assign Q = q_out;

endmodule

module ELVDS_OBUF (
    input   wire        I,
    output  wire        O,
    output  wire        OB
);

assign O = I;
assign OB = ~I;

endmodule

`endif