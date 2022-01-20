//Copyright (C)2014-2021 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//GOWIN Version: V1.9.8
//Part Number: GW1N-LV9QN88C6/I5
//Device: GW1N-9
//Created Time: Thu Jan 20 13:31:52 2022

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

    bootram_2kx8_0 your_instance_name(
        .dout(dout_o), //output [7:0] dout
        .clk(clk_i), //input clk
        .oce(oce_i), //input oce
        .ce(ce_i), //input ce
        .reset(reset_i), //input reset
        .wre(wre_i), //input wre
        .ad(ad_i), //input [10:0] ad
        .din(din_i) //input [7:0] din
    );

//--------Copy end-------------------
