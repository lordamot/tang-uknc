module vp065(
   pin_50MHz_clk,
   pin_vm_clk_p,

   pin_vm_init_i,

   pin_vm_virq_o,

   pin_wbm_adr_i,
   pin_wbm_dat_i,
   pin_wbm_dat_o,
   pin_wbm_wre_i,
   pin_wbm_stb_i,
   pin_wbm_ack_o,
   pin_wbi_dat_o,
   pin_wbi_ack_o,
   pin_wbi_stb_i,

   pin_wbi_stb_o,

   pin_tx_o,
   pin_rx_i,
   pin_ac_o
);
input        pin_50MHz_clk;
input        pin_vm_clk_p;

input        pin_vm_init_i;

output       pin_vm_virq_o;

input  [16:0]pin_wbm_adr_i;
input  [15:0]pin_wbm_dat_i;
output [15:0]pin_wbm_dat_o;

input        pin_wbm_wre_i;

input        pin_wbm_stb_i;
output       pin_wbm_ack_o;
output [15:0]pin_wbi_dat_o;
output       pin_wbi_ack_o;
input        pin_wbi_stb_i;

output       pin_wbi_stb_o;

output       pin_tx_o;
input	       pin_rx_i;

output       pin_ac_o;
//--------------------------------------------
wire ce;
wire setVIRQrx;
wire setVIRQtx;
//--------------------------------------------
reg  ce_old = 1'b0;
reg  wbi_stb_i_old = 0;
reg  pin_wbm_ack_o = 1'b0;
reg  pin_wbi_ack_o = 1'b0;
reg  [15:0]pin_wbm_dat_o = 0;
reg  [15:0]pin_wbi_dat_o = 0;
reg  [12:0]R176570 = 0;
reg  [ 7:0]R176574 = 8'o200;
reg  enVIRQrx  = 1'b1;
reg  enVIRQtx  = 1'b1;
reg  load_tx = 1'b0;
reg  load_rx = 1'b0;
//--------------------------------------------
assign ce = pin_wbm_adr_i[16:3]=='o17657 && pin_wbm_stb_i;
assign setVIRQrx = rx_data_valid & R176570[6];
assign setVIRQtx = ask_tx & R176574[6];
assign pin_vm_virq_o = (|{setVIRQrx&enVIRQrx,setVIRQtx&enVIRQtx});
assign pin_wbi_stb_o = pin_vm_virq_o ? 1'b0 : pin_wbi_stb_i;
assign pin_ac_o = ~pin_rx_i;
//--------------------------------------------
always @(posedge pin_vm_clk_p)
    if(pin_vm_init_i)begin
      pin_wbm_ack_o <= 1'b0;
      pin_wbi_ack_o <= 1'b0;
      wbi_stb_i_old <= 1'b0;
      ce_old        <= 1'b0;
      R176570       <= 8'o0;
      R176574       <= 8'o200;
      enVIRQrx      <= 1'b1;
      enVIRQtx      <= 1'b1;
      load_tx       <= 1'b0;
    end else begin
      load_tx <= 1'b0;
      load_rx <= 1'b0;
      ce_old  <= ce;
      if(!pin_wbm_stb_i)begin
         pin_wbm_dat_o <= 16'o0;
         pin_wbm_ack_o <= 1'b0;
         load_tx <= 1'b0;
      end else
      if(~ce_old & ce)begin
      case({pin_wbm_wre_i, pin_wbm_adr_i[2:1]})
//	read	read	read	read	read	read	read	read	read	read	read	read	read	read	read
      //176570 - приемник sos
      'b0_00: begin pin_wbm_dat_o <= {3'b000,R176570[12],4'b0000,rx_data_valid,R176570[6],6'b000000}; pin_wbm_ack_o <= 1'b1; end
      //176572 - приемник data
      'b0_01: begin pin_wbm_dat_o <= {8'd0,rx_data}; enVIRQrx <= 1'b1; load_rx <= 1'b1; pin_wbm_ack_o <= 1'b1; end
      //176574 - передатчик sos
      'b0_10: begin pin_wbm_dat_o <= {8'b00000000,tx_en_n, R176574[6],3'b000,R176574[2],1'b0,R176574[0]}; pin_wbm_ack_o <= 1'b1; end
      //176576 - передатчик data
      'b0_11: begin pin_wbm_dat_o <= 16'o370; pin_wbm_ack_o <= 1'b1; end
