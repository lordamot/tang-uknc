// I2S transmitter for the on-board DAC.
module audio_drive(
    input        clk_1p536m,//bit clock: one sample pair every 32 clocks, 16 per channel
    input        rst_n     ,//asynchronous reset, active low
    //sample interface
    input [15:0] idata     ,//left  channel sample
    input [15:0] idata_rgt ,//right channel sample
    output       req       ,//sample request; usable as an external FIFO's read strobe (AND it with !fifo_empty to avoid reading an empty one)
    //I2S pins
    output       HP_BCK   ,//bit clock, clk_1p536m passed through
    output       HP_WS    ,//word select, low for the left channel
    output       HP_DIN    //serial data into the DAC
);
reg [4:0] b_cnt;
reg       req_r,req_r1;//req_r1 is req_r one clock later
reg [15:0] idata_r;//the sample being shifted out, MSB first
reg HP_WS_r,HP_DIN_r;
assign HP_BCK = clk_1p536m;
assign HP_WS  = HP_WS_r   ;
assign HP_DIN = HP_DIN_r  ;
assign req    = req_r     ;
//b_cnt
always@(posedge clk_1p536m or negedge rst_n)
begin
if(!rst_n)
    b_cnt    <= 5'd0;
else
    b_cnt <= b_cnt+1'b1;
end
//req_r
always@(posedge clk_1p536m or negedge rst_n)
begin
if(!rst_n)
    req_r <= 1'b0;
else
    req_r <= (b_cnt == 5'd0) || (b_cnt == 5'd16);//one sample every 16 clocks
end
//idata_r
always@(posedge clk_1p536m or negedge rst_n)
begin
if(!rst_n)
    begin
    req_r1  <= 1'b0;
    idata_r <= 16'd0;
    end
else
    begin
    req_r1  <= req_r;
    // b_cnt is 2 on the load for the WS=0 slot and 18 on the load for
    // WS=1, so bit 4 says which channel is being loaded.  Feeding the same
    // word to both, as this did before, is what made the AY mono.
    idata_r <= req_r1?(b_cnt[4]?idata_rgt:idata):idata_r<<1;
    end
end
//HP_DIN_r
always@(posedge clk_1p536m or negedge rst_n)
begin
if(!rst_n)
    HP_DIN_r <= 1'b0;
else
    HP_DIN_r <= idata_r[15];
end
//HP_WS_r
always@(posedge clk_1p536m or negedge rst_n)
begin
if(!rst_n)
    HP_WS_r <= 1'b0;
else
    HP_WS_r <= (b_cnt == 5'd3)?1'b0: ((b_cnt == 5'd19)?1'b1:HP_WS_r);//WS changes one bit ahead of the data, as I2S wants
end
endmodule