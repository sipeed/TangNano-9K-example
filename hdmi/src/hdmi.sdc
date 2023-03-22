//Copyright (C)2014-2021 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//GOWIN Version: 1.9.8 
//Created Time: 2021-11-11 12:48:43
create_clock -name clk_osc -period 37.037 -waveform {0 18.518} [get_ports {clk}]
