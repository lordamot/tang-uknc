/*
IO_LOC "PA_EN" 51;
IO_PORT "PA_EN" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "HP_DIN" 54;
IO_PORT "HP_DIN" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "HP_WS" 55;
IO_PORT "HP_WS" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "HP_BCK" 56;
IO_PORT "HP_BCK" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
*/
/*
IO_LOC "LCD_B[4]" 27;
IO_PORT "LCD_B[4]" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "LCD_B[3]" 28;
IO_PORT "LCD_B[3]" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "LCD_B[2]" 29;
IO_PORT "LCD_B[2]" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "LCD_B[1]" 30;
IO_PORT "LCD_B[1]" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "LCD_B[0]" 31;
IO_PORT "LCD_B[0]" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "LCD_G[5]" 32;
IO_PORT "LCD_G[5]" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "LCD_G[4]" 33;
IO_PORT "LCD_G[4]" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "LCD_G[3]" 34;
IO_PORT "LCD_G[3]" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "LCD_G[2]" 35;
IO_PORT "LCD_G[2]" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "LCD_G[1]" 36;
IO_PORT "LCD_G[1]" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "LCD_G[0]" 37;
IO_PORT "LCD_G[0]" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "LCD_R[4]" 38;
IO_PORT "LCD_R[4]" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "LCD_R[3]" 39;
IO_PORT "LCD_R[3]" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "LCD_R[2]" 40;
IO_PORT "LCD_R[2]" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "LCD_R[1]" 41;
IO_PORT "LCD_R[1]" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "LCD_R[0]" 42;
IO_PORT "LCD_R[0]" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "LCD_DEN" 48;
IO_PORT "LCD_DEN" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "LCD_VS" 26;
IO_PORT "LCD_VS" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "LCD_HS" 25;
IO_PORT "LCD_HS" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "LCD_CLK" 77;
IO_PORT "LCD_CLK" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
*/

module top(
    clk27,
    buts,
    leds,

    uart_tx,
    uart_rx,

    sdclk,
    sdcmd,
    sddat0,
    sddat1,
    sddat2,
    sddat3,

    O_tmds_clk_p,
    O_tmds_clk_n,
    O_tmds_data_p,
    O_tmds_data_n,

    HP_BCK,
    HP_WS, 
    HP_DIN,
    PA_EN,

    O_sdram_clk,
    O_sdram_cke,
    O_sdram_cs_n,
    O_sdram_cas_n,
    O_sdram_ras_n,
    O_sdram_wen_n,
    O_sdram_dqm,
    O_sdram_addr,
    O_sdram_ba,
    IO_sdram_dq,

    spi_io_ss,
    spi_io_clk,
    spi_io_din,
    spi_io_dout,
    mcu_intn
);
input         clk27;
input  [ 1:0] buts ;
output [ 5:0] leds ;

output        uart_tx;
input         uart_rx;

output        sdclk ;
inout         sdcmd ;     // mosi
inout         sddat0;     // miso
inout         sddat1;     // not use
inout         sddat2;     // not use
inout         sddat3;     // cs

output        O_tmds_clk_p ;
output        O_tmds_clk_n ;
output  [2:0] O_tmds_data_p;
output  [2:0] O_tmds_data_n;

//audio
output        HP_BCK;
output        HP_WS ;
output        HP_DIN;
output        PA_EN ;

output        O_sdram_clk  ;
output        O_sdram_cke  ;
output        O_sdram_cs_n ;
output        O_sdram_cas_n;
output        O_sdram_ras_n;
output        O_sdram_wen_n;
output [ 3:0] O_sdram_dqm  ;
output [10:0] O_sdram_addr ;
output [ 1:0] O_sdram_ba   ;
inout  [31:0] IO_sdram_dq  ;

input         spi_io_ss  ;
input         spi_io_clk ;
input         spi_io_din ;
output reg    spi_io_dout;
output        mcu_intn   ;
//------------------------------------------------------------//
assign O_sdram_dqm[ 3: 2] = 2'b11   ;
assign IO_sdram_dq[31:16] = 16'hZZZZ;
assign O_sdram_cke        = 1'b1    ;
assign PA_EN              = 1'b1    ;

assign mcu_intn = int_out_n;

//------------------------------------------------------------//
reg  [23:0]count_rst = 0                ;
wire n_all_rst       = init & (~buts[0]);
wire sys_rst         = count_rst[23]    ;
wire sys_rst_n       =~sys_rst          ;
assign leds[0]       = sys_rst_n        ;

