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
// buts[0] is S1 and forces a reset; buts[1] is S2 and is read nowhere -
// the pin stays constrained in the .cst so the port keeps its width.
// They read 0 released and 1 pressed, whatever PULL_MODE=UP suggests:
// n_all_rst below only makes sense that way round.
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
// Clocks.  clkram (50 MHz) and clk4 (4.18 MHz, the CPU) come off the PLL;
// clk_25 and clk_3_12 (the PPU) are bits of sdram2's horizontal counter,
// which is why the tools cannot relate them to the PLL.  Both edges of
// each processor clock go through a BUFG.
wire clk4_sync   ;
wire clk4n_sync  ;
wire clk312_sync ;
wire clk312n_sync;
wire clk4n = ~clk4;

wire locked ;
wire clkram ;
wire init   ;
wire clk_50 ;
wire clk_25 ;
wire clk4   ;
wire cpuclk_p =    clk4_sync;
wire cpuclk_n =   clk4n_sync;
wire ppuclk_p =  clk312_sync;
wire ppuclk_n = clk312n_sync;

wire clk_3_12;

BUFG t4 (   clk4_sync,clk4     );
BUFG t4n(  clk4n_sync,clk4n    );
BUFG t3 ( clk312_sync,clk_3_12 );
// The inverted PPU clock is made from the BUFG output, not from the raw
// counter bit, so that everything the PPU side clocks is downstream of
// one point the SDC names (t3/O; the tool resolves it to horz[3]'s Q,
// but the inverter and t3n are then on its network either way).  Sep 2026.
wire clk_3_12n = ~clk312_sync;
BUFG t3n(clk312n_sync,clk_3_12n);

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
wire       askn_cpu_i;

