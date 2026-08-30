/*
IO_LOC "HP_BCK" 71;
IO_PORT "HP_BCK" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "HP_WS" 72;
IO_PORT "HP_WS" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "HP_DIN" 73;
IO_PORT "HP_DIN" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "PA_EN" 74;
IO_PORT "PA_EN" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
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

    m0s
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

// MCU link, wired as MiSTeryNano wires it: an external BL616 / M0S Dock on
// the m0s bus, and nothing else.  MiSTeryNano can also talk to the Tang
// Nano 20k's own on-board BL616 over 86/13/76/75/69 and this core did
// briefly, but that link needs pin 69 for its interrupt and 69 is the
// FPGA's TX into that same BL616 - the USB-C serial console.  The console
// is worth more here than an untested second attachment, so the internal
// path is gone.
inout  [ 4:0] m0s        ;  // 0 miso, 1 mosi, 2 csn, 3 sclk, 4 irqn
//------------------------------------------------------------//
assign O_sdram_dqm[ 3: 2] = 2'b11   ;
assign IO_sdram_dq[31:16] = 16'hZZZZ;
assign O_sdram_cke        = 1'b1    ;
assign PA_EN              = 1'b1    ;

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

// Gowin's dvi_tx is DVI, so it has no data islands and can carry no
// sound.  hdmi_tx is the same job with them, and hdmi_serdes is the part
// that touches Gowin primitives.  src/ip/dvi_tx is still in the project
// and uninstantiated; putting it back is this instance and nothing else.
wire [9:0] tmds_ch0, tmds_ch1, tmds_ch2;
wire       hdmi_audio_ovf;
wire [15:0] hdmi_audio_dropc;
wire [15:0] hdmi_audio_pktc;
// The samples come from the volume stage further down; they are picked up
// through these two wires so that block can stay where the author put it.
wire [15:0] hdmi_audio_l;
wire [15:0] hdmi_audio_r;

hdmi_tx hdmi1(
    .I_rst_n      (         1'b1),
    .I_rgb_clk    (       clkpix),
    .I_rgb_vs     (     I_rgb_vs),
    .I_rgb_hs     (     I_rgb_hs),
    .I_rgb_de     (     I_rgb_de),
    .I_rgb_r      (     I_rgb_r ),
    .I_rgb_g      (     I_rgb_g ),
    .I_rgb_b      (     I_rgb_b ),
  // the same words the I2S gets, resampled there to exactly 48 kHz
    .I_audio_l    ( hdmi_audio_l),
    .I_audio_r    ( hdmi_audio_r),
    .O_tmds_ch0   (     tmds_ch0),
    .O_tmds_ch1   (     tmds_ch1),
    .O_tmds_ch2   (     tmds_ch2),
    .O_audio_ovf  (hdmi_audio_ovf),
    .O_audio_dropc(hdmi_audio_dropc),
    .O_audio_pktc (hdmi_audio_pktc)
);

hdmi_serdes hdmi_ser(
    .clk_pixel    (       clkpix),
    .tmds_ch0     (     tmds_ch0),
    .tmds_ch1     (     tmds_ch1),
    .tmds_ch2     (     tmds_ch2),
    .O_tmds_clk_p ( O_tmds_clk_p),
    .O_tmds_clk_n ( O_tmds_clk_n),
    .O_tmds_data_p(O_tmds_data_p),
    .O_tmds_data_n(O_tmds_data_n)
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

//------------------------------------------------------------//
//  The MCU bus
//------------------------------------------------------------//
// One attachment, so there is nothing to select between: miso and irqn are
// the FPGA's outputs onto the bus, the other three are its inputs off it.
// The dock needs no build option and no jumper.
wire        spi_io_dout;
wire        int_out_n  ;

assign m0s[4:0] = { int_out_n, 3'bzzz, spi_io_dout };

wire spi_io_din = m0s[1];
wire spi_io_ss  = m0s[2];
wire spi_io_clk = m0s[3];

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
wire [11:0] mono_channel ;   // driven by aberrant, no longer mixed - the
                             // audio path is stereo now.  Left connected
                             // because it is what a mono menu option would
                             // use, not because anything reads it today.

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
// The UKNC's own C2 serial port.  It does not reach pin 69 any more - the
// diagnostic monitor below has the line; see there.
wire vp65_uart_tx;

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

   .pin_tx_o     (     vp65_uart_tx),
   .pin_rx_i     (          uart_rx),
   .pin_ac_o     (                 )
);
//------------------------------------------------------------//
// The mixer.
//
// One level, one sum, and the volume control only makes it quieter.
//
// It used to pan the AYs ABC - A to the left, C to the right, B split -
// and then scale by SHIFTING UP, so 100% multiplied by four and the result
// had to be clamped.  That made the volume setting change WHAT you could
// hear rather than how loudly: at full volume anything past a third of the
// AY's range clamped flat and went quiet, and a chip feeding mostly one
// side was audible at one setting and not at another.
//
// The real module sums A, B and C of each chip at the same level, sums the
// three chips, and drives one output.  aberrant.v already computes exactly
// that as m_channel - all nine channels added - and it was the output
// nothing read.  The beeper joins it, and the one sum goes to both sides.
//
// Headroom, so nothing ever clips: m_channel is 12 bits and reaches
// 9 * 255 = 2295, which shifted up three is 18360, and the beeper adds
// 4096.  The total is 22456, comfortably inside the 32767 a signed sample
// allows - so full volume is the unattenuated sum and the quieter settings
// divide down from it.  No saturation is needed and none is done.
wire [15:0] ay_mix = {1'd0, mono_channel, 3'd0};   // 0..18360
wire [15:0] beeper = {2'd0, sound, 13'd0};         // 0 or 8192
wire [15:0] mix    = ay_mix + beeper;              // 0..34744, clip() catches
                                                  // the corner where three
                                                  // chips and the beeper all
                                                  // peak at once

// DC blocker.
//
// Every AY channel is UNIPOLAR - it sits between 0 and 255 and never goes
// negative - so the sum of nine of them carries a large steady offset, and
// so does the beeper, which is 0 or 4096.  On the real module a coupling
// capacitor takes that out before the amplifier.  Here it went into the
// sample, and a television meets it as DC on its speaker amplifier: the
// offset grows with the volume setting, so two-thirds distorts and full
// volume trips the protection and mutes.  That is why the mix sounded
// clean quiet, overloaded louder, and vanished at 100%, while the peak
// never came near the 32767 a signed sample allows.
//
// One pole, the digital equivalent of that capacitor.  dc_acc holds the
// running mean in 18.15 fixed point; at the 3.1339 MHz PPU clock a shift
// of 15 puts the corner at 3.1339e6 / (2*pi*2^15) = 15 Hz, well below
// anything the machine plays and slow enough not to chase the waveform.
localparam integer DCB = 15;

reg  signed [33:0] dc_acc = 34'sd0;
wire signed [17:0] dc_x    = $signed({2'b00, mix});
wire signed [17:0] dc_mean = dc_acc[32:15];
wire signed [17:0] dc_out  = dc_x - dc_mean;

always @(posedge ppuclk_p) dc_acc <= dc_acc + dc_out;

// The result is centred on zero and swings about +/-22456 at worst, inside
// a signed sample, but the clamp catches the settling transient after a
// reset rather than letting it wrap.
function signed [15:0] clip;
    input signed [17:0] v;
    clip = (v >  18'sd32767) ?  16'sh7FFF :
           (v < -18'sd32767) ? -16'sh7FFF : v[15:0];
endfunction

// Button S2 bypasses the blocker, so one bitstream carries both answers:
// dc_x is the raw unipolar sum, bit for bit what the build before this one
// sent, and dc_out is that sum with the mean taken out.  Which one is in
// use is reported in the diagnostic line, so the two can be told apart
// from the serial rather than from memory.
//
// The buttons read 0 released and 1 pressed, whatever PULL_MODE=UP in the
// .cst suggests - n_all_rst above only makes sense that way round, since
// pressing S1 has to be what forces a reset.  So released is the design as
// it stands and S2 held is the sound of the build before it.
// The raw unipolar sum is the design.  The DC blocker stays in the source
// and out of the path, on S2, because it may yet be right for some other
// sink - but it is not right for this one, and the reason is measured.
//
// Four states were put on the board, each differing from the working one
// in a single property:
//
//   raw sum, 0..N, quiescent exactly 0        PLAYS
//   raw sum minus a constant 512              silent - dips below zero
//   DC blocked, bipolar, quiescent 0          silent - dips below zero
//   DC blocked plus 8192, never negative      silent - permanent offset
//
// The third and fourth have identical AC content and comparable amplitude
// to the first; the wire carried a clean 8192 +/- 580 that the sink
// ignored while it played 510 +/- 510 from the raw path.  So it is not
// amplitude, and the last test settles the rest: subtracting 512 changes
// nothing but the sign of the troughs and it silences everything.
//
// Which leaves the obvious thing we were solving a problem the hardware
// already solves.  A real MC0511 drives a unipolar sum through a coupling
// capacitor, and a television has one too; blocking the DC digitally was
// doing the capacitor's job badly and in front of a sink that will not
// take the result.  The one defect that remains is the blocker's original
// motive - the mean steps with the program material - and it is contained
// by keeping the beeper at 8192 rather than 16384, which is the level that
// tested clean at 66% and 100%.
wire signed [17:0] dc_amp = buts[1] ? dc_out : dc_x;

// REGISTERED, and that is the whole fix, not a tidy-up.
//
// This was a combinational always @(*), and hdmi_tx latches it at the
// audio sample instant - an instant with no relation to the PPU clock the
// mixer runs on.  So the encoder could take the value while the adders
// were still settling and send a carry-chain intermediate as a sample.
//
// Nothing in the diagnostics could see it: the probes sample these same
// wires on posedge ppuclk_p, when everything has settled, so they reported
// a clean +/-3300 waveform while the sink was being fed spikes.  What gave
// it away was the board: with the blocker bypassed and the volume low the
// AY played, and it went silent as soon as either the DC blocker (a 34-bit
// accumulator, an 18-bit subtract and a clip behind the sample) or full
// volume was in the path.  Depth of logic, not level of signal.
//
// It was consistent rather than intermittent because the old divider took
// a sample every 1024 pixel clocks and ppuclk_p is clkram/16: 1024 = 64*16,
// so the sample instant sat at ONE fixed phase of the PPU clock forever.
// Land that phase in the settling window and every sample is wrong, every
// time, which reads as a dead audio path rather than as noise.
//
// A register makes the sample a settled value by construction, whatever
// the phase.  It costs one PPU clock of latency, 320 ns.
reg  [15:0] volume_data_l = 16'd0;
reg  [15:0] volume_data_r = 16'd0;

always @(posedge ppuclk_p)
    case(system_volume)
    'b00 : begin volume_data_l <= 16'd0;              volume_data_r <= 16'd0;              end
    'b01 : begin volume_data_l <= clip(dc_amp >>> 2); volume_data_r <= clip(dc_amp >>> 2); end
    'b10 : begin volume_data_l <= clip(dc_amp >>> 1); volume_data_r <= clip(dc_amp >>> 1); end
    'b11 : begin volume_data_l <= clip(dc_amp);       volume_data_r <= clip(dc_amp);       end
    endcase
// The HDMI side takes the same post-volume words, and resamples them to
// exactly 48 kHz with a phase accumulator - see src/hdmi/hdmi_tx.v.  It does not go through the FIFO
// below: that one is clocked by the I2S bit rate and is a different rate
// entirely.
assign hdmi_audio_l = volume_data_l;
assign hdmi_audio_r = volume_data_r;

//------------------------------------------------------------//
// Board diagnostics.
//
// Everything about a fault on this design has had to be inferred from a
// picture and a loudspeaker, and the guesses that came out of that have
// been wrong often enough to be expensive.  The serial console is the one
// channel that can carry a number off a running board: uart_tx is pin 69
// into the Tang's own BL616, which the host sees as /dev/ttyUSB1.  So the
// monitor takes the line - vp65_uart_tx, the UKNC's own port, goes
// nowhere, which costs nothing because no software here uses it, and
// putting it back is the one assign at the end of this block.
//
// The events come off the PPU bus rather than out of the modules, so
// neither xm2-01 nor aberrant had to be touched to be watched: a write
// aberrant acked is an AY write, a write at 0177716 that xm2-01 acked is
// the beeper register.  That also means the counters prove the ACK, which
// is the thing a silent peripheral fails at first.
//
// The accumulators run on the PPU clock, next to the signals; dbgmon says
// when to snapshot them by toggling a level, and reads the snapshot a
// window later.  See dbg/dbgmon.v for why it is a level and not a pulse.
wire dbg_win_tog;
wire dbg_uart_tx;

wire dbg_ppu_wr  = ppu_wbm_stb_o & ppu_wbm_wre_o;
wire dbg_ay_hit  = dbg_ppu_wr & ppu_wbm_ack_i_abr;
wire dbg_716_hit = dbg_ppu_wr & ppu_wbm_ack_i_xm2 &
                   ({ppu_wbm_adr_o[15:1], 1'b0} == 16'o177716);

reg  [ 2:0] dbg_togq  = 3'd0;
reg         dbg_cyc_q = 1'b0;
reg  [ 7:0] dbg_key_q = 8'd0;
reg  [ 7:0] dbg_to_cnt= 8'd0;
wire        dbg_ppu_cyc = ppu_wbm_stb_o;
reg         dbg_ay_q  = 1'b0;
reg         dbg_716_q = 1'b0;
reg         dbg_snd_q = 1'b0;

reg  [15:0] acc_716   = 16'd0;      // last word written to 0177716
reg  [15:0] acc_716c  = 16'd0;      // writes to it this window
reg  [15:0] acc_sndc  = 16'd0;      // edges of `sound` this window
reg  [11:0] acc_mnmax = 12'd0;      // range of the nine summed AY channels
reg  [11:0] acc_mnmin = 12'hfff;
reg  [15:0] acc_ayc   = 16'd0;      // AY writes this window
reg  [15:0] acc_ayadr = 16'd0;      // and the last of them
reg  [15:0] acc_aydat = 16'd0;
reg  [15:0] acc_ppuc  = 16'd0;      // PPU bus cycles this window - liveness
reg  [15:0] acc_pputo = 16'd0;      // of which timed out with no ack
reg  [15:0] acc_keyc  = 16'd0;      // keycode changes this window
reg  signed [15:0] acc_vmax = 16'sh8000;   // range of the sample that goes out
reg  signed [15:0] acc_vmin = 16'sh7fff;

reg  [15:0] snp_716   = 16'd0;
reg  [15:0] snp_716c  = 16'd0;
reg  [15:0] snp_sndc  = 16'd0;
reg  [11:0] snp_mnmax = 12'd0;
reg  [11:0] snp_mnmin = 12'd0;
reg  [15:0] snp_ayc   = 16'd0;
reg  [15:0] snp_ayadr = 16'd0;
reg  [15:0] snp_aydat = 16'd0;
reg  [15:0] snp_ppuc  = 16'd0;
reg  [15:0] snp_pputo = 16'd0;
reg  [15:0] snp_keyc  = 16'd0;
reg  signed [15:0] snp_vmax = 16'sd0;
reg  signed [15:0] snp_vmin = 16'sd0;

wire        dbg_latch = dbg_togq[2] ^ dbg_togq[1];
wire signed [15:0] dbg_vol = $signed(volume_data_l);

always @(posedge ppuclk_p) begin
    dbg_togq  <= {dbg_togq[1:0], dbg_win_tog};
    dbg_ay_q  <= dbg_ay_hit;
    dbg_716_q <= dbg_716_hit;
    dbg_snd_q <= sound;
    dbg_cyc_q <= dbg_ppu_cyc;
    dbg_key_q <= keycode;

    // A PPU cycle that has had the strobe up for 64 clocks - 20 us, about
    // what a 1801 waits - with nothing acking is a bus timeout, which is
    // what an address no peripheral answers looks like from the outside.
    // It counts once per cycle because the counter saturates above 63.
    if (!ppu_wbm_stb_o || ppu_wbm_ack_i) dbg_to_cnt <= 8'd0;
    else if (dbg_to_cnt != 8'hff)        dbg_to_cnt <= dbg_to_cnt + 8'd1;

    if (dbg_latch) begin
        snp_716   <= acc_716;                              // survives, not cleared
        snp_716c  <= acc_716c;   acc_716c  <= 16'd0;
        snp_sndc  <= acc_sndc;   acc_sndc  <= 16'd0;
        snp_mnmax <= acc_mnmax;  acc_mnmax <= 12'd0;
        snp_mnmin <= acc_mnmin;  acc_mnmin <= 12'hfff;
        snp_vmax  <= acc_vmax;   acc_vmax  <= 16'sh8000;
        snp_vmin  <= acc_vmin;   acc_vmin  <= 16'sh7fff;
        snp_ayc   <= acc_ayc;    acc_ayc   <= 16'd0;
        snp_ayadr <= acc_ayadr;
        snp_aydat <= acc_aydat;
        snp_ppuc  <= acc_ppuc;   acc_ppuc  <= 16'd0;
        snp_pputo <= acc_pputo;  acc_pputo <= 16'd0;
        snp_keyc  <= acc_keyc;   acc_keyc  <= 16'd0;
    end else begin
        if (dbg_716_hit & ~dbg_716_q) begin
            acc_716  <= ppu_wbm_dat_o;
            acc_716c <= acc_716c + 16'd1;
        end
        if (dbg_ay_hit & ~dbg_ay_q) begin
            acc_ayadr <= {ppu_wbm_adr_o[15:1], 1'b0};
            acc_aydat <= ppu_wbm_dat_o;
            acc_ayc   <= acc_ayc + 16'd1;
        end
        if (sound ^ dbg_snd_q)          acc_sndc  <= acc_sndc + 16'd1;
        if (dbg_ppu_cyc & ~dbg_cyc_q)   acc_ppuc  <= acc_ppuc + 16'd1;
        if (dbg_to_cnt == 8'd63)        acc_pputo <= acc_pputo + 16'd1;
        if (keycode != dbg_key_q)       acc_keyc  <= acc_keyc + 16'd1;
        if (mono_channel > acc_mnmax)   acc_mnmax <= mono_channel;
        if (mono_channel < acc_mnmin)   acc_mnmin <= mono_channel;
        if (dbg_vol      > acc_vmax)    acc_vmax  <= dbg_vol;
        if (dbg_vol      < acc_vmin)    acc_vmin  <= dbg_vol;
    end
end

// Word 0 is a constant, so a reader can tell it has the line in step and
// which format it is looking at.  tools/dbgmon.py names the rest.
wire [16*18-1:0] dbg_probes = {
    hdmi_audio_pktc,                                        // 17 HDMI audio packets sent
    hdmi_audio_dropc,                                       // 16 HDMI samples dropped
    snp_keyc,                                               // 15 keycode changes
    snp_pputo,                                              // 14 PPU bus timeouts
    snp_ppuc,                                               // 13 PPU bus cycles
    16'hdb02,                                               // 12 end marker
    {hdmi_audio_ovf, buts[1], 2'd0,
                     system_volume, 2'd0, keycode},         // 11 status
    snp_aydat,                                              // 10 last AY data
    snp_ayadr,                                              //  9 last AY address
    snp_ayc,                                                //  8 AY writes
    snp_vmin,                                               //  7 sample min
    snp_vmax,                                               //  6 sample max
    {4'd0, snp_mnmin},                                      //  5 AY sum min
    {4'd0, snp_mnmax},                                      //  4 AY sum max
    snp_sndc,                                               //  3 beeper edges
    snp_716c,                                               //  2 0177716 writes
    snp_716,                                                //  1 0177716 value
    16'hdb01                                                //  0 magic
};

dbgmon #(
    .CLK_FRE(       50),
    .BAUD   (   115200),
    .NPROBE (       18),
    .WIN    (  5000000)    // 100 ms at 50 MHz - ten lines a second
) dbg (
    .clk    (      clk_50),
    // NOT sys_rst_n.  That name is a lie: it is high for the first 335 ms
    // and low afterwards, and every module here takes it as `if (reset)`,
    // active high.  sys_rst is its complement and is the active-low reset
    // this module wants - low while the counter runs, high once it sticks.
    .rst_n  (     sys_rst),
    .probes (  dbg_probes),
    .win_tog(dbg_win_tog),
    .tx_pin ( dbg_uart_tx)
);

// One line to hand pin 69 back to the machine: vp65_uart_tx instead.
assign uart_tx = dbg_uart_tx;
//------------------------------------------------------------//

// A diagnostic 1 kHz tone lived here, gated on buts[1], while the HDMI
// audio was being chased.  It did its job - it proved the sink played
// nothing even from a known-good bipolar signal, which is what led to the
// InfoFrame cadence - and it is gone again because the start screen
// stopped appearing with an SD card present in the build that carried it.
// Nothing in it touches the card; what it does is add logic and move the
// placement, and the SD and floppy paths are clocked by data signals that
// test003.sdc constrains at a made-up 1 us, so they are not honestly
// analysed and placement churn can break them silently.  `git show` the
// tone commit to put it back.

//------------------------------------------------------------//
// One FIFO per channel.  fifo_audio is 16 bits wide and regenerating it as
// 32 would mean an IP Core Generator run on the operator's machine, so the
// second channel gets a second instance of the same core instead.  Both are
// read on the same strobe, so they stay in step; audio_drive picks which
// word goes out in which I2S slot.
wire [15:0] data_aud_l;
wire [15:0] data_aud_r;
wire        isread_aud;
wire        Empty_aud_l, Full_aud_l;
wire        Empty_aud_r, Full_aud_r;

fifo_audio abf1(
    .Data (volume_data_l),
    .WrClk(     ppuclk_p),
    .RdClk(   isread_aud),
    .WrEn (         1'b1),
    .RdEn (         1'b1),
    .Q    (   data_aud_l),
    .Empty(  Empty_aud_l),
    .Full (   Full_aud_l)
);

fifo_audio abf2(
    .Data (volume_data_r),
    .WrClk(     ppuclk_p),
    .RdClk(   isread_aud),
    .WrEn (         1'b1),
    .RdEn (         1'b1),
    .Q    (   data_aud_r),
    .Empty(  Empty_aud_r),
    .Full (   Full_aud_r)
);

audio_drive ad1(
    .clk_1p536m(  ppuclk_p),
    .rst_n     (   sys_rst),

    .idata     (data_aud_l),
    .idata_rgt (data_aud_r),
    .req       (isread_aud), /// fifo_empty/fifo_rd

    .HP_BCK    (    HP_BCK),
    .HP_WS     (     HP_WS),
    .HP_DIN    (    HP_DIN)
);
//------------------------------------------------------------//
endmodule