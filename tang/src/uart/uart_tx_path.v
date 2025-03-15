`timescale 1ns / 1ps

module uart_tx_path(
	clk_i,

	uart_tx_data_i,		// data
	uart_tx_en_i,					// transmite enable
	
	uart_tx_done,				//start send
	
	uart_tx_o
);
input  clk_i;

input  [7:0] uart_tx_data_i;		// data
input  uart_tx_en_i;					// transmite enable
	
output uart_tx_done;				//start send
output uart_tx_o;
//-----------------------------------
parameter BAUD_DIV     = 13'd5208/2;      //9600bps = 50Mhz/9600=5208
parameter BAUD_DIV_CAP = 13'd2604/2;      //50Mhz/9600/2=2604

reg [12:0] baud_div = 0;
reg baud_bps = 0;
reg [10:0] send_data = 11'b11111111111;
reg [3:0] bit_num = 0;
reg uart_send_flag = 0;
reg uart_tx_o_r = 1;

reg uart_tx_en_i_old = 0;
reg [2:0]uart_tx_r = 0;

reg uart_tx_done = 0;

always@(posedge clk_i)uart_tx_r <= {uart_tx_r[1:0],uart_tx_en_i};

always@(posedge clk_i)
	if(baud_div==BAUD_DIV_CAP)begin
			baud_bps<=1'b1;
			baud_div<=baud_div+1'b1;
		end else
			if(baud_div<BAUD_DIV && uart_send_flag)begin
				baud_div<=baud_div+1'b1;
				baud_bps<=0;	
			end else	begin
					baud_bps<=0;
					baud_div<=0;
				 end

always@(posedge clk_i)begin
		if(~uart_tx_en_i_old & uart_tx_r[2])begin 
			uart_send_flag<=1'b1;
			send_data<={2'b11,uart_tx_data_i,1'b0};
			uart_tx_done <= 1'b0;
		end
		uart_tx_en_i_old <= uart_tx_r[2];
		if(bit_num==4'd11)begin	uart_send_flag<=1'b0; send_data<=11'b1111_1111_111; uart_tx_done <= 1'b1;end
		//uart_tx_done <= |bit_num[2:0] ? 1'b1 : 1'b0;
	end
		
always@(posedge clk_i)
		if(uart_send_flag)begin
			if(baud_bps)begin
				if(bit_num < 4'd11)begin
						uart_tx_o_r <= send_data[bit_num];
						bit_num <= bit_num + 1'b1;
					end
			end else if(bit_num==4'd11) bit_num <= 4'd0;
			end else	begin
					uart_tx_o_r <= 1'b1;
					bit_num <= 0;
				end

assign uart_tx_o=uart_tx_o_r;

endmodule
