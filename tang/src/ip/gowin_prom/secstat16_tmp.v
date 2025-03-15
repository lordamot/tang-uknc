//Copyright (C)2014-2023 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.9
//Part Number: GW2AR-LV18QN88C8/I7
//Device: GW2AR-18
//Device Version: C
//Created Time: Sun Feb 18 18:40:27 2024

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

    secstat16 your_instance_name(
        .dout(dout_o), //output [15:0] dout
        .clk(clk_i), //input clk
        .oce(oce_i), //input oce
        .ce(ce_i), //input ce
        .reset(reset_i), //input reset
        .ad(ad_i) //input [8:0] ad
    );

//--------Copy end-------------------
