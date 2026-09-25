// mixer.v - the sound mixer, on the PPU clock (ppuclk_p, clkram/16 =
// 3.1339 MHz).  Sep 2026.
//
// Models the Aberrant sound module's analogue stage and then band-limits
// the result for the two digital outputs.  The reference is the module's
// own schematic (aberranthacker/aberrant_sound_module, ay.SchDoc and
// mixer.SchDoc, 22 Aug 2023):
//
//   - each chip: A -1k-> L, C -1k-> R, B -2.2k-> L and -2.2k-> R; the three
//     chips' L tied together into 510 ohms to ground, R the same.  With the
//     AY pins taken as voltage sources that is a weighted sum in which A
//     counts 2.2 times B on its side: L = 33*A + 15*B, R = 33*C + 15*B,
//     halved so that the peak (18360) is the old mono sum's.  'o' picks
//     that or the mono sum, 8*(A+B+C), which is what this core had.
//   - the beeper through 510/510 and 100k into both op-amp inputs, the AYs
//     through 10u and 24k into 10k of feedback: the beeper's swing is about
//     four full-scale AY channels, and 8192 against 255*8 is that.  The
//     DACs join here too; the real module has them on P2, not on its board.
//   - an LM358 inverting summer on +5 V behind 10u/24k couplings: a flat
//     amplifier with a 0.66 Hz high-pass.  The DC blocker below is that
//     high-pass, at 0.95 Hz (2^-19 of the clock).  Its feedback capacitors
//     (1200 pF) are marked NC, so the module itself has no low-pass.
//
// The low-pass ('l') is not the module's.  On the operator's recordings
// (Sep 2026) the real machine - module output through an OSSC into the
// same television over HDMI - sat 11-14 dB under this core above 4 kHz,
// and one pole at 4.75 kHz fits that difference best.  So a single pole
// at 4.87 kHz, (2^-7 + 2^-9) of the clock, stands in for that playback
// path.  It is on by default and Off gives the module's own flat response.
// It also takes the AY's square-wave harmonics down before any resampling,
// which is most of what keeps them from aliasing.
//
// The outputs are band-limited too.  hdmi_tx used to take one sample of
// this 3.13 MHz stream every 1/48000 s, and the harmonics above 24 kHz
// folded back as inharmonic tones: -22 dB under a 440 Hz AY square, -13 dB
// under 3.7 kHz, modelled.  out_l/out_r are now the mean of the last 64
// samples, updated every 16 clocks (195.9 kHz), and hdmi_tx averages them
// over each of its own 48 kHz periods - two boxcars, 44-49 dB down with the
// low-pass on.  The I2S path takes out_l/out_r as they are: its 97.9 kHz
// frame is 32 clocks, and the 64-sample mean has its nulls on multiples of
// that rate.
//
// "Old freaks" ('g', off by default) is for small, old monitor speakers,
// which reproduce neither the bass nor, at this level, much of anything:
// a low shelf of +6 dB under 244 Hz (x + a one-pole low-pass of x, the
// pole at 2^-11 of the clock), then +6 dB on everything, into a soft
// limiter instead of the hard clip - flat to half scale, a quarter of
// the slope above it - so that 100% on a loud tune rounds off rather than
// squares off.  It is nothing the module does.
//
// Everything is registered.  hdmi_tx samples out_l/out_r on clkram, which
// is timed against this clock, and the words change once every 16 clocks.
module mixer(
    input             clk,          // ppuclk_p

    input      [ 9:0] ay_a,         // aberrant.v, A of the three chips summed, 0..765
    input      [ 9:0] ay_b,
    input      [ 9:0] ay_c,
    input             beep,         // the beeper bit, already gated by the OSD
    input      [ 7:0] covox,        // 0177372
    input      [ 7:0] lpt,          // printer port A, 0177100

    input             stereo,       // 'o': 0 mono, 1 the module's ABC panning
    input             lowpass,      // 'l': 1 the 4.87 kHz pole
    input             oldfreaks,    // 'g': 1 bass shelf, +6 dB and a soft limiter
    input      [ 1:0] volume,       // 'A': 0 mute, 1 1/4, 2 1/2, 3 full

    output reg [15:0] out_l = 16'd0,
    output reg [15:0] out_r = 16'd0
);

