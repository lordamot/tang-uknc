`timescale 1ns/1ps
//========================================================================
// tb_mix.v - the audio mixer's level ceiling, checked numerically.
//
// The claim under test is that the output level is bounded - the sample
// never exceeds 2040, whatever is playing - AND that the voices are still
// summed rather than flattened into each other.  aberrant.v adds the nine
// channels and puts the sum through one saturating curve,
//
//     y = FS * S / (S + K),    K = 255, FS = 2040
//
// so one channel at amplitude 15 gives 1024 and all nine give 1840: five
// decibels apart, nothing pinned, harmonic structure intact.  It replaced
// a pairwise composite that held every case at exactly 2040 and, because
// an AY channel at full amplitude is a square between 0 and 255,
// degenerated into a logical OR and turned chords into a click train.
//
// This exists because nothing in the full-machine testbench ever makes a
// sound, so without it the mixer is only ever read.
//
// aberrant.v is driven for real, over its wishbone port, the way ppu.v's
// core drives it - a word write latches an AY register number, a byte
// write puts data in it.  The expected values are computed here from the
// AY's own volume table and from the *definition* of the curve with a real
// division, not from the restoring divider the RTL uses, so the two cannot
// agree by sharing a mistake.
//
// The beeper stage lives in top.v, which this cannot instantiate without
// the whole machine, so it is covered the other way round: the exact
// composite is evaluated here over all 2041 possible AY levels and
// compared against the arithmetic top.v performs.  That checks the
// arithmetic, not top.v's source text - see the report.
//
// Run with `make mix-test`.
//========================================================================
module tb_mix;

localparam integer FS   = 2040;    // the ceiling; the mixer stops at 1840
localparam integer MAXA = 1840;    // all nine AY channels at amplitude 15
localparam integer BEEP = 510;     // the one-bit beeper, FS/4

reg clk = 1'b0;
always #159.5 clk = ~clk;          // 3.1339 MHz, the PPU clock

reg         init = 1'b1;
reg  [16:0] adr  = 17'o0;
reg  [15:0] dat  = 16'o0;
reg         cyc  = 1'b0;
reg         wre  = 1'b0;
reg  [ 1:0] sel  = 2'b11;
reg         stb  = 1'b0;
wire [15:0] dout;
wire        ack;
wire [10:0] l_ch, r_ch;
wire [11:0] m_ch;

aberrant dut (
    .ppu_vm_clk_p (clk), .ppu_vm_init_i(init), .test_i(1'b0), .test_st(),
    .ppu_wbm_adr_i(adr), .ppu_wbm_dat_i(dat), .ppu_wbm_dat_o(dout),
    .ppu_wbm_cyc_i(cyc), .ppu_wbm_wre_i(wre), .ppu_wbm_sel_o(sel),
    .ppu_wbm_stb_i(stb), .ppu_wbm_ack_o(ack),
    .l_channel(l_ch), .r_channel(r_ch), .m_channel(m_ch));

integer errors = 0;

//------------------------------------------------------------------------
// The bus, as ppu.v drives it: strobe held five clocks, address, data and
// sel stable throughout.
task bus_write(input [16:0] a, input [15:0] d, input [1:0] s);
    begin
        @(negedge clk); adr = a; dat = d; sel = s; wre = 1'b1; cyc = 1'b1; stb = 1'b1;
        repeat (5) @(posedge clk);
        @(negedge clk); stb = 1'b0; cyc = 1'b0; wre = 1'b0;
        repeat (2) @(posedge clk);
    end
endtask

task ay_set(input [16:0] a, input [7:0] r, input [7:0] v);
    begin
        bus_write(a, {8'd0, r}, 2'b11);   // word  -> register number
        bus_write(a, {8'd0, v}, 2'b01);   // byte  -> data
    end
endtask

// Amplitudes on one chip, with tone and noise switched off so the channels
// hold a steady level instead of oscillating.  R7 = 077: bits 0-2 disable
// the tones, bits 3-5 the noise, all active low.
task chip_set(input [16:0] a, input [7:0] va, input [7:0] vb, input [7:0] vc);
    begin
        ay_set(a, 8'd7,  8'o77);
        ay_set(a, 8'd8,  va);
        ay_set(a, 8'd9,  vb);
        ay_set(a, 8'd10, vc);
    end
endtask

//------------------------------------------------------------------------
// The expected value, computed independently of the RTL.
//
// The AY's own table, MODE=1 (the AY-3-8910 half), indexed the way
// ym2149.sv indexes it: {amplitude[3:0], amplitude[3]}.
function [7:0] ay_level;
    input [3:0] amp;
    reg [7:0] t [0:31];
    begin
        t[ 0]=8'h00; t[ 1]=8'h00; t[ 2]=8'h03; t[ 3]=8'h03;
        t[ 4]=8'h04; t[ 5]=8'h04; t[ 6]=8'h06; t[ 7]=8'h06;
        t[ 8]=8'h0a; t[ 9]=8'h0a; t[10]=8'h0f; t[11]=8'h0f;
        t[12]=8'h15; t[13]=8'h15; t[14]=8'h22; t[15]=8'h22;
        t[16]=8'h28; t[17]=8'h28; t[18]=8'h41; t[19]=8'h41;
        t[20]=8'h5b; t[21]=8'h5b; t[22]=8'h72; t[23]=8'h72;
        t[24]=8'h90; t[25]=8'h90; t[26]=8'hb5; t[27]=8'hb5;
        t[28]=8'hd7; t[29]=8'hd7; t[30]=8'hff; t[31]=8'hff;
        ay_level = t[{amp, amp[3]}];
    end
endfunction

// The curve, by its definition and with a real divide: the sample for a
// plain sum S of the nine channels is 8 * ceil(255*S/(S+255)).  The RTL
// gets there by restoring division on 65025/(S+255); this does not.
function integer curve_ref;
    input integer S;
    begin
        curve_ref = 8 * ((255*S + (S + 255) - 1) / (S + 255));
    end
endfunction

//------------------------------------------------------------------------
task check(input [255:0] name, input integer got, input integer want);
    begin
        if (got !== want) begin
            $display("  FAIL %0s: got %0d want %0d", name, got, want);
            errors = errors + 1;
        end else $display("  ok   %0s = %0d", name, got);
    end
endtask

// Settle: five pipeline stages in aberrant plus the AY's own output
// register, with plenty of margin.
task settle; begin repeat (40) @(posedge clk); end endtask

integer expect_n;
integer ay, shift_form, exact_form, beep_err;

initial begin
    repeat (10) @(posedge clk);
    init = 1'b0;
    repeat (10) @(posedge clk);

    $display("[tb_mix] full scale = %0d, beeper = %0d", FS, BEEP);

    // --- silence -------------------------------------------------------
    chip_set(17'o177360, 8'd0, 8'd0, 8'd0);
    chip_set(17'o177362, 8'd0, 8'd0, 8'd0);
    chip_set(17'o177364, 8'd0, 8'd0, 8'd0);
    settle;
    check("silence", m_ch, 0);

    // --- the level ladder, one channel at a time -----------------------
    // The point of the curve is that these are DIFFERENT.  Under the
    // composite they were all 2040.
    chip_set(17'o177360, 8'd15, 8'd0, 8'd0);
    settle;
    check("A alone at amplitude 15", m_ch, curve_ref(255));
    check("  and that is 1024", m_ch, 1024);

    chip_set(17'o177360, 8'd15, 8'd15, 8'd0);
    settle;
    check("A and B at amplitude 15", m_ch, curve_ref(510));
    check("  and that is 1360", m_ch, 1360);

    chip_set(17'o177360, 8'd15, 8'd15, 8'd15);
    settle;
    check("A, B and C at amplitude 15", m_ch, curve_ref(765));
    check("  one chip full is 1536", m_ch, 1536);

    // --- all three chips, all nine channels -----------------------------
    chip_set(17'o177362, 8'd15, 8'd15, 8'd15);
    chip_set(17'o177364, 8'd15, 8'd15, 8'd15);
    settle;
    check("three chips, nine channels", m_ch, curve_ref(2295));
    check("  three chips full is 1840", m_ch, MAXA);

    // The ceiling, which is the whole reason the curve is here.
    if (m_ch > FS) begin
        $display("  FAIL: %0d exceeds the ceiling %0d", m_ch, FS);
        errors = errors + 1;
    end else $display("  ok   nine channels stay under the %0d ceiling", FS);

    // Nine voices must be audibly above one, not equal to it.
    if (m_ch <= 1024) begin
        $display("  FAIL: nine channels (%0d) not above one channel (1024)", m_ch);
        errors = errors + 1;
    end else $display("  ok   nine channels are above one, %0d vs 1024", m_ch);

    // l and r must carry the same value - the module is mono.
    check("l_channel follows", l_ch, MAXA);
    check("r_channel follows", r_ch, MAXA);

    // --- below maximum, and additive ------------------------------------
    chip_set(17'o177362, 8'd0, 8'd0, 8'd0);
    chip_set(17'o177364, 8'd0, 8'd0, 8'd0);

    chip_set(17'o177360, 8'd8, 8'd0, 8'd0);
    settle;
    expect_n = curve_ref(ay_level(4'd8));
    check("A alone at amplitude 8", m_ch, expect_n);

    chip_set(17'o177360, 8'd12, 8'd0, 8'd0);
    settle;
    expect_n = curve_ref(ay_level(4'd12));
    check("A alone at amplitude 12", m_ch, expect_n);

    chip_set(17'o177360, 8'd8, 8'd8, 8'd0);
    settle;
    expect_n = curve_ref(2 * ay_level(4'd8));
    check("A and B at amplitude 8", m_ch, expect_n);

    chip_set(17'o177360, 8'd12, 8'd8, 8'd0);
    settle;
    expect_n = curve_ref(ay_level(4'd12) + ay_level(4'd8));
    check("A at 12, B at 8", m_ch, expect_n);

    // The mixer sums, so the same two levels give the same answer whether
    // they sit on one chip or on two.
    chip_set(17'o177360, 8'd12, 8'd0, 8'd0);
    chip_set(17'o177362, 8'd8,  8'd0, 8'd0);
    settle;
    check("the same two levels, two chips", m_ch, expect_n);

    // --- the beeper stage, by arithmetic ---------------------------------
    // top.v computes  ay - (ay >> 2) + 510, which is the saturating
    // composite of the AY level with a beeper at FS/4.  It is exact
    // against the definition ay + 510 - ay*510/2040 for every value the
    // mixer can produce, and it can never break the ceiling.
    beep_err = 0;
    for (ay = 0; ay <= MAXA; ay = ay + 1) begin
        shift_form = ay - (ay >> 2) + BEEP;
        exact_form = ay + BEEP - ((ay * BEEP) / FS);
        if (shift_form !== exact_form) beep_err = beep_err + 1;
        if (shift_form > FS)           beep_err = beep_err + 1;
    end
    check("beeper stage vs definition", beep_err, 0);
    check("beeper alone",                  0 - (0    >> 2) + BEEP, BEEP);
    check("beeper plus the loudest AY", MAXA - (MAXA >> 2) + BEEP, 1890);

    $display("[tb_mix] %0d error(s)", errors);
    if (errors != 0) $fatal(1, "tb_mix failed");
    $finish;
end
endmodule