wire [15:0]addr_ppu_o;
wire [31:0]data_ppu_i;
wire [31:0]data_ppu_o;
wire       read_ppu_o;
wire       wrte_ppu_o;
wire [ 3:0]mask_ppu_o;
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

   .cpu_addr  ({3'd0,addr_cpu_o}),
   .cpu_dout  (       data_cpu_i),
   .cpu_din   (       data_cpu_o),
   .cpu_dqm   (       mask_cpu_o),
   .cpu_read  (       read_cpu_o),
   .cpu_wrte  (       wrte_cpu_o),
   .cpu_busy  (                 ),
   .cpu_asck  (       askn_cpu_i),
   
   .ppu_clk   (         clk_3_12),
   .ppu_addr  ({3'd0,addr_ppu_o}),
   .ppu_dout  (       data_ppu_i),
   .ppu_din   (       data_ppu_o),
   .ppu_dqm   (       mask_ppu_o),
   .ppu_read  (       read_ppu_o),
   .ppu_wrte  (       wrte_ppu_o),
   .ppu_busy  (                 ),
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
// that touches Gowin primitives.  The dvi_tx IP was dropped from the tree
// in Sep 2026; git history has it, and putting it back is this instance
// and nothing else.
wire [9:0] tmds_ch0, tmds_ch1, tmds_ch2;
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
    // The three O_audio_* counters are diagnostic only and go nowhere here;
    // sim/tb/tb_top.v still reads them.
    .O_audio_ovf  (             ),
    .O_audio_dropc(             ),
    .O_audio_pktc (             )
);

hdmi_serdes hdmi_ser(
    .clk_pixel    (       clkpix),
    .ref_locked   (       locked),
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
wire [7:0]  system_hdd_spt     ;
wire [7:0]  system_hdd_heads   ;
wire [7:0]  system_hdd_flags   ;
wire [1:0]  system_hdd_mode    ;
wire [15:0] system_hdd_cyl     ;
wire        system_hdd_wprot   ;

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

    .leds               (                   ), // MCU-driven LEDs and the ws2812 colour:
    .color              (                   ), // nothing on this board to drive

  // values that can be configured by the user
    .system_video       (       system_video),
    .system_reset       (       system_reset),
    .system_volume      (      system_volume),
    .system_floppy_wprot(system_floppy_wprot),
    .system_hdd_spt     (     system_hdd_spt),
    .system_hdd_heads   (   system_hdd_heads),
    .system_hdd_flags   (   system_hdd_flags),
    .system_hdd_mode    (    system_hdd_mode),
    .system_hdd_cyl     (     system_hdd_cyl),
    .system_hdd_wprot   (   system_hdd_wprot)
);

wire [5:0] db9_port = 6'd0;
wire [7:0] keycode  ;   // the UKNC scan code, translated on the MCU

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
    .mouse         (              ),   // the UKNC has no mouse or joystick port
    .keyboard      (       keycode),
    .joystick0     (              ),
    .joystick1     (              )
);


wire [31:0] sd_img_size   ;
wire [ 4:0] sd_img_mounted;
wire sdc_iack = int_ack[3];
wire        sd_busy       ;
wire        sd_done       ;
wire        sd_rd_byte_strobe;
wire [ 8:0] sd_byte_index ;
wire [ 7:0] sd_rd_data    ;
wire [ 7:0] sd_wr_data    ;
wire [ 4:0] sd_rd         ;   // slots 0-3 the floppies, 4 the IDE disk
wire [ 4:0] sd_wr         ;
wire [31:0] sd_sector     ;
wire [31:0] fdd_sector    ;
wire [ 7:0] fdd_wr_data   ;

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

// sd_img_mounted[n] is a one-cycle pulse in the mist_clk domain, raised
// by sd_card.v on the same edge that completes image_size.  These four
// used to be clocked BY that pulse - a flop clock on general routing, one
// per drive - and were what the SDC could only describe as a 1 us clock.
// Sampled on the clock the pulse belongs to, the value is the same and
// the path is one the tool can see.
reg [4:0]mount_dsk = 5'b00000;
always @(posedge mist_clk)begin
    if(sd_img_mounted[0])mount_dsk[0] <= |sd_img_size;
    if(sd_img_mounted[1])mount_dsk[1] <= |sd_img_size;
    if(sd_img_mounted[2])mount_dsk[2] <= |sd_img_size;
    if(sd_img_mounted[3])mount_dsk[3] <= |sd_img_size;
    if(sd_img_mounted[4])mount_dsk[4] <= |sd_img_size;   // the IDE disk
end

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
wire       ppu_vm_init_o;

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
                       ppu_wbm_ack_i_abr ? ppu_wbm_dat_i_abr :
                       ppu_wbm_ack_i_ide ? ppu_wbm_dat_i_ide : 16'o0;

assign ppu_wbm_ack_i = ppu_wbm_ack_i_xm2|ppu_wbm_ack_i_vp|ppu_wbm_ack_i_128|ppu_wbm_ack_i_abr|ppu_wbm_ack_i_ide;

assign ppu_wbi_dat_i = ppu_wbi_ack_i_xm2 ? ppu_wbi_dat_i_xm2 :
                       ppu_wbi_ack_i_vp  ? ppu_wbi_dat_i_vp  : 16'o0;
assign ppu_wbi_ack_i = ppu_wbi_ack_i_xm2 | ppu_wbi_ack_i_vp;
//------------------------------------------------------------//
//  Wishbone CPU
//------------------------------------------------------------//
wire [15:0]vp65_wbm_dat_i;
wire [15:0]vp65_wbi_dat_i;
wire       vp65_vm_virq_i;
wire       vp65_wbm_ack_i;
wire       vp65_wbi_ack_i;
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
// The PPU is reset by the MCU's 'R' bit, which is 0 from configuration,
// so until Sep 2026 the PPU ran from the moment the FPGA configured -
// before the PLL had locked and the SDRAM had been initialised.  Its
// boot ROM is BSRAM, so it got as far as its first SDRAM access and sat
// there unacknowledged until init; whether that read as a stall or as a
// bus timeout into a trap vector that is ALSO in SDRAM depended on the
// 1801's timeout against the init time, and the MCU's reset a third of a
// second later was what cleaned it up.  Holding it until the memory is
// initialised costs nothing and takes that ordering out of the boot.
wire pp_rst = system_reset[0] | ~init;
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
   .pin_vm_dclo_o(             ),   // the PPU's own DCLO/ACLO go nowhere;
   .pin_vm_aclo_o(             ),   // the CPU's come from xm2_01's R177716

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

   .pin_tmr_ena_o(pin_tmr_ena_o),
   .pin_cart_sel_o (         cart_sel),
   .pin_cart_bank_o(        cart_bank)
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

// The CPU's DCLO, ACLO and HALT are bits of R177716, written in the PPU
// domain, and each fans out to dozens of enables inside the CPU core.
// They used to go in raw, so the fan-out sat on a clk_3_12 -> clk4
// crossing that no constraint could bound - the 15 ns cap on that
// crossing (test003.sdc) failed on exactly these nets.  Two flops on the
// CPU clock make each of them one short cross-domain path and a local
// fan-out; the cost is two clk4 periods, 480 ns, on a reset the PPU's
// firmware holds for milliseconds.  DCLO and ACLO start asserted so the
// core is held from configuration.  Sep 2026.
reg [1:0] cpu_dclo_s = 2'b11;
reg [1:0] cpu_aclo_s = 2'b11;
reg [1:0] cpu_halt_s = 2'b00;
always @(posedge cpuclk_p)begin
    cpu_dclo_s <= {cpu_dclo_s[0], cpu_vm_dclo_i};
    cpu_aclo_s <= {cpu_aclo_s[0], cpu_vm_aclo_i};
    cpu_halt_s <= {cpu_halt_s[0], pin_vm_halt_i};
end
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
   
    .rstart       (       fdd_rd),
    .wstart       (       fdd_wr),
    .rsector      (   fdd_sector),
    .rbusy        (      sd_busy),
    .rdone        (      sd_done),

    .outen    (      fdd_outen),
    .outaddr      (sd_byte_index),
    .inbyte       (   sd_rd_data),
    .outbyte      (  fdd_wr_data),
    .mount_dsk    (mount_dsk[3:0]),
    .sd_taken     (    fdd_taken)
);

//------------------------------------------------------------//
// The IDE hard disk cartridge (src/ide/ide.v), slot 4 of the SD path.
//
// sd_card.v has one request interface and the MCU picks the drive from
// a one-hot mask, so two requesters must never be visible to it at
// once - and the first version of this let them be, for a cycle or two,
// with the sector number and the data muxed by "who is pending".  On
// the board that put the WD home block into block 21 of the disk image:
// 21 is the floppy's sector number for track 1 sector 1, which RT-11
// was reading at the moment WDINIT wrote track 0 sector 1.  So there is
// an owner now.  The cartridge gets the path when it asks and no floppy
// request is up and the card is idle; it keeps it until sd_card reports
// done; while it owns, the floppies' request lines are masked off and
// fdd4.v holds its own back (sd_taken), and every mux - sector number,
// write data, incoming bytes - follows the owner and nothing else.
//------------------------------------------------------------//
wire        hdd_sd_active ;
wire        hdd_rstart, hdd_wstart, hdd_other, hdd_outen;
wire [ 3:0] fdd_rd, fdd_wr;
wire        fdd_taken, fdd_outen, sd_owner_hdd;
wire [31:0] hdd_sector    ;
wire [ 7:0] hdd_wr_data   ;
wire        cart_sel      ;
wire [ 1:0] cart_bank     ;
wire [15:0] ppu_wbm_dat_i_ide;
wire        ppu_wbm_ack_i_ide;

sd_arbiter sdarb(
    .clk        (clk_25),
    .fdd_rd(fdd_rd), .fdd_wr(fdd_wr), .fdd_sector(fdd_sector), .fdd_wr_data(fdd_wr_data),
    .fdd_taken(fdd_taken), .fdd_outen(fdd_outen),
    .hdd_rd(hdd_rstart), .hdd_wr(hdd_wstart), .hdd_sector(hdd_sector), .hdd_wr_data(hdd_wr_data),
    .hdd_other(hdd_other), .hdd_outen(hdd_outen),
    .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_sector(sd_sector), .sd_wr_data(sd_wr_data),
    .sd_busy(sd_busy), .sd_done(sd_done), .sd_outen(sd_rd_byte_strobe),
    .owner_hdd(sd_owner_hdd)
);

ide hdd(
    .clk        (            clk_25),
    .rst        (     ppu_vm_init_o),

    .wbm_adr_i  (     ppu_wbm_adr_o),
    .wbm_dat_i  (     ppu_wbm_dat_o),
    .wbm_dat_o  ( ppu_wbm_dat_i_ide),
    .wbm_wre_i  (     ppu_wbm_wre_o),
    .wbm_sel_i  (     ppu_wbm_sel_o),
    .wbm_stb_i  (     ppu_wbm_stb_o),
    .wbm_ack_o  ( ppu_wbm_ack_i_ide),

    .cart_sel   (          cart_sel),
    .cart_bank  (         cart_bank),

    .hdd_present(      mount_dsk[4]),
    .geo_spt    (    system_hdd_spt),
    .geo_heads  (  system_hdd_heads),
    .geo_inv    ( system_hdd_flags[0]),
    .geo_mode   (   system_hdd_mode),
    .geo_cyl    (    system_hdd_cyl),
    .wprot      (  system_hdd_wprot),

    .sd_rstart  (        hdd_rstart),
    .sd_wstart  (        hdd_wstart),
    .sd_sector  (        hdd_sector),
    .sd_rbusy   (           sd_busy),
    .sd_rdone   (           sd_done),
    .sd_other   (         hdd_other),
    .sd_outen   (         hdd_outen),
    .sd_outaddr (     sd_byte_index),
    .sd_inbyte  (        sd_rd_data),
    .sd_outbyte (       hdd_wr_data),
    .sd_active  (     hdd_sd_active)
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
wire [11:0] mono_channel ;   // all nine AY channels, summed in aberrant

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
   .pin_vm_dclo_i(cpu_dclo_s[1]),
   .pin_vm_aclo_i(cpu_aclo_s[1]),
   .pin_vm_halt_i(cpu_halt_s[1]),

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
wire cpu_wbi_stb_o_vp1;   // the CPU's interrupt-ack chain, on to vp65

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
// The UKNC's own C2 serial port.  It drives pin 69 - see the assign at the
// end of the mixer block below.
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

   .pin_wbi_stb_o(                 ),

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
// 8192.  The total is 26552, comfortably inside the 32767 a signed sample
// allows - so full volume is the unattenuated sum and the quieter settings
// divide down from it.  No saturation is needed and none is done.
wire [15:0] ay_mix = {1'd0, mono_channel, 3'd0};   // 0..18360
wire [15:0] beeper = {2'd0, sound, 13'd0};         // 0 or 8192
wire [15:0] mix    = ay_mix + beeper;              // 0..26552

// The sum goes out unipolar, as it is.
//
// Every AY channel sits between 0 and 255 and never goes negative, so the
// sum of nine of them carries a large steady offset, and so does the
// beeper.  A DC blocker used to take that out here, on the reasoning that
// a real module has a coupling capacitor in front of its amplifier and
// this one did not.  It was removed on 31 Aug 2026 because every bipolar
// form of the signal was silent on the operator's television while the
// raw sum played, and the reason was written up as unknown.
//
// It is known now, and it was never the level, the sign or the DC.
// hdmi_tx.v packed the audio subpacket as two IEC 60958 subframes end to
// end instead of HDMI's own layout, which put sample bits 15:12 where the
// sink reads the left channel's V, U, C and P flags.  A negative sample
// has all four set; a sample at or above 16384 has bit 14, the
// channel-status bit, set.  Either corrupts the channel status block the
// sink is reading and the sink mutes.  That is the whole of the table
// that used to sit here: minus 512 dips negative, DC blocked dips
// negative, the beeper at 16384 reaches bit 14, and three AY chips at once
// peak at 18360 and reach it too - while one or two chips, peaking at 6120
// and 12240, never do.  Fixed 1 Sep 2026 in hdmi_tx.v.
//
// So the raw sum is kept here for now as the one thing known to play,
// with the layout fix as the only change between builds.  Once the fixed
// layout has been heard on a board the blocker is worth putting back -
// the offset is real, +3000 of DC under one chip's music, +9000 under
// three, and a sink's own AC coupling turns every step in it into a thump.
// `git show f2bb44b^` has the blocker.
wire signed [17:0] snd_amp = $signed({2'b00, mix});

// mix reaches 26552 when three chips and the beeper all peak at once,
// which fits a signed sample; clip() is kept for the day the beeper or
// the AY level goes back up, so the corner clips rather than wraps.
function signed [15:0] clip;
    input signed [17:0] v;
    clip = (v >  18'sd32767) ?  16'sh7FFF :
           (v < -18'sd32767) ? -16'sh7FFF : v[15:0];
endfunction

// REGISTERED, and that is the whole fix, not a tidy-up.
//
// This was a combinational always @(*), and hdmi_tx latches it at the
// audio sample instant - an instant with no relation to the PPU clock the
// mixer runs on.  So the encoder could take the value while the adders
// were still settling and send a carry-chain intermediate as a sample.
//
// Nothing on the diagnostic line could see it: those probes sampled these
// same wires on posedge ppuclk_p, when everything has settled, so they
// reported a clean +/-3300 waveform while the sink was being fed spikes.
// What gave it away was the board: with the DC blocker out of the path and
// the volume low the AY played, and it went silent as soon as either the
// blocker (a 34-bit accumulator, an 18-bit subtract and a clip behind the
// sample) or full volume was in it.  Depth of logic, not level of signal.
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
    'b01 : begin volume_data_l <= clip(snd_amp>>>2); volume_data_r <= clip(snd_amp>>>2); end
    'b10 : begin volume_data_l <= clip(snd_amp>>>1); volume_data_r <= clip(snd_amp>>>1); end
    'b11 : begin volume_data_l <= clip(snd_amp);     volume_data_r <= clip(snd_amp);     end
    endcase
// The HDMI side takes the same post-volume words, and resamples them to
// exactly 48 kHz with a phase accumulator - see src/hdmi/hdmi_tx.v.  It does not go through the FIFO
// below: that one is clocked by the I2S bit rate and is a different rate
// entirely.
assign hdmi_audio_l = volume_data_l;
assign hdmi_audio_r = volume_data_r;

// Pin 69 is the UKNC's own C2 serial port.  A diagnostic monitor
// (src/dbg/dbgmon.v, since removed from the tree - `git log --all --
// tang/src/dbg` finds it) had the line for a fortnight in Aug 2026, with
// about 160 lines of probe accumulators here feeding it.
assign uart_tx = vp65_uart_tx;

// A diagnostic 1 kHz tone lived here, gated on buts[1], while the HDMI
// audio was being chased.  It did its job - it proved the sink played
// nothing even from a known-good bipolar signal, which is what led to the
// InfoFrame cadence - and it is gone again because the start screen
// stopped appearing with an SD card present in the build that carried it.
// Nothing in it touches the card; what it does is add logic and move the
// placement, and at the time the SD and floppy paths were clocked by data
// signals that test003.sdc could only call a made-up 1 us clock, so they
// were not analysed and placement churn broke them silently.  Both halves
// of that are gone as of 2 Sep 2026: fdd4.v runs on clk_25 with enables,
// and the SDC relates clk_25 to the PPU clock with the right phase (its
// edges sit on clk_25's falling edges, 20 ns from the rising ones), so
// the floppy's status word into vp1_128fdd is a 20 ns path the tool now
// knows about.  `git show` the tone commit to put the tone back.

//------------------------------------------------------------//
// One FIFO per channel.  fifo_audio is 16 bits wide and regenerating it as
// 32 would mean an IP Core Generator run on the operator's machine, so the
// second channel gets a second instance of the same core instead.  Both are
// read on the same strobe, so they stay in step; audio_drive picks which
// word goes out in which I2S slot.
wire [15:0] data_aud_l;
wire [15:0] data_aud_r;
wire        isread_aud;

fifo_audio abf1(
    .Data (volume_data_l),
    .WrClk(     ppuclk_p),
    .RdClk(   isread_aud),
    .WrEn (         1'b1),
    .RdEn (         1'b1),
    .Q    (   data_aud_l),
    .Empty(             ),
    .Full (             )
);

fifo_audio abf2(
    .Data (volume_data_r),
    .WrClk(     ppuclk_p),
    .RdClk(   isread_aud),
    .WrEn (         1'b1),
    .RdEn (         1'b1),
    .Q    (   data_aud_r),
    .Empty(             ),
    .Full (             )
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