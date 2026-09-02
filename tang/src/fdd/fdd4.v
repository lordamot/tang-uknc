module fdd4(
    pin_25mhz_ck,
    ppu_vm_init_i,

    data_in,
    data_out,
    write,

    drive,
    motor,
    step,
    dir,
    head,
    valid,
    sync,
    crc_ok,
    rdy,
    tr0,
    ind,

    led_init,

    rstart,
    wstart,
    rsector,
    rbusy,
    rdone,

    outen,
    outaddr,
    inbyte,
    outbyte,
    mount_dsk
);
input         pin_25mhz_ck;
input         ppu_vm_init_i;

input   [15:0]data_in;
output  [15:0]data_out;
input         write;

input   [ 1:0]drive;
input         motor;
input         step;
input         dir;
input         head;
output        valid;
output        sync;
output        crc_ok;
output        rdy;
output        tr0;
output        ind;

output        led_init;

output [ 3:0] rstart; // up to four different sources can request data 
output [ 3:0] wstart; 
output [31:0] rsector;
input         rbusy;
input         rdone;

output [ 7:0] outbyte;
input         outen;   // when outen=1, a byte of sector content
input  [ 8:0] outaddr; // outaddr from 0 to 511, because the sector size is 512
input  [ 7:0] inbyte;   // a byte of sector content 
input  [ 3:0] mount_dsk;
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
reg  [ 3:0] no_sec     =   4'd8;
reg  [ 7:0] no_trk     =   8'd5;
reg         clk_dsk    =      0;   // one 25 MHz cycle high per word - an ENABLE, not a clock
reg         clk_dsk_n  =      0;   // the same, one cycle later
reg         clk_dsk_n1 =      0;
//---------------------------------------------------------------------------------
// Everything in this module is clocked by pin_25mhz_ck and nothing else.
//
// Until Sep 2026 five flops here were clocked by data: no_trk by `step`, a
// PPU register bit; sd_rd/_trk/_sek/_data and the track ROM by clk_dsk_n;
// count_word by clk_dsk; read_sd by sd_rd with is_clean as an asynchronous
// reset.  clk_dsk and clk_dsk_n are one-cycle pulses out of a flop, so as
// clocks they travelled on general routing with whatever skew that
// placement gave them, and `step` changes on the PPU clock, which is the
// same counter as this clock (horz[3] against horz[0]) - so it changed
// right at this clock's edge and the flop it clocked won or lost a race
// that no tool could see.  test003.sdc could only name these as clocks
// with an invented 1 us period.  Each re-place-and-route re-rolled the
// dice on all of it, and the SD and floppy path is what broke when the
// dice came up wrong.
//
// Now the pulses are clock enables on the one clock, `step` goes through
// two flops and an edge detector, and the two asynchronous resets are
// synchronous.  The behaviour is the same to within one or two 25 MHz
// cycles - 40-80 ns against a 64 us word - and every path is on a clock
// the tool knows.  sim/tb/tb_fdd4.v runs the old module beside this one
// and compares what the PPU would see.
//---------------------------------------------------------------------------------
reg  [1:0]  step_s     = 2'b00;
always @(posedge pin_25mhz_ck) step_s <= {step_s[0], step};
wire        step_r     = step_s[0];              // step, synchronised
wire        step_rise  = step_s[0] & ~step_s[1]; // its rising edge
//---------------------------------------------------------------------------------
assign valid    = count_clk>10 && count_clk<900 && motor;
assign led_init = ~motor;
assign sync     = (word_sectr == 9'h18 || word_sectr == 9'h2F ) && motor;
assign crc_ok   = (word_sectr == 9'h1C || word_sectr == 9'h131) && motor;
assign ind      = (word_sectr >= 9'h01 || word_sectr <=   9'h4) && motor;
assign tr0      = !no_trk && motor;

reg  [15:0] data_out = 16'h0000;
wire disk_insert = mount_dsk[drive];

always @(*)
    case({disk_insert,_data,_sek,_trk})
    'b1000 : data_out <= data_raw;
    'b1001 : data_out <= {1'b0,no_trk,7'd0,head};
    'b1010 : data_out <= {4'd0,no_sec+1'b1,8'd2};
    'b1100 : data_out <= {data_sec[7:0],data_sec[15:8]};
    default: data_out <= 16'h4E4E;
    endcase
//---------------------------------------------------------------------------------
reg         head_old = 1'b1;
reg  [ 1:0] drive_old= 1'b0;


always @(posedge pin_25mhz_ck)
    if(step_rise)no_trk <= dir ? no_trk + 1'b1 : (no_trk ? no_trk - 1'b1 : 8'd0);

