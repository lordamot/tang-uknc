`timescale 1ns/1ps
//========================================================================
// hdmi_tx.v - HDMI transmitter with audio, in place of Gowin's dvi_tx.
//
// Gowin's DVI_TX IP is DVI: video only, no data islands, so no sound.
// This is the same job plus the four packets a sink needs before it will
// play audio - clock regeneration, audio sample, audio InfoFrame and AVI
// InfoFrame - and it hands ten-bit TMDS words to hdmi_serdes.v, which is
// the only part that touches Gowin primitives.
//
// The port list is dvi_tx's with the audio added, so swapping back is one
// instance name in top.v.
//
// Timing is taken entirely from de/hs/vs; nothing here knows the mode.
// A data island has to be announced eight clocks before it starts and the
// video period ten, which means knowing the future, so the video is put
// through a short delay line and the scheduler looks at the undelayed
// signals.  The delay applies to sync and pixels alike, so the picture
// does not move.
//
// The data island goes in the BACK PORCH - after hsync falls, before the
// active period.  That assumes hsync is active high with the back porch
// behind it, which is what sdram2.v generates; with 176 clocks there and
// four packets to place, it fits with room to spare.  On a line with no
// active period at all - vertical blanking - the islands still happen,
// which is what keeps the audio flowing across the frame boundary.
//
// The audio is sampled here at pixel_clock/1024, and NOT taken from the
// I2S path: at 50.143 MHz that is 48.968 kHz, an exact ratio, which is
// what makes N and CTS below constants rather than a measurement.  The
// sink regenerates its audio clock from them, so it plays at the rate the
// machine really produces; the "48 kHz" in the channel status is the
// nearest declarable value and is informational only.
//========================================================================
module hdmi_tx (
    input             I_rst_n      ,
    input             I_rgb_clk    ,   // pixel clock, 50.143 MHz
    input             I_rgb_vs     ,
    input             I_rgb_hs     ,
    input             I_rgb_de     ,
    input       [7:0] I_rgb_r      ,
    input       [7:0] I_rgb_g      ,
    input       [7:0] I_rgb_b      ,
    input      [15:0] I_audio_l    ,   // signed-magnitude free, taken as is
    input      [15:0] I_audio_r    ,
    output      [9:0] O_tmds_ch0   ,   // to hdmi_serdes
    output      [9:0] O_tmds_ch1   ,
    output      [9:0] O_tmds_ch2   ,
    output reg        O_audio_ovf      // a sample was dropped - see below
);

//------------------------------------------------------------------------
// Audio clock regeneration constants.  Fs = f_TMDS * N / (128 * CTS), and
// with Fs = f_TMDS/1024 that is CTS = 8*N for any N.  N = 6144 is the
// standard value for the 48 kHz family.
//------------------------------------------------------------------------
localparam [19:0] ACR_N   = 20'd6144 ;
localparam [19:0] ACR_CTS = 20'd49152;

localparam integer AUDIO_DIV = 1024;   // pixel clocks per audio frame

//------------------------------------------------------------------------
// Delay line.  DLY has to be at least 10 for the video preamble and guard
// band; 12 leaves the look-ahead taps inside the array with room.
//------------------------------------------------------------------------
localparam integer DLY = 12;

reg [26:0] dl [0:DLY];              // {vs, hs, de, r, g, b}
integer    k;

initial for (k = 0; k <= DLY; k = k + 1) dl[k] = 27'd0;

always @(posedge I_rgb_clk) begin
    dl[0] <= {I_rgb_vs, I_rgb_hs, I_rgb_de, I_rgb_r, I_rgb_g, I_rgb_b};
    for (k = 1; k <= DLY; k = k + 1) dl[k] <= dl[k-1];
end

wire        vs_out = dl[DLY][26];
wire        hs_out = dl[DLY][25];
wire        de_out = dl[DLY][24];
wire [7:0]  r_out  = dl[DLY][23:16];
wire [7:0]  g_out  = dl[DLY][15: 8];
wire [7:0]  b_out  = dl[DLY][ 7: 0];

// de this many clocks ahead of the output
wire de_a1  = dl[DLY- 1][24];
wire de_a2  = dl[DLY- 2][24];
wire de_a3  = dl[DLY- 3][24];
wire de_a4  = dl[DLY- 4][24];
wire de_a5  = dl[DLY- 5][24];
wire de_a6  = dl[DLY- 6][24];
wire de_a7  = dl[DLY- 7][24];
wire de_a8  = dl[DLY- 8][24];
wire de_a9  = dl[DLY- 9][24];
wire de_a10 = dl[DLY-10][24];

wire video_guard    = !de_out && (de_a1 || de_a2);
wire video_preamble = !de_out && !video_guard &&
                      (de_a3 || de_a4 || de_a5 || de_a6 ||
                       de_a7 || de_a8 || de_a9 || de_a10);

//------------------------------------------------------------------------
// Where in the blanking the data island goes.  di_cnt restarts on the
// falling edge of the delayed hsync and saturates, so it is a position
// within the back porch and nothing else.
//------------------------------------------------------------------------
localparam integer DI_PRE   = 4                     ; // control period first
localparam integer DI_GUARD = DI_PRE   + 8          ; // 8 clocks of preamble
localparam integer DI_DATA  = DI_GUARD + 2          ; // 2 clocks of guard
localparam integer DI_PKTS  = 4                     ; // packets in one island
localparam integer DI_END   = DI_DATA  + 32*DI_PKTS ;
localparam integer DI_TAIL  = DI_END   + 2          ; // trailing guard

reg        hs_out_d = 1'b0;
reg  [9:0] di_cnt   = 10'd1023;

always @(posedge I_rgb_clk) begin
    hs_out_d <= hs_out;
    if (!hs_out && hs_out_d)      di_cnt <= 10'd0;
    else if (di_cnt != 10'd1023)  di_cnt <= di_cnt + 10'd1;
end

// The video period and its announcement always win: if a mode ever moved
// the back porch under the island, the picture would go rather than the
// sound, and that is the wrong way round.
wire di_room = !de_out && !video_guard && !video_preamble;

wire di_preamble = di_room && (di_cnt >= DI_PRE  ) && (di_cnt < DI_GUARD);
wire di_guard    = di_room && (((di_cnt >= DI_GUARD) && (di_cnt < DI_DATA)) ||
                               ((di_cnt >= DI_END  ) && (di_cnt < DI_TAIL)));
wire di_period   = di_room && (di_cnt >= DI_DATA ) && (di_cnt < DI_END  );

//------------------------------------------------------------------------
// Audio capture.  volume_data_l/r in top.v change in the ppu clock
// domain, which is a bit of the same counter that makes this pixel clock,
// so there is no crossing here and no synchroniser is needed.
//------------------------------------------------------------------------
reg [9:0]  aud_div = 10'd0;
reg [31:0] aud_fifo [0:3];
reg [2:0]  aud_wr = 3'd0, aud_rd = 3'd0;

wire [2:0] aud_cnt   = aud_wr - aud_rd;
wire       aud_avail = (aud_cnt != 3'd0);
wire       aud_full  = (aud_cnt == 3'd4);

initial begin
    aud_fifo[0] = 0; aud_fifo[1] = 0; aud_fifo[2] = 0; aud_fifo[3] = 0;
    O_audio_ovf = 1'b0;
end

wire aud_take = (aud_div == AUDIO_DIV - 1);

always @(posedge I_rgb_clk) begin
    if (!I_rst_n) begin
        aud_div <= 10'd0;
        aud_wr  <= 3'd0;
    end else begin
        aud_div <= aud_take ? 10'd0 : aud_div + 10'd1;
        if (aud_take) begin
            if (aud_full) O_audio_ovf <= 1'b1;   // sticky; the tb reads it
            else begin
                aud_fifo[aud_wr[1:0]] <= {I_audio_r, I_audio_l};
                aud_wr <= aud_wr + 3'd1;
            end
        end
    end
end

wire [15:0] aud_l_head = aud_fifo[aud_rd[1:0]][15: 0];
wire [15:0] aud_r_head = aud_fifo[aud_rd[1:0]][31:16];

//------------------------------------------------------------------------
// IEC 60958 channel status.  Only the low 40 bits are ever non-zero, so
// only those are indexed - the rest of the 192-bit block reads as 0.
// LSB first: grade, word type, copyright, pre-emphasis, mode, category,
// source, channel, sampling frequency, clock accuracy, word length,
// original frequency.  Word length is left "not indicated", which lets
// the 16-bit sample sit in the top of a 24-bit word unchanged.
//------------------------------------------------------------------------
localparam [39:0] CS_L = {4'b0000, 4'b0000, 2'b00, 2'b00, 4'b0010,
                          4'd1, 4'd0, 8'd0, 2'b00, 3'b000, 1'b1, 1'b0, 1'b0};
localparam [39:0] CS_R = {4'b0000, 4'b0000, 2'b00, 2'b00, 4'b0010,
                          4'd2, 4'd0, 8'd0, 2'b00, 3'b000, 1'b1, 1'b0, 1'b0};

reg [7:0] aud_frame = 8'd0;    // 0..191, position in the channel status block

wire cs_bit_l = (aud_frame < 8'd40) ? CS_L[aud_frame[5:0]] : 1'b0;
wire cs_bit_r = (aud_frame < 8'd40) ? CS_R[aud_frame[5:0]] : 1'b0;

wire [23:0] samp_l = {aud_l_head, 8'd0};
wire [23:0] samp_r = {aud_r_head, 8'd0};

wire par_l = ^{cs_bit_l, 1'b0, 1'b0, samp_l};   // user = 0, valid = 0
wire par_r = ^{cs_bit_r, 1'b0, 1'b0, samp_r};

// The subpacket is two IEC 60958 subframes end to end, 28 bits each: the
// 24 sample bits, then V, U, C and P.  The flags belong to the sample
// they follow and have to stay interleaved with it - collecting them into
// one field at the top puts the right channel's sample four bits high, so
// its two top bits become the left channel's parity and channel status,
// and the parity bit flips every sample.  That is heard as white noise on
// the right channel and nothing else, because the left one happens to
// stay in place at bits 23:0.
wire [55:0] as_sub0 = {par_r, cs_bit_r, 1'b0, 1'b0, samp_r,
                       par_l, cs_bit_l, 1'b0, 1'b0, samp_l};

// HB1[3:0] say which of the four subpackets carry a sample - one here.
// HB2[7:4] flag the sample that starts a channel status block.
// HB2 = {B3..B0, sample_flat3..0}, HB1 = {rsvd, layout, sp3..sp0}, HB0 = type
wire [23:0] as_header = {{3'b000, (aud_frame == 8'd0), 4'b0000},
                         {3'b000, 1'b0, 4'b0001},
                         8'd2};

//------------------------------------------------------------------------
// The two InfoFrames and the clock regeneration packet.  All constant:
// the checksum folds away at synthesis.
//------------------------------------------------------------------------
localparam [23:0] AVI_HDR = {8'h0D, 8'h02, 8'h82};   // length 13, ver 2
wire [7:0] avi_pb1 = 8'h10;   // RGB, no bar data, A0 set so R below counts
wire [7:0] avi_pb2 = 8'h08;   // no colorimetry/aspect, AFAR = same as picture
wire [7:0] avi_pb3 = 8'h00;   // default quantisation, no scaling
wire [7:0] avi_pb4 = 8'h00;   // VIC 0: this mode is not a CEA one
wire [7:0] avi_pb5 = 8'h00;   // no pixel repetition
wire [7:0] avi_pb0 = 8'h01 + ~(AVI_HDR[23:16] + AVI_HDR[15:8] + AVI_HDR[7:0]
                             + avi_pb1 + avi_pb2 + avi_pb3 + avi_pb4 + avi_pb5);

wire [223:0] AVI_SUB = {56'd0, 56'd0,
                        {8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0},
                        {8'd0, avi_pb5, avi_pb4, avi_pb3, avi_pb2, avi_pb1,
                         avi_pb0}};

localparam [23:0] AI_HDR = {8'h0A, 8'h01, 8'h84};    // length 10, ver 1
wire [7:0] ai_pb1 = 8'h01;    // two channels, coding type from the stream
wire [7:0] ai_pb2 = 8'h00;    // sample size and rate from the stream
wire [7:0] ai_pb3 = 8'h00;
wire [7:0] ai_pb4 = 8'h00;    // channel allocation: front left, front right
wire [7:0] ai_pb5 = 8'h00;
wire [7:0] ai_pb0 = 8'h01 + ~(AI_HDR[23:16] + AI_HDR[15:8] + AI_HDR[7:0]
                            + ai_pb1 + ai_pb2 + ai_pb3 + ai_pb4 + ai_pb5);

wire [223:0] AI_SUB = {56'd0, 56'd0,
                       {8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0},
                       {8'd0, ai_pb5, ai_pb4, ai_pb3, ai_pb2, ai_pb1, ai_pb0}};

// General Control Packet.  HDMI 1.4b 5.3.6 says it SHALL go out at least
// once per two video fields; this design sent none at all, which left the
// sink with no statement of the colour depth and no Clear_AVMUTE it could
// ever have acted on.
//
// SB0 carries the mute flags and THE ORDER IS NOT THE OBVIOUS ONE:
// **bit 0 is Set_AVMUTE and bit 4 is Clear_AVMUTE**, never both in one
// packet.  Sending 8'h01 here on the guess that bit 0 meant "clear" muted
// the sink instead - a black screen with the monitor falling back to
// advertising its preferred mode, which is what AVMUTE is defined to do.
// It is 8'h10.
//
// SB1 is {PP[3:0], CD[3:0]}: colour depth 0 is "not indicated", which is
// what a 24-bit source sends, and the packing phase is 0 with it.  SB2
// bit 2 is Default_Phase, also 0.
localparam [23:0] GCP_HDR = {8'd0, 8'd0, 8'd3};
localparam [55:0] GCP_SUB = {40'd0, 8'h00, 8'h10};

localparam [23:0] ACR_HDR = {8'd0, 8'd0, 8'd1};
localparam [55:0] ACR_SUB = {ACR_N[7:0], ACR_N[15:8], {4'd0, ACR_N[19:16]},
                             ACR_CTS[7:0], ACR_CTS[15:8],
                             {4'd0, ACR_CTS[19:16]}, 8'd0};

//------------------------------------------------------------------------
// Picking a packet.  Four slots a line: the first carries one of the four
// standing packets in turn, the rest carry audio when there is any and a
// null packet when there is not.  Three samples a line is nearly twice
// what 48.97 kHz needs at this line rate, so the audio never queues.
//
// One line in four each, at a 31.3 kHz line rate, puts every standing
// packet out at 7.8 kHz - far above the once-per-two-fields the spec asks
// of the GCP and the InfoFrames.
//------------------------------------------------------------------------
wire pick = (di_cnt == DI_DATA - 1) || (di_cnt == DI_DATA + 31) ||
            (di_cnt == DI_DATA + 63) || (di_cnt == DI_DATA + 95);
wire pick_first = (di_cnt == DI_DATA - 1);

// Which line of the frame this is.  The standing packets are placed by
// line number rather than round-robined every line, because one line in
// four put each InfoFrame on the wire 7800 times a second.  Real sources
// send them once per frame, the spec asks only for once per two fields,
// and a sink that re-arms its audio path whenever an Audio InfoFrame
// arrives would never get started at that rate.  Two televisions play no
// audio at all from this design while both display the picture and both
// act on control packets, which is the shape of exactly that.
reg  [9:0] line_cnt = 10'd0;
reg        vs_out_d = 1'b0;

always @(posedge I_rgb_clk) begin
    vs_out_d <= vs_out;
    if (vs_out && !vs_out_d)      line_cnt <= 10'd0;          // frame start
    else if (!hs_out && hs_out_d) line_cnt <= line_cnt + 10'd1;
end

// AVI, audio InfoFrame and GCP once a frame - 50.7 Hz, twice the minimum.
// ACR every 32 lines is 979 Hz, the rate a real source uses.  Every other
// line the first slot carries audio like the rest, so there are now four
// audio slots a line instead of three.
wire want_avi = (line_cnt == 10'd1);
wire want_ai  = (line_cnt == 10'd2);
wire want_gcp = (line_cnt == 10'd3);
wire want_acr = (line_cnt[4:0] == 5'd16);
wire want_std = want_avi || want_ai || want_gcp || want_acr;

reg [23:0] hdr_r    = 24'd0;
reg [223:0] sub_r   = 224'd0;

always @(posedge I_rgb_clk) begin
    if (!I_rst_n) begin
        aud_rd    <= 3'd0;
        aud_frame <= 8'd0;
        hdr_r     <= 24'd0;
        sub_r     <= 224'd0;
    end else if (di_room && pick) begin
        if (pick_first && want_std) begin
            if (want_avi) begin hdr_r <= AVI_HDR; sub_r <= AVI_SUB; end
            else if (want_ai)  begin hdr_r <= AI_HDR;  sub_r <= AI_SUB;  end
            else if (want_gcp) begin hdr_r <= GCP_HDR;
                                     sub_r <= {56'd0, 56'd0, 56'd0, GCP_SUB}; end
            else               begin hdr_r <= ACR_HDR;
                                     sub_r <= {ACR_SUB, ACR_SUB, ACR_SUB, ACR_SUB}; end
        end else if (aud_avail) begin
            hdr_r     <= as_header;
            sub_r     <= {56'd0, 56'd0, 56'd0, as_sub0};
            aud_rd    <= aud_rd + 3'd1;
            aud_frame <= (aud_frame == 8'd191) ? 8'd0 : aud_frame + 8'd1;
        end else begin
            hdr_r <= 24'd0;             // null packet
            sub_r <= 224'd0;
        end
    end
end

wire [8:0] packet_data;
wire [4:0] packet_cnt;

hdmi_packet pkt (
    .clk_pixel  (   I_rgb_clk),
    .reset      (!di_period  ),
    .island     ( di_period  ),
    .header     (      hdr_r ),
    .sub        (      sub_r ),
    .packet_data( packet_data),
    .counter    (  packet_cnt)
);

//------------------------------------------------------------------------
// Mode and the three channels.
//------------------------------------------------------------------------
wire [2:0] mode = di_guard      ? 3'd4 :
                  di_period     ? 3'd3 :
                  video_guard   ? 3'd2 :
                  de_out        ? 3'd1 : 3'd0;

wire       any_preamble = video_preamble || di_preamble;

// Channel 0 carries the syncs at all times; the first character of a data
// island is the one with bit 3 clear.
wire [3:0] isl0 = {(di_cnt != DI_DATA), packet_data[0], vs_out, hs_out};
wire [3:0] isl1 = packet_data[4:1];
wire [3:0] isl2 = packet_data[8:5];

tmds_channel #(.CN(0)) ch0 (
    .clk_pixel(I_rgb_clk), .video_data(b_out), .island_data(isl0),
    .control_data({vs_out, hs_out}), .mode(mode), .tmds(O_tmds_ch0));

tmds_channel #(.CN(1)) ch1 (
    .clk_pixel(I_rgb_clk), .video_data(g_out), .island_data(isl1),
    .control_data({1'b0, any_preamble}), .mode(mode), .tmds(O_tmds_ch1));

tmds_channel #(.CN(2)) ch2 (
    .clk_pixel(I_rgb_clk), .video_data(r_out), .island_data(isl2),
    .control_data({1'b0, di_preamble}), .mode(mode), .tmds(O_tmds_ch2));

endmodule
