//Copyright (C)2014-2020 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//GOWIN Version: V1.9.6.02Beta
//Part Number: GW1NR-LV9QN88PC6/I5
//Created Time: Thu Nov 04 10:43:37 2021

module Gowin_OSC (oscout);

output oscout;

OSC osc_inst (
    .OSCOUT(oscout)
);

defparam osc_inst.FREQ_DIV = 10;
defparam osc_inst.DEVICE = "GW1NR-9C";

endmodule //Gowin_OSC
