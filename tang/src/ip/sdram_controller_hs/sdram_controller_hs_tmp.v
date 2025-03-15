//Copyright (C)2014-2023 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.9
//Part Number: GW2AR-LV18QN88C8/I7
//Device: GW2AR-18
//Device Version: C
//Created Time: Sun Feb 18 16:06:45 2024

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

	SDRAM_Controller_HS_Top your_instance_name(
		.O_sdram_clk(O_sdram_clk_o), //output O_sdram_clk
		.O_sdram_cke(O_sdram_cke_o), //output O_sdram_cke
		.O_sdram_cs_n(O_sdram_cs_n_o), //output O_sdram_cs_n
		.O_sdram_cas_n(O_sdram_cas_n_o), //output O_sdram_cas_n
		.O_sdram_ras_n(O_sdram_ras_n_o), //output O_sdram_ras_n
		.O_sdram_wen_n(O_sdram_wen_n_o), //output O_sdram_wen_n
		.O_sdram_dqm(O_sdram_dqm_o), //output [3:0] O_sdram_dqm
		.O_sdram_addr(O_sdram_addr_o), //output [10:0] O_sdram_addr
		.O_sdram_ba(O_sdram_ba_o), //output [1:0] O_sdram_ba
		.IO_sdram_dq(IO_sdram_dq_io), //inout [31:0] IO_sdram_dq
		.I_sdrc_rst_n(I_sdrc_rst_n_i), //input I_sdrc_rst_n
		.I_sdrc_clk(I_sdrc_clk_i), //input I_sdrc_clk
		.I_sdram_clk(I_sdram_clk_i), //input I_sdram_clk
		.I_sdrc_cmd_en(I_sdrc_cmd_en_i), //input I_sdrc_cmd_en
		.I_sdrc_cmd(I_sdrc_cmd_i), //input [2:0] I_sdrc_cmd
		.I_sdrc_precharge_ctrl(I_sdrc_precharge_ctrl_i), //input I_sdrc_precharge_ctrl
		.I_sdram_power_down(I_sdram_power_down_i), //input I_sdram_power_down
		.I_sdram_selfrefresh(I_sdram_selfrefresh_i), //input I_sdram_selfrefresh
		.I_sdrc_addr(I_sdrc_addr_i), //input [20:0] I_sdrc_addr
		.I_sdrc_dqm(I_sdrc_dqm_i), //input [3:0] I_sdrc_dqm
		.I_sdrc_data(I_sdrc_data_i), //input [31:0] I_sdrc_data
		.I_sdrc_data_len(I_sdrc_data_len_i), //input [7:0] I_sdrc_data_len
		.O_sdrc_data(O_sdrc_data_o), //output [31:0] O_sdrc_data
		.O_sdrc_init_done(O_sdrc_init_done_o), //output O_sdrc_init_done
		.O_sdrc_cmd_ack(O_sdrc_cmd_ack_o) //output O_sdrc_cmd_ack
	);

//--------Copy end-------------------