//	write write write write write write write write write write write write write write write
      //176570 - приемник sos
      'b1_00: begin R176570[6] <= pin_wbm_dat_i[6]; enVIRQrx <= pin_wbm_dat_i[6]; pin_wbm_ack_o <= 1'b1; end
      //176572 - приемник data
      'b1_01: pin_wbm_ack_o <= 1'b1;
      //176574 - передатчик sos
      'b1_10: begin
               R176574[6] <= pin_wbm_dat_i[6]; enVIRQtx   <= pin_wbm_dat_i[6];
               R176574[2] <= pin_wbm_dat_i[2]; R176574[0] <= pin_wbm_dat_i[0];
               pin_wbm_ack_o <= 1'b1;
              end
      //176576 - передатчик data
      'b1_11: begin
               load_tx <= 1'b1;
               pin_wbm_ack_o <= 1'b1;
              end
      endcase
      end
      wbi_stb_i_old<=pin_wbi_stb_i;
      if(!pin_wbi_stb_i)begin
         pin_wbi_ack_o <= 1'b0;
         pin_wbi_dat_o <= 16'o0;
      end else
      if(!wbi_stb_i_old&&pin_wbi_stb_i)begin
         if(setVIRQrx && enVIRQrx)begin pin_wbi_dat_o <= 16'o370; enVIRQrx <= 0; pin_wbi_ack_o <= 1'b1; end
         else if(setVIRQtx && enVIRQtx) begin pin_wbi_dat_o <= 16'o374; enVIRQtx <= 0; pin_wbi_ack_o <= 1'b1; end
         else pin_wbi_ack_o <= 1'b0;
      end
   end
//=============================================================================================================
reg  load_tx_old = 0;
reg  ask_tx_old = 0;
reg  tx_data_valid = 0;

wire rdreq = tx_en_n ? 1'b0 : ~ask_tx_old & ask_tx;
wire wrreq = ~load_tx_old & load_tx;
wire ask_tx;
wire rx_data_valid;
wire [7:0]rx_data;

always @(posedge pin_vm_clk_p)begin load_tx_old <= load_tx; end
always @(posedge pin_50MHz_clk)begin ask_tx_old <= ~tx_en_n & ask_tx; tx_data_valid <= rdreq; end

wire [7:0]tx_data;
wire tx_en;
wire tx_en_n;

uartfifo txff1(
    .Data (pin_wbm_dat_i[7:0]), //input [7:0] Data
    .WrClk(      pin_vm_clk_p), //input WrClk
    .WrEn (             wrreq), //input WrEn

    .RdClk(     pin_50MHz_clk), //input RdClk
    .RdEn (             rdreq), //input RdEn
    .Q    (           tx_data), //output [7:0] Q

    .Empty(           tx_en_n), //output Empty
    .Full (             tx_en) //output Full
	);
//=============================================================================================================
uart_tx #(
   .BAUD_RATE(19200) //serial baud rate
) txuart
(
   .clk          ( pin_50MHz_clk),  //clock input
   .rst_n        (~pin_vm_init_i),  //asynchronous reset input, low active 
   .tx_data	     (       tx_data),  //data to send
   .tx_data_valid( tx_data_valid),  //data to be sent is valid
   .tx_data_ready(        ask_tx),  //send ready
   .tx_pin       (      pin_tx_o)   //serial data output
);
uart_rx #(
   .BAUD_RATE(19200) //serial baud rate
) rxuart
(
   .clk          ( pin_50MHz_clk),  //clock input
   .rst_n        (~pin_vm_init_i),  //asynchronous reset input, low active 
   .rx_data      (       rx_data),  //received serial data
   .rx_data_valid( rx_data_valid),  //received serial data is valid
   .rx_data_ready(       load_rx),  //data receiver module ready
   .rx_pin       (      pin_rx_i)   //serial data input
);
//=============================================================================================================
endmodule
