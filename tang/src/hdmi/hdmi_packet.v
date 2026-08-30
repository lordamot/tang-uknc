`timescale 1ns/1ps
//========================================================================
// hdmi_packet.v - the 32-clock data island packet and its BCH ECC.
//
// HDMI 1.4a Figure 5-4 and section 5.2.3.4.  A packet is 24 header bits
// plus four 56-bit subpackets, each with an 8-bit BCH parity byte
// appended.  Over 32 pixel clocks the header goes out one bit per clock
// on channel 0, and each subpacket two bits per clock across channels 1
// and 2 - 32 x 2 = 64 = 56 + 8, which is where the shape comes from.
//
// The ECC is the standard's BCH(64,56)/BCH(32,24) with generator
// x^8 + x^7 + x^6 + x^4 + 1; in LSB-first shift form that is the 8'h83
// below.  The subpacket parity has to advance two bits per clock or it
// would not be ready in time, which is why there are two stages.
//
// Derived from Sameer Puri's https://github.com/hdl-util/hdmi (MIT),
// with the unpacked-array ports flattened for Verilog-2001.
//========================================================================
module hdmi_packet (
    input             clk_pixel,
    input             reset    ,   // active high
    input             island   ,   // data island period, 32 clocks a packet
    input      [23:0] header   ,
    input     [223:0] sub      ,   // {sub3, sub2, sub1, sub0}, 56 bits each
    output      [8:0] packet_data, // {ch2[3:0], ch1[3:0], ch0}
    output reg  [4:0] counter
);

initial counter = 5'd0;

always @(posedge clk_pixel)
    if (reset)       counter <= 5'd0;
    else if (island) counter <= counter + 5'd1;

wire [5:0] c2   = {counter, 1'b0};   // bit 2n   of a subpacket
wire [5:0] c2p1 = {counter, 1'b1};   // bit 2n+1

reg [7:0] par0, par1, par2, par3, parh;
initial begin par0 = 0; par1 = 0; par2 = 0; par3 = 0; parh = 0; end

wire [55:0] s0 = sub[ 55:  0];
wire [55:0] s1 = sub[111: 56];
wire [55:0] s2 = sub[167:112];
wire [55:0] s3 = sub[223:168];

wire [63:0] b0 = {par0, s0};
wire [63:0] b1 = {par1, s1};
wire [63:0] b2 = {par2, s2};
wire [63:0] b3 = {par3, s3};
wire [31:0] bh = {parh, header};

assign packet_data = {b3[c2p1], b2[c2p1], b1[c2p1], b0[c2p1],
                      b3[c2  ], b2[c2  ], b1[c2  ], b0[c2  ],
                      bh[counter]};

function [7:0] next_ecc;
    input [7:0] ecc;
    input       bit_in;
    begin
        next_ecc = (ecc >> 1) ^ ((ecc[0] ^ bit_in) ? 8'b10000011 : 8'd0);
    end
endfunction

wire [7:0] p0a = next_ecc(par0, s0[c2]);
wire [7:0] p1a = next_ecc(par1, s1[c2]);
wire [7:0] p2a = next_ecc(par2, s2[c2]);
wire [7:0] p3a = next_ecc(par3, s3[c2]);

wire [7:0] p0b = next_ecc(p0a, s0[c2p1]);
wire [7:0] p1b = next_ecc(p1a, s1[c2p1]);
wire [7:0] p2b = next_ecc(p2a, s2[c2p1]);
wire [7:0] p3b = next_ecc(p3a, s3[c2p1]);

// The header is 24 bits against the counter's 32 states, so the index has
// to be guarded - reading past the end would be an x that then poisons
// the parity for the rest of the packet.
wire       hdr_bit = (counter < 5'd24) ? header[counter[4:0]] : 1'b0;
wire [7:0] pha     = next_ecc(parh, hdr_bit);

always @(posedge clk_pixel) begin
    if (reset || !island) begin
        par0 <= 8'd0; par1 <= 8'd0; par2 <= 8'd0; par3 <= 8'd0; parh <= 8'd0;
    end else begin
        // The parity covers the data only, never itself: 56 subpacket bits
        // are 28 clocks at two a clock, and the header is 24 bits.
        if (counter < 5'd28) begin
            par0 <= p0b; par1 <= p1b; par2 <= p2b; par3 <= p3b;
            if (counter < 5'd24) parh <= pha;
        end else if (counter == 5'd31) begin
            par0 <= 8'd0; par1 <= 8'd0; par2 <= 8'd0; par3 <= 8'd0; parh <= 8'd0;
        end
    end
end

endmodule
