//
//Written by GowinSynthesis
//Product Version "GowinSynthesis V1.9.8"
//Fri Nov 12 13:20:17 2021

//Source file index table:
//file0 "\D:/Gowin_ov/Gowin_V1.9.8/IDE/ipcore/DDR/data/ddr.v"
`timescale 100 ps/100 ps
module Gowin_DDR (
  din,
  fclk,
  pclk,
  reset,
  q
)
;
input [9:0] din;
input fclk;
input pclk;
input reset;
output [0:0] q;
wire [0:0] ddr_inst_o;
wire VCC;
wire GND;
  OBUF \obuf_gen[0].obuf_inst  (
    .O(q[0]),
    .I(ddr_inst_o[0]) 
);
  OSER10 \oser10_gen[0].oser10_inst  (
    .Q(ddr_inst_o[0]),
    .D0(din[0]),
    .D1(din[1]),
    .D2(din[2]),
    .D3(din[3]),
    .D4(din[4]),
    .D5(din[5]),
    .D6(din[6]),
    .D7(din[7]),
    .D8(din[8]),
    .D9(din[9]),
    .PCLK(pclk),
    .FCLK(fclk),
    .RESET(reset) 
);
  VCC VCC_cZ (
    .V(VCC)
);
  GND GND_cZ (
    .G(GND)
);
  GSR GSR (
    .GSRI(VCC) 
);
endmodule /* Gowin_DDR */