//---------------------------------------------------------------------------------
// 1. The resistor network.  33x = 32x + x, 15x = 16x - x.
wire [16:0] a33 = {2'd0, ay_a, 5'd0} + {7'd0, ay_a};
wire [16:0] c33 = {2'd0, ay_c, 5'd0} + {7'd0, ay_c};
wire [16:0] b15 = {3'd0, ay_b, 4'd0} - {7'd0, ay_b};
wire [16:0] abc_l = (a33 + b15) >> 1;                         // 0..18360
wire [16:0] abc_r = (c33 + b15) >> 1;
wire [11:0] ay_all = {2'd0, ay_a} + {2'd0, ay_b} + {2'd0, ay_c};
wire [16:0] mono = {2'd0, ay_all, 3'd0};                       // 0..18360

wire [16:0] common = {3'd0, beep, 13'd0}                      // 0 or 8192
                   + {4'd0, covox, 5'd0}                      // 0..8160
                   + {4'd0, lpt,   5'd0};                     // 0..8160

reg  [16:0] mix_l = 17'd0;                                    // 0..42872
reg  [16:0] mix_r = 17'd0;
always @(posedge clk) begin
    mix_l <= (stereo ? abc_l : mono) + common;
    mix_r <= (stereo ? abc_r : mono) + common;
end

//---------------------------------------------------------------------------------
// 2. The coupling capacitors: mean += (x - mean) / 2^19, out = x - mean.
// Every AY level is positive, so the raw sum carries a DC offset that
// moves with the music - +3000 under one chip, +9000 under three,
// measured on the board in Aug 2026.  The real module takes it out here.
// (The blocker that was removed on 31 Aug 2026 was never the fault: the
// audio subpacket layout was, progress.md defect 11.)
reg  [35:0] dc_l = 36'd0;
reg  [35:0] dc_r = 36'd0;
wire [16:0] mean_l = dc_l[35:19];
wire [16:0] mean_r = dc_r[35:19];
reg  signed [17:0] hp_l = 18'sd0;                             // +-42872
reg  signed [17:0] hp_r = 18'sd0;
always @(posedge clk) begin
    dc_l <= dc_l + {19'd0, mix_l} - {19'd0, mean_l};
    dc_r <= dc_r + {19'd0, mix_r} - {19'd0, mean_r};
    hp_l <= $signed({1'b0, mix_l}) - $signed({1'b0, mean_l});
    hp_r <= $signed({1'b0, mix_r}) - $signed({1'b0, mean_r});
end

//---------------------------------------------------------------------------------
// 3. The low-pass: s += (x - s) * (2^-7 + 2^-9), s carrying nine bits of
// fraction.  Off, s follows x, so switching it on starts from the signal
// rather than from a stale state.
reg  signed [27:0] lp_l = 28'sd0;
reg  signed [27:0] lp_r = 28'sd0;
wire signed [27:0] e_l = $signed({hp_l, 9'd0}) - lp_l;
wire signed [27:0] e_r = $signed({hp_r, 9'd0}) - lp_r;
always @(posedge clk) begin
    lp_l <= lowpass ? lp_l + (e_l >>> 7) + (e_l >>> 9) : $signed({hp_l, 9'd0});
    lp_r <= lowpass ? lp_r + (e_r >>> 7) + (e_r >>> 9) : $signed({hp_r, 9'd0});
end
wire signed [18:0] y_l = lp_l[27:9];
wire signed [18:0] y_r = lp_r[27:9];

//---------------------------------------------------------------------------------
// 4. "Old freaks": the bass shelf.  b += (y - b) / 2^11, eleven bits of
// fraction; out = y + b, +6 dB at DC, +4 at 244 Hz, +2 at 500, +0.7 at
// 1 kHz.  Off, b follows nothing and is not added.
reg  signed [29:0] bs_st_l = 30'sd0;
reg  signed [29:0] bs_st_r = 30'sd0;
wire signed [29:0] be_l = $signed({y_l, 11'd0}) - bs_st_l;
wire signed [29:0] be_r = $signed({y_r, 11'd0}) - bs_st_r;
always @(posedge clk) begin
    bs_st_l <= oldfreaks ? bs_st_l + (be_l >>> 11) : 30'sd0;
    bs_st_r <= oldfreaks ? bs_st_r + (be_r >>> 11) : 30'sd0;
end
wire signed [19:0] sh_l = oldfreaks ? y_l + $signed(bs_st_l[29:11]) : y_l;   // +-85744
wire signed [19:0] sh_r = oldfreaks ? y_r + $signed(bs_st_r[29:11]) : y_r;

//---------------------------------------------------------------------------------
// 5. Volume, then saturation into 16 bits.  The volume only makes the
// sum quieter; full scale is the unattenuated sum, which past the DC
// blocker swings about zero and saturates only when three chips, the
// beeper and both DACs all peak on one side at once.  "Old freaks"
// doubles it after the volume and limits it softly.
function signed [15:0] clip;
    input signed [20:0] v;
    clip = (v >  21'sd32767) ?  16'sh7FFF :
           (v < -21'sd32767) ? -16'sh7FFF : v[15:0];
endfunction

// linear to 16384, then a quarter of the slope, full scale at 81916
function signed [15:0] limit;
    input signed [20:0] v;
    reg   [20:0] m;
    reg   [20:0] o;
    begin
        m = v[20] ? -v : v;
        o = (m <= 21'd16384) ? m :
            (m >= 21'd81916) ? 21'd32767 : 21'd16384 + ((m - 21'd16384) >> 2);
        limit = v[20] ? -o[15:0] : o[15:0];
    end
endfunction

wire signed [20:0] vs_l = (volume == 2'd3) ? sh_l : (volume == 2'd2) ? (sh_l >>> 1) : (sh_l >>> 2);
wire signed [20:0] vs_r = (volume == 2'd3) ? sh_r : (volume == 2'd2) ? (sh_r >>> 1) : (sh_r >>> 2);

reg  signed [15:0] v_l = 16'sd0;
reg  signed [15:0] v_r = 16'sd0;
always @(posedge clk)
    if (volume == 2'd0) begin
        v_l <= 16'sd0;
        v_r <= 16'sd0;
    end else if (oldfreaks) begin
        v_l <= limit(vs_l <<< 1);
        v_r <= limit(vs_r <<< 1);
    end else begin
        v_l <= clip(vs_l);
        v_r <= clip(vs_r);
    end

//---------------------------------------------------------------------------------
// 6. The 64-sample mean, every 16 clocks: a sum over each block of 16,
// and the last four block sums added.
reg  [ 3:0] blk = 4'd0;
reg  signed [19:0] bs_l = 20'sd0, bs_r = 20'sd0;             // the block being summed
reg  signed [19:0] b1_l = 20'sd0, b2_l = 20'sd0, b3_l = 20'sd0;
reg  signed [19:0] b1_r = 20'sd0, b2_r = 20'sd0, b3_r = 20'sd0;
wire signed [19:0] bn_l = bs_l + v_l;                        // the block including this clock
wire signed [19:0] bn_r = bs_r + v_r;
wire signed [21:0] m_l  = bn_l + b1_l + b2_l + b3_l;
wire signed [21:0] m_r  = bn_r + b1_r + b2_r + b3_r;
always @(posedge clk) begin
    blk <= blk + 4'd1;
    if (blk == 4'd15) begin
        bs_l <= 20'sd0;  b1_l <= bn_l;  b2_l <= b1_l;  b3_l <= b2_l;
        bs_r <= 20'sd0;  b1_r <= bn_r;  b2_r <= b1_r;  b3_r <= b2_r;
        out_l <= m_l[21:6];                                   // /64
        out_r <= m_r[21:6];
    end else begin
        bs_l <= bn_l;
        bs_r <= bn_r;
    end
end

endmodule
