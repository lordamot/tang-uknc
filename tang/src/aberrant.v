module aberrant(
   ppu_vm_clk_p,

   ppu_vm_init_i,

   ppu_wbm_adr_i,
   ppu_wbm_dat_i,
   ppu_wbm_dat_o,
   ppu_wbm_cyc_i,
   ppu_wbm_wre_i,
   ppu_wbm_sel_o,
   ppu_wbm_stb_i,
   ppu_wbm_ack_o,

   l_channel,
   r_channel,
   m_channel
);
input        ppu_vm_clk_p;

input        ppu_vm_init_i;

input  [16:0]ppu_wbm_adr_i;
input  [15:0]ppu_wbm_dat_i;
output [15:0]ppu_wbm_dat_o;
input        ppu_wbm_cyc_i;
input        ppu_wbm_wre_i;
input  [ 1:0]ppu_wbm_sel_o;
input        ppu_wbm_stb_i;
output       ppu_wbm_ack_o;

output [10:0]l_channel;
output [10:0]r_channel;
output [11:0]m_channel;

//---------------------------------------------------------------------------------
// Chipselect.  The real Aberrant sound module (aberranthacker/
// aberrant_sound_module, for the MS 0511) lays its range out like this:
//
//   0177360  AY1          0177370  unused (MIDI data on the FPGA variant)
//   0177362  AY2          0177372  DAC, the Covox
//   0177364  AY3          0177374  YM3812, the OPL2
//   0177366  unused       0177376  unused
//
// and the board itself answers **only** the three AY word addresses.
// 0177366-0177377 are decoded onto the expansion connector P2, so with
// nothing plugged in there they must not be acknowledged at all - a bus
// timeout is how software learns the Covox and the OPL2 are absent.
//
// This decode used to leave adr[3] don't-care, so the top half aliased
// straight onto the bottom: 0177372 hit AY2 and 0177374 hit AY3.  A player
// probing for a Covox or an OPL2 was answered by a device that is not
// there, and then every write it aimed at them was latched into an AY as a
// register address or a data byte.  That is why the AYs went quiet and
// only occasionally made a noise.  adr[3] is now compared, and adr[2:1] ==
// 11 - which is 0177366 - is left to the connector as well.
//
// The old comment here said "Chipselect 177130/2"; it never decoded that.
wire ceppu = (ppu_wbm_adr_i[15:3] == 13'o17736) &&
             (ppu_wbm_adr_i[ 2:1] != 2'b11);
//---------------------------------------------------------------------------------
assign ppu_wbm_ack_o = ceppu && ppu_wbm_stb_i;

assign ppu_wbm_dat_o = ce0 ? {2{DO_0}}:
                       ce1 ? {2{DO_1}}:
                       ce2 ? {2{DO_2}}: 16'd0;

wire ce0 = ceppu && ppu_wbm_adr_i[2:1]==2'b00 && ppu_wbm_stb_i;
wire ce1 = ceppu && ppu_wbm_adr_i[2:1]==2'b01 && ppu_wbm_stb_i;
wire ce2 = ceppu && ppu_wbm_adr_i[2:1]==2'b10 && ppu_wbm_stb_i;
wire bc  = &ppu_wbm_sel_o;


wire nwtbt = &ppu_wbm_sel_o;

reg bdir1 = 0;
reg bc1   = 0;
reg bdir2 = 0;
reg bc2   = 0;
reg bdir3 = 0;
reg bc3   = 0;

always @(posedge ppu_vm_clk_p)begin
        bdir1 <= ce0 && ppu_wbm_wre_i;
        bc1   <= ce0 && nwtbt;
        bdir2 <= ce1 && ppu_wbm_wre_i;
        bc2   <= ce1 && nwtbt;
        bdir3 <= ce2 && ppu_wbm_wre_i;
        bc3   <= ce2 && nwtbt;
    end


//---------------------------------------------------------------------------------
// AY clock enable.  An AY-3-8912 wants 1.7734 MHz on CLC, to within 100 Hz,
// and that is what every PT3 module is written against.  These three run
// off ppu_vm_clk_p, which is clkram/16 = 3.1339 MHz, and with CE tied high
// they were free-running at that - 1.767 times too fast, so every note came
// out about nine semitones sharp and the music that much too quick.
//
// A phase accumulator makes the enable instead: 37084/65536 of 3.1339 MHz
// is 1.773364 MHz, 36 Hz low and inside the chip's own tolerance.  The
// jitter is one PPU clock, 319 ns, which the tone dividers average away.
//
// This gates the sound generation ONLY.  ym2149.sv writes its registers in
// a plain always @(posedge CLK) with no CE guard, so bus writes still land
// on every PPU clock and none can be missed while the enable is low.
reg [15:0] ay_acc = 16'd0;
reg        ay_ce  = 1'b0;
always @(posedge ppu_vm_clk_p)
    {ay_ce, ay_acc} <= {1'b0, ay_acc} + 17'd37084;

//---------------------------------------------------------------------------------
// Data outputs for each AY chips
wire [7:0] DO_0;
wire [7:0] DO_1;
wire [7:0] DO_2;
//---------------------------------------------------------------------------------
wire [7:0]out_a_dd1;
wire [7:0]out_b_dd1;
wire [7:0]out_c_dd1;

YM2149 dd1(
    .CLK      (      ppu_vm_clk_p), // Global clock
    .CE       (             ay_ce), // PSG Clock enable, 1.7734 MHz
    .RESET    (     ppu_vm_init_i), // Chip RESET (set all Registers to '0', active hi)
    .BDIR     (             bdir1), // Bus Direction (0 - read , 1 - write)
    .BC       (               bc1), // Bus control
    .DI       (ppu_wbm_dat_i[7:0]), // Data In
    .DO       (              DO_0), // Data Out
    .CHANNEL_A(         out_a_dd1), // PSG Output channel A
    .CHANNEL_B(         out_b_dd1), // PSG Output channel B
    .CHANNEL_C(         out_c_dd1), // PSG Output channel C

    .SEL      (              1'b1),
    .MODE     (              1'b1),

    .ACTIVE   (                  ),

    .IOA_in   (              8'd0),
    .IOA_out  (                  ),

    .IOB_in   (              8'd0),
    .IOB_out  (                  )
);

wire [7:0]out_a_dd2;
wire [7:0]out_b_dd2;
wire [7:0]out_c_dd2;

YM2149 dd2(
    .CLK      (      ppu_vm_clk_p), // Global clock
    .CE       (             ay_ce), // PSG Clock enable, 1.7734 MHz
    .RESET    (     ppu_vm_init_i), // Chip RESET (set all Registers to '0', active hi)
    .BDIR     (             bdir2), // Bus Direction (0 - read , 1 - write)
    .BC       (               bc2), // Bus control
    .DI       (ppu_wbm_dat_i[7:0]), // Data In
    .DO       (              DO_1), // Data Out
    .CHANNEL_A(         out_a_dd2), // PSG Output channel A
    .CHANNEL_B(         out_b_dd2), // PSG Output channel B
    .CHANNEL_C(         out_c_dd2), // PSG Output channel C

    .SEL      (              1'b1),
    .MODE     (              1'b1),

    .ACTIVE   (                  ),

    .IOA_in   (              8'd0),
    .IOA_out  (                  ),

    .IOB_in   (              8'd0),
    .IOB_out  (                  )
);

// The module carries THREE AY-3-8912s; this one used to be commented out
// with its outputs tied to zero, so 0177364 acknowledged and did nothing.
wire [7:0]out_a_dd3;
wire [7:0]out_b_dd3;
wire [7:0]out_c_dd3;

YM2149 dd3(
    .CLK      (      ppu_vm_clk_p), // Global clock
    .CE       (             ay_ce), // PSG Clock enable, 1.7734 MHz
    .RESET    (     ppu_vm_init_i), // Chip RESET (set all Registers to '0', active hi)
    .BDIR     (             bdir3), // Bus Direction (0 - read , 1 - write)
    .BC       (               bc3), // Bus control
    .DI       (ppu_wbm_dat_i[7:0]), // Data In
    .DO       (              DO_2), // Data Out
    .CHANNEL_A(         out_a_dd3), // PSG Output channel A
    .CHANNEL_B(         out_b_dd3), // PSG Output channel B
    .CHANNEL_C(         out_c_dd3), // PSG Output channel C

    .SEL      (              1'b1),
    .MODE     (              1'b1),

    .ACTIVE   (                  ),

    .IOA_in   (              8'd0),
    .IOA_out  (                  ),

    .IOB_in   (              8'd0),
    .IOB_out  (                  )
);
//---------------------------------------------------------------------------------
// mixer
//---------------------------------------------------------------------------------
reg [10:0]left_channel  = 11'd0;
reg [10:0]right_channel = 11'd0;
reg [11:0]mono_channel  = 12'd0;

assign l_channel =  left_channel;
assign r_channel = right_channel;
assign m_channel =  mono_channel;

always @(posedge ppu_vm_clk_p)begin
        left_channel  <= out_a_dd1 + out_a_dd2 + out_a_dd3 + ((out_b_dd1 + out_b_dd2 + out_b_dd3)>>1);
        right_channel <= out_c_dd1 + out_c_dd2 + out_c_dd3 + ((out_b_dd1 + out_b_dd2 + out_b_dd3)>>1);
        mono_channel  <= out_a_dd1 + out_a_dd2 + out_a_dd3 + out_b_dd1 + out_b_dd2 + out_b_dd3 + out_c_dd1 + out_c_dd2 + out_c_dd3;
    end
//---------------------------------------------------------------------------------
endmodule
