`timescale 1ns/1ps
//========================================================================
// hdmi_serdes.v - ten-bit TMDS words out of the pins.
//
// Everything Gowin-specific in the HDMI path is here and nowhere else:
// the 5x serial clock, four OSER10 serialisers and four ELVDS output
// buffers.  hdmi_tx.v above it is ordinary Verilog, which is what lets
// the simulation replace this module with a stub and still exercise the
// encoder - see sim/stubs/gowin_ip_sim.v.
//
// This is NOT IP Core Generator output and must not be treated as such
// (.claude/rules/guideline.md): rPLL, OSER10 and ELVDS_OBUF are device
// primitives, and this is a hand-written instantiation of them.  The
// equivalent inside Gowin's dvi_tx was an rPLL doing exactly this, which
// is why the PLL budget does not change - it is still two of two.
//
// The serial clock is multiplied from the pixel clock rather than made
// separately from the 27 MHz crystal, and that is not a detail: OSER10
// needs its fast and slow clocks in a fixed phase relation, and taking
// the pixel clock as the PLL's own reference is what guarantees it.
//
// TMDS is sent least significant bit first, so tmds[0] is D0.
//========================================================================
module hdmi_serdes (
    input        clk_pixel   ,
    input        ref_locked  ,   // the PLL that makes clk_pixel has locked
    input  [9:0] tmds_ch0    ,
    input  [9:0] tmds_ch1    ,
    input  [9:0] tmds_ch2    ,
    output       O_tmds_clk_p ,
    output       O_tmds_clk_n ,
    output [2:0] O_tmds_data_p,
    output [2:0] O_tmds_data_n
);

wire clk_serial;
wire pll_lock;

// 50.143 MHz x 5 = 250.714 MHz.  VCO = 250.714 x 4 = 1002.9 MHz, inside
// the GW2A range; the phase detector sees the full 50.143 MHz.  Parameters
// go in by defparam, which is how Gowin's own generated wrappers do it.
// This PLL is fed by another PLL's output, and until Sep 2026 it had no
// reset: it was acquiring while its reference was still swinging into
// lock, and where that left it was a property of the power cycle.  Gowin's
// PLL guide wants RESET released after the input clock is stable, so it
// is held until sys_rpll says it has locked, and the serialisers are held
// until this one has.
rPLL pll_hdmi (
    .CLKOUT  (clk_serial),
    .LOCK    (pll_lock  ),
    .CLKOUTP (          ),
    .CLKOUTD (          ),
    .CLKOUTD3(          ),
    .RESET   (~ref_locked),
    .RESET_P (1'b0      ),
    .CLKIN   (clk_pixel ),
    .CLKFB   (1'b0      ),
    .FBDSEL  (6'b000000 ),
    .IDSEL   (6'b000000 ),
    .ODSEL   (6'b000000 ),
    .PSDA    (4'b0000   ),
    .DUTYDA  (4'b0000   ),
    .FDLY    (4'b1111   )
);

defparam pll_hdmi.FCLKIN           = "50.143";
defparam pll_hdmi.DEVICE           = "GW2AR-18C";
defparam pll_hdmi.DYN_IDIV_SEL     = "false";
defparam pll_hdmi.IDIV_SEL         = 0;        // divide by 1
defparam pll_hdmi.DYN_FBDIV_SEL    = "false";
defparam pll_hdmi.FBDIV_SEL        = 4;        // multiply by 5
defparam pll_hdmi.DYN_ODIV_SEL     = "false";
defparam pll_hdmi.ODIV_SEL         = 4;
defparam pll_hdmi.PSDA_SEL         = "0000";
defparam pll_hdmi.DYN_DA_EN        = "false";
defparam pll_hdmi.DUTYDA_SEL       = "1000";
defparam pll_hdmi.CLKOUT_FT_DIR    = 1'b1;
defparam pll_hdmi.CLKOUTP_FT_DIR   = 1'b1;
defparam pll_hdmi.CLKOUT_DLY_STEP  = 0;
defparam pll_hdmi.CLKOUTP_DLY_STEP = 0;
defparam pll_hdmi.CLKFB_SEL        = "internal";
defparam pll_hdmi.CLKOUT_BYPASS    = "false";
defparam pll_hdmi.CLKOUTP_BYPASS   = "false";
defparam pll_hdmi.CLKOUTD_BYPASS   = "false";
defparam pll_hdmi.DYN_SDIV_SEL     = 2;
defparam pll_hdmi.CLKOUTD_SRC      = "CLKOUT";
defparam pll_hdmi.CLKOUTD3_SRC     = "CLKOUT";

// The clock channel is five lows then five highs, sent through the same
// kind of serialiser as the data so it leaves the die the same way.
wire [9:0] tmds_ck = 10'b1111100000;

wire [3:0] ser_q;
wire       ser_rst = ~pll_lock;

OSER10 ser0 (.Q(ser_q[0]), .FCLK(clk_serial), .PCLK(clk_pixel), .RESET(ser_rst),
    .D0(tmds_ch0[0]), .D1(tmds_ch0[1]), .D2(tmds_ch0[2]), .D3(tmds_ch0[3]),
    .D4(tmds_ch0[4]), .D5(tmds_ch0[5]), .D6(tmds_ch0[6]), .D7(tmds_ch0[7]),
    .D8(tmds_ch0[8]), .D9(tmds_ch0[9]));

OSER10 ser1 (.Q(ser_q[1]), .FCLK(clk_serial), .PCLK(clk_pixel), .RESET(ser_rst),
    .D0(tmds_ch1[0]), .D1(tmds_ch1[1]), .D2(tmds_ch1[2]), .D3(tmds_ch1[3]),
    .D4(tmds_ch1[4]), .D5(tmds_ch1[5]), .D6(tmds_ch1[6]), .D7(tmds_ch1[7]),
    .D8(tmds_ch1[8]), .D9(tmds_ch1[9]));

OSER10 ser2 (.Q(ser_q[2]), .FCLK(clk_serial), .PCLK(clk_pixel), .RESET(ser_rst),
    .D0(tmds_ch2[0]), .D1(tmds_ch2[1]), .D2(tmds_ch2[2]), .D3(tmds_ch2[3]),
    .D4(tmds_ch2[4]), .D5(tmds_ch2[5]), .D6(tmds_ch2[6]), .D7(tmds_ch2[7]),
    .D8(tmds_ch2[8]), .D9(tmds_ch2[9]));

OSER10 serc (.Q(ser_q[3]), .FCLK(clk_serial), .PCLK(clk_pixel), .RESET(ser_rst),
    .D0(tmds_ck[0]), .D1(tmds_ck[1]), .D2(tmds_ck[2]), .D3(tmds_ck[3]),
    .D4(tmds_ck[4]), .D5(tmds_ck[5]), .D6(tmds_ck[6]), .D7(tmds_ck[7]),
    .D8(tmds_ck[8]), .D9(tmds_ck[9]));

ELVDS_OBUF obuf_d0 (.O(O_tmds_data_p[0]), .OB(O_tmds_data_n[0]), .I(ser_q[0]));
ELVDS_OBUF obuf_d1 (.O(O_tmds_data_p[1]), .OB(O_tmds_data_n[1]), .I(ser_q[1]));
ELVDS_OBUF obuf_d2 (.O(O_tmds_data_p[2]), .OB(O_tmds_data_n[2]), .I(ser_q[2]));
ELVDS_OBUF obuf_ck (.O(O_tmds_clk_p    ), .OB(O_tmds_clk_n    ), .I(ser_q[3]));

endmodule