always @(posedge clk_25 or negedge n_all_rst) count_rst <= !n_all_rst ? 24'd0 : count_rst + !count_rst[23];
//------------------------------------------------------------//
/*reg clk4_sync    = 1'b0;
reg clk4n_sync   = 1'b1;
reg clk312_sync  = 1'b0;
reg clk312n_sync = 1'b1;
reg clk_dac_sync = 1'b0;


always @(posedge clk_25)begin
        clk4_sync    <=     clk4;
        clk4n_sync   <=    ~clk4;

        clk312_sync  <= clk_3_12;
        clk312n_sync <=~clk_3_12;

        clk_dac_sync <=  clk_dac;
    end*/

wire clk4_sync   ;
wire clk4n_sync  ;
wire clk312_sync ;
wire clk312n_sync;
wire clk_dac_sync;
wire clk4n = ~clk4;
wire clk_3_12n = ~clk_3_12;

wire locked ;
wire clkram ;
wire init   ;
wire clk_50 ;
wire clk_25 ;
wire clk4   ;
wire clk_dac;
wire cpuclk_p =    clk4_sync; //clk4;
wire cpuclk_n =   clk4n_sync; //~clk4;
wire ppuclk_p =  clk312_sync;
wire ppuclk_n = clk312n_sync;

wire clk_6_25;
wire clk_3_12;

BUFG t4 (   clk4_sync,clk4     );
BUFG t4n(  clk4n_sync,clk4n    );
BUFG t3 ( clk312_sync,clk_3_12 );
BUFG t3n(clk312n_sync,clk_3_12n);
BUFG td (clk_dac_sync,clk_dac  );

wire hsync;
wire vsync;
wire visible;
wire [ 2:0] red  ;
wire [ 2:0] green;
wire [ 2:0] blue ;

sys_rpll pl1(
        .clkout (     clkram), //output clkout
        .lock   (     locked), //output lock
        .clkoutp(O_sdram_clk), //output clkoutp
        .clkoutd(       clk4), //output clkoutd
        .clkin  (      clk27)  //input clkin
    );

//------------------------------------------------------------//
// RAM cpu/ppu
//------------------------------------------------------------//
wire [15:0]addr_cpu_o;
wire [31:0]data_cpu_i;
wire [31:0]data_cpu_o;
wire       read_cpu_o;
wire       wrte_cpu_o;
wire [ 3:0]mask_cpu_o;
wire       busy_cpu_i;
wire       askn_cpu_i;

