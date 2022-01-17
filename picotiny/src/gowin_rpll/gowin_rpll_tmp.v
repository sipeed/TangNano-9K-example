//Copyright (C)2014-2021 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//GOWIN Version: V1.9.8
//Part Number: GW1NR-LV9QN88PC6/I5
//Device: GW1NR-9C
//Created Time: Fri Nov 12 14:05:41 2021

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

    Gowin_rPLL your_instance_name(
        .clkout(clkout_o), //output clkout
        .lock(lock_o), //output lock
        .clkin(clkin_i) //input clkin
    );

//--------Copy end-------------------
