module fdd4(
    pin_25mhz_ck,
    ppu_vm_init_i,

   SD_clk,
   SD_cs,
   SD_datain,
   SD_dataout,

    data_in;
    data_out;

    drive,
    motor,
    step,
    dir,
    head,
    valid,

   led_init,
   
   osd_addr,
   osd_data,
   
   disk_a,
   disk_b,
   disk_c,
   disk_d,
   
   num_files
);
input         pin_25mhz_ck;
input         ppu_vm_init_i;

input   [15:0]data_in;
output  [15:0]data_out;

input   [ 2:0]drive;
input         motor;
input         step;
input         dir;
input         head;
output        valid;

output        SD_clk;
output        SD_cs;
output        SD_datain;
input         SD_dataout;

output        led_init;

input  [  6:0]osd_addr;
output [127:0]osd_data;

input  [  6:0]disk_a;
input  [  6:0]disk_b;
input  [  6:0]disk_c;
input  [  6:0]disk_d;

output reg [6:0]num_files;
//---------------------------------------------------------------------------------
// Size dsk image in sectors
//---------------------------------------------------------------------------------
// 1600 = 819200 / 512
//---------------------------------------------------------------------------------
// Spin disk emulation
//---------------------------------------------------------------------------------
// 25MHz input clk, 3125 16-bit word per one spin, result clk = 25000000/5/3125 = 1600
// 1 word in 64mkS
//---------------------------------------------------------------------------------
reg  [10:0] count_clk  =      0;
reg  [ 8:0] word_sectr =      0;
reg  [ 3:0] no_sec     =   4'd0;
reg  [ 7:0] no_trk     =   8'd5;
reg  [ 2:0] steps      = 3'b000;
reg         clk_dsk    =      0;
//---------------------------------------------------------------------------------
assign valid    = clk_dsk;
assign data_out = data_raw;
//---------------------------------------------------------------------------------
reg  step_old = 1'b0;
reg  head_old = 1'b0;

always @(posedge pin_25mhz_ck or negedge motor)
    if(!motor)begin
        no_sec <= 4'h0; word_sectr <= 9'h0;
        clk_dsk <= 1'b0;
    end else begin
//------ disk rotate immitation ---------------------------------------------------
        if(count_clk==1599)begin
            count_clk <= 11'd0;
            clk_dsk   <= 1'b1;
            if(word_sectr==9'h169)begin no_sec <= 4'h0; word_sectr <= 9'h0; end
            else
                if(word_sectr==9'h132 && no_sec < 9)begin no_sec <= no_sec + 1'b1; word_sectr <= 9'h0; end
                else word_sectr <= word_sectr + 1'b1;
        end else begin count_clk <= count_clk + 1'b1; clk_dsk <= 1'b0;end
//------ SETEP immitation ---------------------------------------------------------
        steps <= {steps[1:0],step};
        step_old <= steps[2];
        if(!step_old && steps[2])no_trk <= dir ? no_trk + 1'b1 : (no_trk ? no_trk - 1'b1 : 8'd0);
//------ HEAD and STEP new data ---------------------------------------------------------
        head_old <= head;
        if((!head_old && head) || (!step_old && steps[2]))begin no_sec <= 4'h0; word_sectr <= 9'h0; end
//---------------------------------------------------------------------------------
    end
//---------------------------------------------------------------------------------
// raw sectr, emul raw trk
// kolesiko krutit'sa - lave mutit'sa
//---------------------------------------------------------------------------------
wire [15:0] data_raw;
rawtr_prom romtr1(
        .dout (     data_raw), //output [15:0] dout
        .clk  ( pin_25mhz_ck), //input clk
        .oce  (         1'b0), //input oce
        .ce   (        motor), //input ce
        .reset(ppu_vm_init_i), //input reset
        .ad   (   word_sectr)  //input [8:0] ad
    );
//---------------------------------------------------------------------------------
// SD-Card controller
//---------------------------------------------------------------------------------
wire [ 6:0]image_nom = (drive==0 ? disk_a :
                        drive==1 ? disk_b :
                        drive==2 ? disk_c : disk_d) - 1'b1;

wire [31:0]sec_image = (image_nom<<10) + (image_nom<<9) + (image_nom<<6); //1600 * (image_nom - 1'b1);

wire [31:0]sd_sec = {no_trk,head,3'b000}+{no_trk,head,1'b0} + no_sec + 4 + sec_image;
//---------------------------------------------------------------------------------
endmodule