wire [15:0]addr_ppu_o;
wire [31:0]data_ppu_i;
wire [31:0]data_ppu_o;
wire       read_ppu_o;
wire       wrte_ppu_o;
wire [ 3:0]mask_ppu_o;
wire       busy_ppu_i;
wire       askn_ppu_i;
//------------------------------------------------------------//
sdram2 ram1(

   // interface to the MT48LC16M16 chip
   .SDRAM_A   (     O_sdram_addr),
   .SDRAM_DQr (IO_sdram_dq[15:0]),
   .SDRAM_BA  (       O_sdram_ba),
   .SDRAM_nCS (     O_sdram_cs_n),
   .SDRAM_nWE (    O_sdram_wen_n),
   .SDRAM_nRAS(    O_sdram_ras_n),
   .SDRAM_nCAS(    O_sdram_cas_n),
   .SDRAM_DQML(   O_sdram_dqm[0]),
   .SDRAM_DQMH(   O_sdram_dqm[1]),
   
   // cpu/chipset interface
   .clkram    (           clkram),      // sdram is accessed at up to 50MHz
   .lockclk   (           locked),
   .init      (             init),
   
   .hsync     (            hsync),
   .vsync     (            vsync),
   .visible   (          visible),
   .red       (              red),
   .green     (            green),
   .blue      (             blue),
   
   .clk_25    (           clk_25),
   .clk_50    (           clk_50),
   .clk_dac   (          clk_dac),
   
   .cpu_clk   (         clk_6_25),
   .cpu_addr  ({3'd0,addr_cpu_o}),
   .cpu_dout  (       data_cpu_i),
   .cpu_din   (       data_cpu_o),
   .cpu_dqm   (       mask_cpu_o),
   .cpu_read  (       read_cpu_o),
   .cpu_wrte  (       wrte_cpu_o),
   .cpu_busy  (       busy_cpu_i),
   .cpu_asck  (       askn_cpu_i),
   
   .ppu_clk   (         clk_3_12),
   .ppu_addr  ({3'd0,addr_ppu_o}),
   .ppu_dout  (       data_ppu_i),
   .ppu_din   (       data_ppu_o),
   .ppu_dqm   (       mask_ppu_o),
   .ppu_read  (       read_ppu_o),
   .ppu_wrte  (       wrte_ppu_o),
   .ppu_busy  (       busy_ppu_i),
   .ppu_asck  (       askn_ppu_i)
);

//------------------------------------------------------------//
//  HDMI/LCD
//------------------------------------------------------------//
wire clkpix = clkram;

wire       O_tmds_clk_p ;
wire       O_tmds_clk_n ;
wire [2:0] O_tmds_data_p;
wire [2:0] O_tmds_data_n;

wire [5:0] r_out;
wire [5:0] g_out;
wire [5:0] b_out;

reg  I_rgb_vs = 1'b0;
reg  I_rgb_hs = 1'b0;
reg  I_rgb_de = 1'b0;
reg  [7:0] I_rgb_r = 8'd0;
reg  [7:0] I_rgb_g = 8'd0;
reg  [7:0] I_rgb_b = 8'd0;

always @(posedge clkpix)begin
        I_rgb_vs <= vsync;
        I_rgb_hs <= hsync;
        I_rgb_de <= visible;
        I_rgb_r  <= {r_out,2'd0};
        I_rgb_g  <= {g_out,2'd0};
        I_rgb_b  <= {b_out,2'd0};
    end

dvi_tx hdmi1(
    .I_rst_n      (         1'b1), //input I_rst_n
    .I_rgb_clk    (       clkpix), //input I_rgb_clk
    .I_rgb_vs     (     I_rgb_vs), //input I_rgb_vs
    .I_rgb_hs     (     I_rgb_hs), //input I_rgb_hs
    .I_rgb_de     (     I_rgb_de), //input I_rgb_de
    .I_rgb_r      (     I_rgb_r ), //input [7:0] I_rgb_r
    .I_rgb_g      (     I_rgb_g ), //input [7:0] I_rgb_g
    .I_rgb_b      (     I_rgb_b ), //input [7:0] I_rgb_b
    .O_tmds_clk_p ( O_tmds_clk_p), //output O_tmds_clk_p
    .O_tmds_clk_n ( O_tmds_clk_n), //output O_tmds_clk_n
    .O_tmds_data_p(O_tmds_data_p), //output [2:0] O_tmds_data_p
    .O_tmds_data_n(O_tmds_data_n)  //output [2:0] O_tmds_data_n
);
//------------------------------------------------------------//
//  Mister zone
//------------------------------------------------------------//
// byte interface to the various core components
wire        mist_clk = clk_25;
wire        mcu_sys_strobe;
wire        mcu_hid_strobe;
wire        mcu_osd_strobe;
wire        mcu_sdc_strobe;
wire        mcu_start     ;
wire  [7:0] mcu_sys_din   ;
wire  [7:0] mcu_hid_din   ;
wire  [7:0] mcu_osd_din = 8'h55;
wire  [7:0] mcu_sdc_din   ;
wire  [7:0] mcu_dout      ;
wire        hid_int       ;
wire        sdc_int       ;
wire  [7:0] int_ack       ;

mcu_spi msp1(
    .clk           (      mist_clk),
    .reset         (     sys_rst_n),

  // SPI interface to MCU
    .spi_io_ss     (   spi_io_ss  ),
    .spi_io_clk    (   spi_io_clk ),
    .spi_io_din    (   spi_io_din ),
    .spi_io_dout   (   spi_io_dout),

  // byte interface to the various core components
    .mcu_sys_strobe(mcu_sys_strobe), // byte strobe for system control target  
    .mcu_hid_strobe(mcu_hid_strobe), // byte strobe for HID target  
    .mcu_osd_strobe(mcu_osd_strobe), // byte strobe for OSD target
    .mcu_sdc_strobe(mcu_sdc_strobe), // byte strobe for SD card target
    .mcu_start     (   mcu_start  ),
    .mcu_sys_din   (   mcu_sys_din),
    .mcu_hid_din   (   mcu_hid_din),
    .mcu_osd_din   (   mcu_osd_din),
    .mcu_sdc_din   (   mcu_sdc_din),
    .mcu_dout      (   mcu_dout   )
);

wire        system_video       ;
wire [1:0]  system_reset       ;
wire [1:0]  system_volume      ;
wire [3:0]  system_floppy_wprot;
wire [23:0] color              ;
wire [ 1:0] leds_n             ;

sysctrl sctl1(
    .clk                (           mist_clk),
    .reset              (          sys_rst_n),

    .data_in_strobe     (     mcu_sys_strobe),
    .data_in_start      (          mcu_start),
    .data_in            (           mcu_dout),
    .data_out           (        mcu_sys_din),

  // interrupt interface
    .int_out_n          (          int_out_n),
    .int_in({ 4'b0000, sdc_int, 1'b0, hid_int, 1'b0 }),
    .int_ack            (            int_ack),

    .buttons            (              2'b00), // S0 and S1 buttons on Tang Nano 20k

    .leds               (             leds_n), // two leds can be controlled from the MCU
    .color              (              color), // a 24bit color to e.g. be used to drive the ws2812

  // values that can be configured by the user
    .system_video       (       system_video),
    .system_reset       (       system_reset),
    .system_volume      (      system_volume),
    .system_floppy_wprot(system_floppy_wprot)
);

wire [5:0] db9_port = 6'd0;
wire [7:0] keycode  ;
wire [5:0] hid_mouse;   // USB/HID mouse with four directions and two buttons
wire [7:0] hid_joy  ;   // USB/HID joystick with four directions and four buttons

hid hd1(
    .clk           (      mist_clk),
    .reset         (     sys_rst_n),

    .data_in_strobe(mcu_hid_strobe),
    .data_in_start (     mcu_start),
    .data_in       (      mcu_dout),
    .data_out      (   mcu_hid_din),

// input local db9 port events to be sent to MCU
    .db9_port      (      db9_port),
    .irq           (       hid_int),
    .iack          (    int_ack[1]),

// output HID data received from USB
    .mouse         (     hid_mouse),
    .keyboard      (       keycode),
    .joystick0     (       hid_joy),
    .joystick1     (              )
);


wire [31:0] sd_img_size   ;
wire [ 3:0] sd_img_mounted;
wire sdc_iack = int_ack[3];
wire        sd_busy       ;
wire        sd_done       ;
wire        sd_rd_byte_strobe;
wire [ 8:0] sd_byte_index ;
wire [ 7:0] sd_rd_data    ;
wire [ 7:0] sd_wr_data    ;
wire [ 3:0] sd_rd         ;
wire [ 3:0] sd_wr         ;
wire [31:0] sd_sector     ;

sd_card #(
    .CLK_DIV(3'd1)                        // for 25 Mhz clock
) sd_card (
    .rstn(  sys_rst),                     // rstn active-low, 1:working, 0:reset
    .clk ( mist_clk),                     // clock
  
    // SD card signals
    .sdclk(   sdclk),
    .sdcmd(   sdcmd),
    .sddat({sddat3,sddat2,sddat1,sddat0}),

    // mcu interface
    .data_strobe(mcu_sdc_strobe),
    .data_start (     mcu_start),
    .data_in    (      mcu_dout),
    .data_out   (   mcu_sdc_din),

    // output file/image information. Image size is e.g. used by fdc to 
    // translate between sector/track/side and lba sector
    .image_size   (   sd_img_size),           // length of image file
    .image_mounted(sd_img_mounted),

    // interrupt to signal communication request
    .irq    (  sdc_int),
    .iack   ( sdc_iack),

    // user read sector command interface (sync with clk32)
    .rstart (    sd_rd), 
    .wstart (    sd_wr), 
    .rsector(sd_sector),
    .rbusy  (  sd_busy),
    .rdone  (  sd_done),

    // sector data output interface (sync with clk32)
    .inbyte (       sd_wr_data),
    .outen  (sd_rd_byte_strobe),   // when outen=1, a byte of sector content is read out from outbyte
    .outaddr(    sd_byte_index),   // outaddr from 0 to 511, because the sector size is 512
    .outbyte(       sd_rd_data)    // a byte of sector content
);

reg [3:0]mount_dsk = 4'b0000;
always @(posedge sd_img_mounted[0])mount_dsk[0]<= !sd_img_size ? 1'b0 : 1'b1;
always @(posedge sd_img_mounted[1])mount_dsk[1]<= !sd_img_size ? 1'b0 : 1'b1;
always @(posedge sd_img_mounted[2])mount_dsk[2]<= !sd_img_size ? 1'b0 : 1'b1;
always @(posedge sd_img_mounted[3])mount_dsk[3]<= !sd_img_size ? 1'b0 : 1'b1;

assign leds[4] = ~mount_dsk[0];


wire [ 2:0] red_m   = system_video ? green : red  ;
wire [ 2:0] green_m = system_video ? red   : green;


osd_u8g2 osd1(
    .clk           (      mist_clk),

    .pclk          (      mist_clk),
    .reset         (     sys_rst_n),

    .data_in_strobe(mcu_osd_strobe),
    .data_in_start (     mcu_start),
    .data_in       (      mcu_dout),

    .hs            (         hsync),
    .vs            (         vsync),
    .r_in          (  {red_m,3'd0}),
    .g_in          ({green_m,3'd0}),
    .b_in          (   {blue,3'd0}),

    .r_out         (         r_out),
    .g_out         (         g_out),
    .b_out         (         b_out)
);
//------------------------------------------------------------//
//  Wishbone PPU
//------------------------------------------------------------//
wire       ppu_vm_clk_p;

wire       ppu_vm_init_o;
wire       ppu_vm_dclo_o;
wire       ppu_vm_aclo_o;

wire       ppu_vm_virq_i;

wire [16:0]ppu_wbm_adr_o;
wire [15:0]ppu_wbm_dat_o;
wire [15:0]ppu_wbm_dat_i;
wire       ppu_wbm_cyc_o;
wire       ppu_wbm_wre_o;
wire [ 1:0]ppu_wbm_sel_o;
wire       ppu_wbm_stb_o;
wire       ppu_wbm_ack_i;
wire [15:0]ppu_wbi_dat_i;
wire       ppu_wbi_ack_i;
wire       ppu_wbi_stb_o;


// vp1-120
wire       ppu_vm_virq_i_vp;

wire [15:0]ppu_wbm_dat_i_vp;

wire       ppu_wbm_ack_i_vp;
wire [15:0]ppu_wbi_dat_i_vp;
wire       ppu_wbi_ack_i_vp;

wire       pin_tmr_ena_o;
// vp1-128
wire [15:0]ppu_wbm_dat_i_128;
wire       ppu_wbm_ack_i_128;

wire       wite_clk_128;
wire       motor_on_128;
//xm2-01
wire [15:0]ppu_wbm_dat_i_xm2;
wire       ppu_vm_virq_i_xm2;
wire       ppu_wbm_ack_i_xm2;

wire [15:0]ppu_wbi_dat_i_xm2;
wire       ppu_wbi_ack_i_xm2;
wire       ppu_wbi_stb_o_xm2;

//aberrant
wire [15:0]ppu_wbm_dat_i_abr;
wire       ppu_wbm_ack_i_abr;


assign ppu_vm_virq_i = ppu_vm_virq_i_xm2|ppu_vm_virq_i_vp;

assign ppu_wbm_dat_i = ppu_wbm_ack_i_xm2 ? ppu_wbm_dat_i_xm2 :
                       ppu_wbm_ack_i_vp  ? ppu_wbm_dat_i_vp  :
                       ppu_wbm_ack_i_128 ? ppu_wbm_dat_i_128 : 
                       ppu_wbm_ack_i_abr ? ppu_wbm_dat_i_abr : 16'o0;

assign ppu_wbm_ack_i = ppu_wbm_ack_i_xm2|ppu_wbm_ack_i_vp|ppu_wbm_ack_i_128|ppu_wbm_ack_i_abr;

assign ppu_wbi_dat_i = ppu_wbi_ack_i_xm2 ? ppu_wbi_dat_i_xm2 :
                       ppu_wbi_ack_i_vp  ? ppu_wbi_dat_i_vp  : 16'o0;
assign ppu_wbi_ack_i = ppu_wbi_ack_i_xm2 | ppu_wbi_ack_i_vp;

//assign leds[4] = ~pin_tmr_ena_o;
//------------------------------------------------------------//
//  Wishbone CPU
//------------------------------------------------------------//
wire [15:0]vp65_wbm_dat_i;
wire [15:0]vp65_wbi_dat_i;
wire       vp65_vm_virq_i;
wire       vp65_wbm_ack_i;
wire       vp65_wbi_ack_i;
wire       vp65_wbi_stb_i;
//--------------------------------------------
wire       cpu_vm_init_o;
wire       cpu_vm_dclo_i;
wire       cpu_vm_aclo_i;
wire       pin_vm_halt_i;

wire       cpu_vm_virq_i = cpu_vm_virq_i_vp|vp65_vm_virq_i;

wire [16:0]cpu_wbm_adr_o;
wire [15:0]cpu_wbm_dat_o;
wire [15:0]cpu_wbm_dat_i = cpu_wbm_ack_i_vp ? cpu_wbm_dat_i_vp : 
                           vp65_wbm_ack_i   ? vp65_wbm_dat_i   : 16'o0;
wire       cpu_wbm_cyc_o;
wire       cpu_wbm_wre_o;
wire [ 1:0]cpu_wbm_sel_o;
wire       cpu_wbm_stb_o;
wire       cpu_wbm_ack_i = cpu_wbm_ack_i_vp|vp65_wbm_ack_i;

wire [15:0]cpu_wbi_dat_i = cpu_wbi_ack_i_vp ? cpu_wbi_dat_i_vp : 
                           vp65_wbi_ack_i   ? vp65_wbi_dat_i   : 16'o0;

wire       cpu_wbi_ack_i = cpu_wbi_ack_i_vp|vp65_wbi_ack_i;
wire       cpu_wbi_stb_o;


// vp1-120
wire       cpu_vm_virq_i_vp;

wire [15:0]cpu_wbm_dat_i_vp;

wire       cpu_wbm_ack_i_vp;
wire [15:0]cpu_wbi_dat_i_vp;
wire       cpu_wbi_ack_i_vp;
//------------------------------------------------------------//
wire pp_rst = system_reset[0];//~sys_rst;
ppu_wb ppu1(
   .clk_ppu_p    (     ppuclk_p),
   .clk_ppu_n    (     ppuclk_n),
   .rst          (       pp_rst),
   .clk50hz      (        vsync),

   .addr_ram     (   addr_ppu_o),
   .duot_ram     (   data_ppu_o),
   .dinp_ram     (   data_ppu_i),
   .mask_ram     (   mask_ppu_o),
   .read_ram     (   read_ppu_o),
   .wrte_ram     (   wrte_ppu_o),
   .askn_ram     (   askn_ppu_i),

   .pin_vm_init_o(ppu_vm_init_o),
   .pin_vm_dclo_o(ppu_vm_dclo_o),
   .pin_vm_aclo_o(ppu_vm_aclo_o),

   .pin_vm_virq_i(ppu_vm_virq_i),

   .pin_wbm_adr_o(ppu_wbm_adr_o),
   .pin_wbm_dat_o(ppu_wbm_dat_o),
   .pin_wbm_dat_i(ppu_wbm_dat_i),
   .pin_wbm_cyc_o(ppu_wbm_cyc_o),
   .pin_wbm_wre_o(ppu_wbm_wre_o),
   .pin_wbm_sel_o(ppu_wbm_sel_o),
   .pin_wbm_stb_o(ppu_wbm_stb_o),
   .pin_wbm_ack_i(ppu_wbm_ack_i),
   .pin_wbi_dat_i(ppu_wbi_dat_i),
   .pin_wbi_ack_i(ppu_wbi_ack_i),
   .pin_wbi_stb_o(ppu_wbi_stb_o),

   .pin_tmr_ena_o(pin_tmr_ena_o)
);
//------------------------------------------------------------//
wire sound;

assign leds[1] = ~sound;

xm2_01 dd1(
   .pin_vm_clk25 (           clk_25),
   .pin_vm_clk_p (         ppuclk_n),

   .pin_vm_init_i(    ppu_vm_init_o),

   .pin_vm_virq_o(ppu_vm_virq_i_xm2),

   .pin_wbm_adr_i(    ppu_wbm_adr_o),
   .pin_wbm_dat_i(    ppu_wbm_dat_o),
   .pin_wbm_dat_o(ppu_wbm_dat_i_xm2),

   .pin_wbm_wre_i(    ppu_wbm_wre_o),

   .pin_wbm_stb_i(    ppu_wbm_stb_o),
   .pin_wbm_ack_o(ppu_wbm_ack_i_xm2),

   .pin_wbi_dat_o(ppu_wbi_dat_i_xm2),
   .pin_wbi_ack_o(ppu_wbi_ack_i_xm2),
   .pin_wbi_stb_i(    ppu_wbi_stb_o),

   .pin_vm_dclo_o(    cpu_vm_dclo_i),
   .pin_vm_aclo_o(    cpu_vm_aclo_i),
   .pin_vm_halt_o(    pin_vm_halt_i),

   .pin_wbi_stb_o(ppu_wbi_stb_o_xm2),

   .but_data     (          keycode),

   .sound        (            sound)
);

assign leds[3:2] = {cpu_vm_dclo_i,cpu_vm_aclo_i};
//--------------------------------------------
wire [15:0] disk_data_out;
wire [15:0] disk_data_in ;
wire [ 1:0] disk_drive   ;
wire        disk_valid   ;
wire        disk_sync    ;
wire        disk_crc_ok  ;
wire        disk_rdy     ;
wire        disk_tr0     ;
wire        disk_ind     ;
wire        disk_motor   ;
wire        disk_step    ;
wire        disk_dir     ;
wire        disk_head    ;
wire        disk_write   ;

fdd4 fdd(
    .pin_25mhz_ck (       clk_25),
    .ppu_vm_init_i(ppu_vm_init_o),

    .data_in      ( disk_data_in),
    .data_out     (disk_data_out),
    .write        (   disk_write),

    .drive        (   disk_drive),
    .motor        (   disk_motor),
    .step         (    disk_step),
    .dir          (     disk_dir),
    .head         (    disk_head),
    .valid        (   disk_valid),
    .sync         (    disk_sync),
    .crc_ok       (  disk_crc_ok),
    .rdy          (     disk_rdy),
    .tr0          (     disk_tr0),
    .ind          (     disk_ind),

    .led_init     (      leds[5]),
   
    .rstart       (        sd_rd),
    .wstart       (        sd_wr),
    .rsector      (    sd_sector),
    .rbusy        (      sd_busy),
    .rdone        (      sd_done),

    .outen    (sd_rd_byte_strobe),
    .outaddr      (sd_byte_index),
    .inbyte       (   sd_rd_data),
    .outbyte      (   sd_wr_data),
    .mount_dsk    (    mount_dsk)
);

vp1_128fdd vp128(
    .ppu_vm_clk_p (         ppuclk_n),

    .ppu_vm_init_i(    ppu_vm_init_o),

    .ppu_wbm_adr_i(    ppu_wbm_adr_o),
    .ppu_wbm_dat_i(    ppu_wbm_dat_o),
    .ppu_wbm_dat_o(ppu_wbm_dat_i_128),
    .ppu_wbm_cyc_i(    ppu_wbm_cyc_o),
    .ppu_wbm_wre_i(    ppu_wbm_wre_o),
    .ppu_wbm_stb_i(    ppu_wbm_stb_o),
    .ppu_wbm_ack_o(ppu_wbm_ack_i_128),

    .data_in      (    disk_data_out),
    .data_out     (     disk_data_in),
    .write        (       disk_write),

    .drive        (       disk_drive),
    .motor        (       disk_motor),
    .step         (        disk_step),
    .dir          (         disk_dir),
    .head         (        disk_head),
    .valid        (       disk_valid),
    .sync         (        disk_sync),
    .crc_ok       (      disk_crc_ok),
    .rdy          (         disk_rdy),
    .tr0          (         disk_tr0),
    .ind          (         disk_ind),
    .wrprt_dsk    (system_floppy_wprot)
);
//------------------------------------------------------------//
wire [10:0] left_channel ;
wire [10:0] right_channel;
wire [11:0] mono_channel ;

aberrant ay1(
   .ppu_vm_clk_p (         ppuclk_n),

   .ppu_vm_init_i(    ppu_vm_init_o),

   .ppu_wbm_adr_i(    ppu_wbm_adr_o),
   .ppu_wbm_dat_i(    ppu_wbm_dat_o),
   .ppu_wbm_dat_o(ppu_wbm_dat_i_abr),
   .ppu_wbm_cyc_i(    ppu_wbm_cyc_o),
   .ppu_wbm_wre_i(    ppu_wbm_wre_o),
   .ppu_wbm_sel_o(    ppu_wbm_sel_o),
   .ppu_wbm_stb_i(    ppu_wbm_stb_o),
   .ppu_wbm_ack_o(ppu_wbm_ack_i_abr),

   .l_channel    (     left_channel),
   .r_channel    (    right_channel),
   .m_channel    (     mono_channel)
);
//------------------------------------------------------------//
cpu_wb cpu1(
   .clk_ppu_p    (     cpuclk_p),
   .clk_ppu_n    (     cpuclk_n),
   .clk50hz      (        vsync),

   .addr_ram     (   addr_cpu_o),
   .duot_ram     (   data_cpu_o),
   .dinp_ram     (   data_cpu_i),
   .mask_ram     (   mask_cpu_o),
   .read_ram     (   read_cpu_o),
   .wrte_ram     (   wrte_cpu_o),
   .askn_ram     (   askn_cpu_i),

   .pin_vm_init_o(cpu_vm_init_o),
   .pin_vm_dclo_i(cpu_vm_dclo_i),
   .pin_vm_aclo_i(cpu_vm_aclo_i),
   .pin_vm_halt_i(pin_vm_halt_i),

   .pin_vm_virq_i(cpu_vm_virq_i),

   .pin_wbm_adr_o(cpu_wbm_adr_o),
   .pin_wbm_dat_o(cpu_wbm_dat_o),
   .pin_wbm_dat_i(cpu_wbm_dat_i),
   .pin_wbm_cyc_o(cpu_wbm_cyc_o),
   .pin_wbm_wre_o(cpu_wbm_wre_o),
   .pin_wbm_sel_o(cpu_wbm_sel_o),
   .pin_wbm_stb_o(cpu_wbm_stb_o),
   .pin_wbm_ack_i(cpu_wbm_ack_i),
   .pin_wbi_dat_i(cpu_wbi_dat_i),
   .pin_wbi_ack_i(cpu_wbi_ack_i),
   .pin_wbi_stb_o(cpu_wbi_stb_o),

   .pin_tmr_ena_i(pin_tmr_ena_o)
);
//------------------------------------------------------------//
wire cpu_wbi_stb_o_vp1; // not use
wire [7:0] covox;

vp1_120 vp1
(
    .clk          (           clk_25),

    .cpu_vm_init_i(    cpu_vm_init_o),

    .cpu_vm_virq_o( cpu_vm_virq_i_vp),

    .cpu_wbm_adr_i(    cpu_wbm_adr_o),
    .cpu_wbm_dat_i(    cpu_wbm_dat_o),
    .cpu_wbm_dat_o( cpu_wbm_dat_i_vp),
    .cpu_wbm_cyc_i(    cpu_wbm_cyc_o),
    .cpu_wbm_wre_i(    cpu_wbm_wre_o),
    .cpu_wbm_sel_i(    cpu_wbm_sel_o),
    .cpu_wbm_stb_i(    cpu_wbm_stb_o),
    .cpu_wbm_ack_o( cpu_wbm_ack_i_vp),
    .cpu_wbi_dat_o( cpu_wbi_dat_i_vp),
    .cpu_wbi_ack_o( cpu_wbi_ack_i_vp),
    .cpu_wbi_stb_i(    cpu_wbi_stb_o),

    .cpu_wbi_stb_o(cpu_wbi_stb_o_vp1),

//--------------------------------------------

    .ppu_vm_init_i(    ppu_vm_init_o),

    .ppu_vm_virq_o( ppu_vm_virq_i_vp),

    .ppu_wbm_adr_i(    ppu_wbm_adr_o),
    .ppu_wbm_dat_i(    ppu_wbm_dat_o),
    .ppu_wbm_dat_o( ppu_wbm_dat_i_vp),
    .ppu_wbm_cyc_i(    ppu_wbm_cyc_o),
    .ppu_wbm_wre_i(    ppu_wbm_wre_o),
    .ppu_wbm_sel_i(    ppu_wbm_sel_o),
    .ppu_wbm_stb_i(    ppu_wbm_stb_o),
    .ppu_wbm_ack_o( ppu_wbm_ack_i_vp),
    .ppu_wbi_dat_o( ppu_wbi_dat_i_vp),
    .ppu_wbi_ack_o( ppu_wbi_ack_i_vp),
    .ppu_wbi_stb_i(ppu_wbi_stb_o_xm2),

    .ppu_wbi_stb_o()
);

//------------------------------------------------------------//
vp065 dd2(
   .pin_50MHz_clk(           clk_50),
   .pin_vm_clk_p (         cpuclk_n),

   .pin_vm_init_i(    cpu_vm_init_o),

   .pin_vm_virq_o(   vp65_vm_virq_i),

   .pin_wbm_adr_i(    cpu_wbm_adr_o),
   .pin_wbm_dat_i(    cpu_wbm_dat_o),
   .pin_wbm_dat_o(   vp65_wbm_dat_i),
   .pin_wbm_wre_i(    cpu_wbm_wre_o),
   .pin_wbm_stb_i(    cpu_wbm_stb_o),
   .pin_wbm_ack_o(   vp65_wbm_ack_i),
   .pin_wbi_dat_o(   vp65_wbi_dat_i),
   .pin_wbi_ack_o(   vp65_wbi_ack_i),
   .pin_wbi_stb_i(cpu_wbi_stb_o_vp1),

   .pin_wbi_stb_o(   vp65_wbi_stb_i),

   .pin_tx_o     (          uart_tx),
   .pin_rx_i     (          uart_rx),
   .pin_ac_o     (                 )
);
//------------------------------------------------------------//
reg  [15:0] volume_data = 16'd0;

always @(*)
    case(system_volume)
    'b00 : volume_data <= 16'd0;
    'b01 : volume_data <= ({2'd0, mono_channel, 2'd0}+{4'd0, sound, 11'd0});
    'b10 : volume_data <= ({2'd0, mono_channel, 2'd0}+{4'd0, sound, 11'd0})<<1;
    'b11 : volume_data <= ({2'd0, mono_channel, 2'd0}+{4'd0, sound, 11'd0})<<2;
    endcase
//------------------------------------------------------------//
wire [15:0] data_aud  ;
wire        isread_aud;
wire        Empty_aud ;
wire        Full_aud  ;

fifo_audio abf1(
    .Data (volume_data),
    .WrClk(   ppuclk_p),
    .RdClk( isread_aud),
    .WrEn (       1'b1),
    .RdEn (       1'b1),
    .Q    (   data_aud),
    .Empty(  Empty_aud),
    .Full (   Full_aud)
);

audio_drive ad1(
    .clk_1p536m(  ppuclk_p),
    .rst_n     (   sys_rst),

    .idata     (  data_aud),
    .req       (isread_aud), /// fifo_empty/fifo_rd

    .HP_BCK    (    HP_BCK),
    .HP_WS     (     HP_WS),
    .HP_DIN    (    HP_DIN)
);
//------------------------------------------------------------//
endmodule