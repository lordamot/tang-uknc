`timescale 1ns/1ps
//========================================================================
// tmds_channel.v - one TMDS channel: video, control, guard bands, TERC4.
//
// HDMI 1.4a section 5.4 (encoding), 5.2.2.1 (video guard band) and
// 5.2.3.3 (data island guard bands).  The 8b/10b part is a direct
// transcription of the spec's Figure 5-7 and uses its variable names, so
// it can be read against the standard rather than against intent.
//
// Derived from Sameer Puri's https://github.com/hdl-util/hdmi
// (MIT licence), rewritten in Verilog-2001 to match the rest of this
// tree.  The coding tables are the standard's and are not ours to change.
//
// CN is the channel number: 0 is blue and carries HSYNC/VSYNC, 1 green,
// 2 red.  It only affects which guard-band words are emitted.
//========================================================================
module tmds_channel #(parameter CN = 0) (
    input            clk_pixel   ,
    input      [7:0] video_data  ,
    input      [3:0] island_data ,
    input      [1:0] control_data,   // {vsync, hsync} on channel 0
    // 0 control, 1 video, 2 video guard, 3 data island, 4 island guard
    input      [2:0] mode        ,
    output reg [9:0] tmds
);

initial tmds = 10'b1101010100;

//------------------------------------------------------------------------
// Stage 1: transition minimisation.  q_m is nine bits - eight of data and
// one saying whether XOR or XNOR was used.
//------------------------------------------------------------------------
wire [3:0] n1d = video_data[0] + video_data[1] + video_data[2] + video_data[3]
               + video_data[4] + video_data[5] + video_data[6] + video_data[7];

reg  [8:0] q_m;
integer    i;
always @* begin
    q_m[0] = video_data[0];
    if (n1d > 4'd4 || (n1d == 4'd4 && video_data[0] == 1'b0)) begin
        for (i = 0; i < 7; i = i + 1) q_m[i+1] = q_m[i] ~^ video_data[i+1];
        q_m[8] = 1'b0;
    end else begin
        for (i = 0; i < 7; i = i + 1) q_m[i+1] = q_m[i] ^ video_data[i+1];
        q_m[8] = 1'b1;
    end
end

//------------------------------------------------------------------------
// Stage 2: DC balance.  acc is the running disparity and is reset outside
// the video period, which is what makes each video period start balanced.
//------------------------------------------------------------------------
wire [3:0] n1q = q_m[0] + q_m[1] + q_m[2] + q_m[3]
               + q_m[4] + q_m[5] + q_m[6] + q_m[7];

wire signed [4:0] n1q_m07 = {1'b0, n1q};
wire signed [4:0] n0q_m07 = 5'sd8 - n1q_m07;

reg signed [4:0] acc = 5'sd0;
reg signed [4:0] acc_add;
reg        [9:0] q_out;

always @* begin
    if (acc == 5'sd0 || n1q_m07 == n0q_m07) begin
        if (q_m[8]) begin
            q_out   = {1'b0, 1'b1,  q_m[7:0]};
            acc_add = n1q_m07 - n0q_m07;
        end else begin
            q_out   = {1'b1, 1'b0, ~q_m[7:0]};
            acc_add = n0q_m07 - n1q_m07;
        end
    end else if ((acc > 5'sd0 && n1q_m07 > n0q_m07) ||
                 (acc < 5'sd0 && n1q_m07 < n0q_m07)) begin
        q_out   = {1'b1, q_m[8], ~q_m[7:0]};
        acc_add = (n0q_m07 - n1q_m07) + (q_m[8] ? 5'sd2 : 5'sd0);
    end else begin
        q_out   = {1'b0, q_m[8],  q_m[7:0]};
        acc_add = (n1q_m07 - n0q_m07) - (q_m[8] ? 5'sd0 : 5'sd2);
    end
end

always @(posedge clk_pixel)
    acc <= (mode != 3'd1) ? 5'sd0 : acc + acc_add;

//------------------------------------------------------------------------
// The three fixed tables.  Section 5.4.2, 5.4.3, 5.2.2.1, 5.2.3.3.
//------------------------------------------------------------------------
reg [9:0] control_coding;
always @* case (control_data)
    2'b00: control_coding = 10'b1101010100;
    2'b01: control_coding = 10'b0010101011;
    2'b10: control_coding = 10'b0101010100;
    2'b11: control_coding = 10'b1010101011;
endcase

reg [9:0] terc4_coding;
always @* case (island_data)
    4'b0000: terc4_coding = 10'b1010011100;
    4'b0001: terc4_coding = 10'b1001100011;
    4'b0010: terc4_coding = 10'b1011100100;
    4'b0011: terc4_coding = 10'b1011100010;
    4'b0100: terc4_coding = 10'b0101110001;
    4'b0101: terc4_coding = 10'b0100011110;
    4'b0110: terc4_coding = 10'b0110001110;
    4'b0111: terc4_coding = 10'b0100111100;
    4'b1000: terc4_coding = 10'b1011001100;
    4'b1001: terc4_coding = 10'b0100111001;
    4'b1010: terc4_coding = 10'b0110011100;
    4'b1011: terc4_coding = 10'b1011000110;
    4'b1100: terc4_coding = 10'b1010001110;
    4'b1101: terc4_coding = 10'b1001110001;
    4'b1110: terc4_coding = 10'b0101100011;
    4'b1111: terc4_coding = 10'b1011000011;
endcase

// Video guard band: channels 0 and 2 send one word, channel 1 the other.
wire [9:0] video_guard_band =
    (CN == 1) ? 10'b0100110011 : 10'b1011001100;

// Data island guard band: channels 1 and 2 are fixed, channel 0 carries
// the sync levels - it is the TERC4 word for {1, 1, vsync, hsync}.
reg  [9:0] data_guard_band;
always @* begin
    if (CN == 0)
        case (control_data)
            2'b00: data_guard_band = 10'b1010001110;   // TERC4 of 4'b1100
            2'b01: data_guard_band = 10'b1001110001;   // TERC4 of 4'b1101
            2'b10: data_guard_band = 10'b0101100011;   // TERC4 of 4'b1110
            2'b11: data_guard_band = 10'b1011000011;   // TERC4 of 4'b1111
        endcase
    else
        data_guard_band = 10'b0100110011;
end

always @(posedge clk_pixel) case (mode)
    3'd0:    tmds <= control_coding  ;
    3'd1:    tmds <= q_out           ;
    3'd2:    tmds <= video_guard_band;
    3'd3:    tmds <= terc4_coding    ;
    3'd4:    tmds <= data_guard_band ;
    default: tmds <= control_coding  ;
endcase

endmodule