always @(posedge pin_25mhz_ck)
    if(!motor || step_r || head_old!=head || drive_old!=drive)begin
        //no_sec     <=  4'h8;
        word_sectr <=  9'h0;
        clk_dsk    <=  1'b0;
        clk_dsk_n  <=  1'b0;
        clk_dsk_n1 <=  1'b0;
        count_clk  <= 11'd0;
        head_old   <=  head;
        drive_old  <= drive;
    end else begin
//------ disk rotate immitation ---------------------------------------------------
        clk_dsk    <=       1'b0;
        clk_dsk_n  <=    clk_dsk;
        clk_dsk_n1 <=  clk_dsk_n;

        count_clk <= count_clk==1599 ? 11'd0 : count_clk + 1'b1;
        if(!count_clk)begin
            clk_dsk <= 1'b1;
            if(word_sectr==9'h168)begin no_sec <= 4'h0; word_sectr <= 9'h0; end
            else
                if(word_sectr==9'h132 && no_sec < 9)begin no_sec <= no_sec + 1'b1; word_sectr <= 9'h0; end
                else word_sectr <= word_sectr + 1'b1;
        end
//---------------------------------------------------------------------------------
    end
//---------------------------------------------------------------------------------
// raw sectr, emul raw trk
// kolesiko krutit'sa - lave mutit'sa
//---------------------------------------------------------------------------------
wire [15:0] data_raw;
rawtr_prom romtr1(
        .dout (     data_raw), //output [15:0] dout
        .clk  (pin_25mhz_ck), //input clk
        .oce  (         1'b0), //input oce
        .ce   (clk_dsk_n && motor), //input ce - reads once a word, as it did when clk_dsk_n was its clock
        .reset(ppu_vm_init_i), //input reset
        .ad   (   word_sectr)  //input [8:0] ad
    );
//---------------------------------------------------------------------------------
// SD-Card controller
//---------------------------------------------------------------------------------
wire [31:0]sd_sec    = {no_trk,head,3'b000}+{no_trk,head,1'b0} + no_sec;
//---------------------------------------------------------------------------------
reg  sd_rd = 1'b0;
reg  _trk  = 1'b0;
reg  _sek  = 1'b0;
reg  _data = 1'b0;
//reg  reset_fifo = 1'b0;

always @(posedge pin_25mhz_ck)
    if(!motor)begin
        sd_rd <= 1'b0;
        _trk  <= 1'b0;
        _sek  <= 1'b0;
        _data <= 1'b0;
    end else if(clk_dsk_n)begin
        sd_rd      <= word_sectr == 9'h1C ? 1'b1 : 1'b0;
        _trk       <= word_sectr == 9'h1A ? 1'b1 : 1'b0;
        _sek       <= word_sectr == 9'h1B ? 1'b1 : 1'b0;
        _data      <= word_sectr >= 9'h31 && word_sectr <= 9'h130 ? 1'b1 : 1'b0;
    end

reg  read_sd  = 1'b0;
reg  write_sd = 1'b0;

assign rsector = sd_sec;
assign rdy     = ~ppu_vm_init_i;
assign rstart  = {3'b000, read_sd}<<drive;
assign wstart  = {3'b000,write_sd}<<drive;

wire is_clean = ~motor|rbusy;

// read_sd rises on sd_rd's rising edge and falls as soon as the reader is
// busy or the motor stops; sd_card.v sees it in this same clock domain.
reg  sd_rd_d  = 1'b0;
always @(posedge pin_25mhz_ck)begin
    sd_rd_d <= sd_rd;
    if(is_clean)               read_sd <= 1'b0;
    else if(sd_rd && !sd_rd_d) read_sd <= disk_insert;
end
//---------------------------------------------------------------------------------
//wire reset_fifo = word_sectr == 9'h13 || !motor; //3

wire [15:0] data_sec;
reg  [ 7:0] count_word = 8'd0;

always @(posedge pin_25mhz_ck)
    if(clk_dsk)count_word <= _data ? count_word + 1'b1 : 8'd0;

dbufsec16 bffsd(
    .clka  (pin_25mhz_ck), //input clka
    .cea   (        1'b1), //input cea
    .reseta(        1'b0), //input reseta
    .ada   (     outaddr), //input [8:0] ada
    .wrea  (       outen), //input wrea
    .dina  (      inbyte), //input [7:0] dina
    .douta (     outbyte), //output [7:0] douta

    .ocea  (1'b0), //input ocea
    .oceb  (1'b0), //input oceb

    .clkb  (pin_25mhz_ck), //input clkb
    .ceb   (        1'b1), //input ceb
    .resetb(        1'b0), //input resetb
    .wreb  (       write), //input wreb
    .adb   (  count_word), //input [7:0] adb
    .dinb  (     data_in), //input [15:0] dinb
    .doutb (    data_sec) //output [15:0] doutb
);

endmodule