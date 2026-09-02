//========================================================================
// Behavioural models of the Gowin IP, for simulation only.
//========================================================================
// Three of the generated IP files under tang/src/ip/ are ENCRYPTED
// (`pragma protect`, aes128-cfb) - dvi_tx, fifo_audio and uartfifo.  Only
// the Gowin synthesiser can read them, so simulation cannot use the real
// thing and neither can any open-source synthesis flow.  The rest of the
// IP is plain Verilog over Gowin primitives (pROM, SDPB, DPB, rPLL),
// which would need the vendor primitive library.
//
// So the whole vendor layer is replaced here, at the IP boundary.  Every
// module below matches its generated counterpart's port list exactly and
// its .ipc configuration exactly; the .ipc values are quoted in each
// header so a future regeneration can be checked against them.
//
// These are simulation models, not synthesisable replacements, and the
// asynchronous FIFOs in particular are behavioural only - they will not
// reproduce a clock-domain-crossing bug.
//========================================================================
`timescale 1ns / 1ps

//------------------------------------------------------------------------
// BUFG - global clock buffer.  top.v instantiates it positionally as
// BUFG name (output, input).
//------------------------------------------------------------------------
module BUFG (output O, input I);
    assign O = I;
endmodule

//------------------------------------------------------------------------
// sys_rpll - ip/sys_rpll/sys_rpll.v
//   FCLKIN 27, IDIV_SEL 6, FBDIV_SEL 12, DYN_SDIV_SEL 12, PSDA_SEL "0100"
//   => clkout  = clkin * (FBDIV_SEL+1) / (IDIV_SEL+1) = 27 * 13/7 = 50.14 MHz
//      clkoutp = clkout shifted by PSDA_SEL/16 of a period (4/16 = 90 deg)
//      clkoutd = clkout / DYN_SDIV_SEL = 4.18 MHz
// The input period is measured rather than assumed, so a testbench that
// clocks something other than 27 MHz still gets the right ratios.
//------------------------------------------------------------------------
module sys_rpll (
    output      clkout,
    output reg  lock,
    output      clkoutp,
    output reg  clkoutd,
    input       clkin
);
    parameter IDIV  = 7;    // IDIV_SEL  + 1
    parameter FBDIV = 13;   // FBDIV_SEL + 1
    parameter SDIV  = 12;   // DYN_SDIV_SEL
    parameter PSDA  = 4;    // PSDA_SEL, in sixteenths of a period

// Yosys reads this file too, for `make synth`, and it parses neither
// `real` nor delay control.  It does not need to: that pass only checks
// the design elaborates, so a straight-through clock is enough there.
`ifdef YOSYS
    assign clkout  = clkin;
    assign clkoutp = clkin;
    always @(*) begin lock = 1'b1; clkoutd = clkin; end
`else
    real tin  = 0.0;        // measured clkin period
    real tout = 0.0;        // derived clkout period
    time prev = 0;

    reg clkout_r  = 1'b0;
    reg clkoutp_r = 1'b0;
    assign clkout  = clkout_r;
    assign clkoutp = clkoutp_r;

    initial begin
        lock    = 1'b0;
        clkoutd = 1'b0;
    end

    // Measure one input period, then hold the ratio for the whole run.
    always @(posedge clkin) begin
        if (prev != 0 && tin == 0.0) begin
            tin  = $realtime - prev;
            tout = tin * IDIV / FBDIV;
        end
        prev = $realtime;
    end

    initial begin
        wait (tout > 0.0);
        #(tout * 3);                    // a plausible lock time
        lock = 1'b1;
    end

    initial begin
        wait (tout > 0.0);
        forever #(tout / 2.0) clkout_r = ~clkout_r;
    end

    initial begin
        wait (tout > 0.0);
        #(tout * PSDA / 16.0);          // the phase-shifted copy
        forever #(tout / 2.0) clkoutp_r = ~clkoutp_r;
    end

    integer dcount = 0;
    always @(posedge clkout_r) begin
        if (dcount == SDIV - 1) dcount <= 0;
        else                    dcount <= dcount + 1;
        if (dcount == 0)          clkoutd <= 1'b1;
        else if (dcount == SDIV/2) clkoutd <= 1'b0;
    end
`endif
endmodule

//------------------------------------------------------------------------
// hdmi_serdes - src/hdmi/hdmi_serdes.v (Gowin primitives).
// The real module is four OSER10s, four ELVDS_OBUFs and an rPLL, none of
// which Verilator has a model for.  It is also where the 250 MHz serial
// clock lives, and running that for the length of a real boot would cost
// a great deal to watch bits the encoder above it has already chosen.
//
// So the pads are tied off here and the checking happens one level up,
// on the ten-bit TMDS words: sim/tb/tb_top.v decodes them back into
// pixels and data island packets, which is a stronger statement about
// hdmi_tx.v than watching a serialiser shift would have been.
//
// dvi_tx is gone from this file with the module it stubbed.  It is still
// in the project - src/ip/dvi_tx - and still uninstantiated.
//------------------------------------------------------------------------
module hdmi_serdes (
    input        clk_pixel,
    input        ref_locked,
    input  [9:0] tmds_ch0,
    input  [9:0] tmds_ch1,
    input  [9:0] tmds_ch2,
    output       O_tmds_clk_p,
    output       O_tmds_clk_n,
    output [2:0] O_tmds_data_p,
    output [2:0] O_tmds_data_n
);
    assign O_tmds_clk_p  = 1'b0;
    assign O_tmds_clk_n  = 1'b1;
    assign O_tmds_data_p = 3'b000;
    assign O_tmds_data_n = 3'b111;
endmodule

//------------------------------------------------------------------------
// fifo_audio - ip/ip/fifo_audio (ENCRYPTED)
//   .ipc: fifo_hs, 16 x 16, StandardFIFO, no first-word-fall-through,
//         no output registers, BSRAM
//------------------------------------------------------------------------
module fifo_audio (
    input  [15:0] Data,
    input         WrClk,
    input         RdClk,
    input         WrEn,
    input         RdEn,
    output [15:0] Q,
    output        Empty,
    output        Full
);
    gowin_fifo_hs_model #(.DW(16), .DEPTH(16)) u (
        .Data(Data), .WrClk(WrClk), .RdClk(RdClk),
        .WrEn(WrEn), .RdEn(RdEn), .Q(Q), .Empty(Empty), .Full(Full));
endmodule

//------------------------------------------------------------------------
// uartfifo - ip/uartfifo (ENCRYPTED)
//   .ipc: fifo_hs, 4 x 8, StandardFIFO, reset synchronisation on
//------------------------------------------------------------------------
module uartfifo (
    input  [7:0] Data,
    input        WrClk,
    input        RdClk,
    input        WrEn,
    input        RdEn,
    output [7:0] Q,
    output       Empty,
    output       Full
);
    gowin_fifo_hs_model #(.DW(8), .DEPTH(4)) u (
        .Data(Data), .WrClk(WrClk), .RdClk(RdClk),
        .WrEn(WrEn), .RdEn(RdEn), .Q(Q), .Empty(Empty), .Full(Full));
endmodule

//------------------------------------------------------------------------
// The shared asynchronous FIFO model.  Standard (not first-word
// fall-through): Q becomes valid one RdClk after RdEn.
//
// This is BEHAVIOURAL.  Both pointers are plain integers read from both
// domains, so it will not reproduce a clock-domain-crossing failure - it
// models what the FIFO is meant to do, not how it does it.
//------------------------------------------------------------------------
module gowin_fifo_hs_model #(
    parameter DW    = 16,
    parameter DEPTH = 16
) (
    input      [DW-1:0] Data,
    input               WrClk,
    input               RdClk,
    input               WrEn,
    input               RdEn,
    output reg [DW-1:0] Q,
    output              Empty,
    output              Full
);
    reg [DW-1:0] mem [0:DEPTH-1];
    integer wp = 0, rp = 0, count = 0;

    assign Empty = (count == 0);
    assign Full  = (count == DEPTH);

    initial Q = {DW{1'b0}};

    always @(posedge WrClk) begin
        if (WrEn && count != DEPTH) begin
            mem[wp] <= Data;
            wp    = (wp + 1) % DEPTH;
            count = count + 1;
        end
    end

    always @(posedge RdClk) begin
        if (RdEn && count != 0) begin
            Q  <= mem[rp];
            rp    = (rp + 1) % DEPTH;
            count = count - 1;
        end
    end
endmodule

//------------------------------------------------------------------------
// pROM models.  Gowin's block ROM registers dout on clk when ce; with
// READ=0 (no output register) that is a one-cycle read, and oce is
// unused.  Contents come from the .mif the .ipc names, converted to hex
// by tools/mif.py - see the Makefile's `mif` target.
//------------------------------------------------------------------------

// rom208 - ip/rom208.  .ipc: ram_prom, 16384 x 16,
//          MEM_FILE ../../../rom/uknc_rom.mif
module rom208 (
    output reg [15:0] dout,
    input             clk,
    input             oce,
    input             ce,
    input             reset,
    input      [13:0] ad
);
    parameter MEM_HEX = "build/mif/uknc_rom.hex";
    reg [15:0] mem [0:16383];
    integer i;
    initial begin
        for (i = 0; i < 16384; i = i + 1) mem[i] = 16'h0000;
        $readmemh(MEM_HEX, mem);
        dout = 16'h0000;
    end
    always @(posedge clk or posedge reset)
        if (reset)   dout <= 16'h0000;
        else if (ce) dout <= mem[ad];
endmodule

// rawtr_prom - fdd/ip/rawtr_prom.  .ipc: ram_prom, 361 x 16,
//              MEM_FILE ../../rom128/rawtrk.mif
module rawtr_prom (
    output reg [15:0] dout,
    input             clk,
    input             oce,
    input             ce,
    input             reset,
    input      [ 8:0] ad
);
    parameter MEM_HEX = "build/mif/rawtrk.hex";
    reg [15:0] mem [0:511];
    integer i;
    initial begin
        for (i = 0; i < 512; i = i + 1) mem[i] = 16'h0000;
        $readmemh(MEM_HEX, mem);
        dout = 16'h0000;
    end
    always @(posedge clk or posedge reset)
        if (reset)   dout <= 16'h0000;
        else if (ce) dout <= mem[ad];
endmodule

//------------------------------------------------------------------------
// Semi-dual-port block RAM (SDPB): port A writes, port B reads, and the
// two may be different widths.  Gowin lays these out as one flat bit
// array, so a port of width W at address A covers bits [A*W +: W]; that
// is what makes the mixed-width cases work, and it is modelled directly.
//------------------------------------------------------------------------
module gowin_sdpb_model #(
    parameter WA   = 8,
    parameter DA   = 512,
    parameter WB   = 16,
    parameter DB   = 256,
    parameter AWA  = 9,
    parameter AWB  = 8
) (
    output reg [WB-1:0] dout,
    input               clka,
    input               cea,
    input               reseta,
    input               clkb,
    input               ceb,
    input               resetb,
    input               oce,
    input  [AWA-1:0]    ada,
    input  [WA-1:0]     din,
    input  [AWB-1:0]    adb
);
    localparam BITS = WA * DA;
    reg [BITS-1:0] mem;
    integer i;

    initial begin
        mem  = {BITS{1'b0}};
        dout = {WB{1'b0}};
    end

    always @(posedge clka)
        if (cea) mem[ada*WA +: WA] <= din;

    always @(posedge clkb or posedge resetb)
        if (resetb)  dout <= {WB{1'b0}};
        else if (ceb) dout <= mem[adb*WB +: WB];
endmodule

// sdbuf_sdpb - ip/sdbuf_sdpb.  .ipc: A 8 x 512 (write), B 32 x 128 (read)
module sdbuf_sdpb (
    output [31:0] dout,
    input         clka, cea, reseta,
    input         clkb, ceb, resetb, oce,
    input  [ 8:0] ada,
    input  [ 7:0] din,
    input  [ 6:0] adb
);
    gowin_sdpb_model #(.WA(8), .DA(512), .WB(32), .DB(128), .AWA(9), .AWB(7)) u (
        .dout(dout), .clka(clka), .cea(cea), .reseta(reseta),
        .clkb(clkb), .ceb(ceb), .resetb(resetb), .oce(oce),
        .ada(ada), .din(din), .adb(adb));
endmodule

//------------------------------------------------------------------------
// dbufsec16 - ip/dbufsec16.  .ipc: ram_dpb, true dual port,
//   A 8 x 512 read/write, B 16 x 256 read/write.  Same flat-array
//   layout as the SDPB above, so A and B see the same bytes.
//------------------------------------------------------------------------
module dbufsec16 (
    output reg [ 7:0] douta,
    output reg [15:0] doutb,
    input             clka, ocea, cea, reseta, wrea,
    input             clkb, oceb, ceb, resetb, wreb,
    input      [ 8:0] ada,
    input      [ 7:0] dina,
    input      [ 7:0] adb,
    input      [15:0] dinb
);
    localparam BITS = 8 * 512;
    reg [BITS-1:0] mem;

    initial begin
        mem   = {BITS{1'b0}};
        douta = 8'h00;
        doutb = 16'h0000;
    end

    always @(posedge clka or posedge reseta)
        if (reseta)   douta <= 8'h00;
        else if (cea) begin
            if (wrea) mem[ada*8 +: 8] <= dina;
            else      douta           <= mem[ada*8 +: 8];
        end

    always @(posedge clkb or posedge resetb)
        if (resetb)   doutb <= 16'h0000;
        else if (ceb) begin
            if (wreb) mem[adb*16 +: 16] <= dinb;
            else      doutb             <= mem[adb*16 +: 16];
        end
endmodule

//------------------------------------------------------------------------
// DPB - the raw Gowin dual-port block RAM primitive.
//
// Most of the vendor IP is replaced at the module boundary above, but
// mister/sector_dpram.v is generated IP that sits outside tang/src/ip/
// and instantiates DPB directly, so the primitive itself has to exist.
// Yosys's Gowin cell library ships SP and rPLL but not DPB.
//
// Modelled for the configuration the design actually uses - BIT_WIDTH 8
// on both ports, WRITE_MODE 00 (normal, no write-through), READ_MODE 0
// (no output register).  The address shift follows Gowin's convention:
// an 8-bit port addresses through AD[13:3].
//------------------------------------------------------------------------
module DPB (
    output reg [17:0] DOA,
    output reg [17:0] DOB,
    input             CLKA, OCEA, CEA, RESETA, WREA,
    input             CLKB, OCEB, CEB, RESETB, WREB,
    input      [ 2:0] BLKSELA,
    input      [ 2:0] BLKSELB,
    input      [13:0] ADA,
    input      [17:0] DIA,
    input      [13:0] ADB,
    input      [17:0] DIB
);
    parameter READ_MODE0  = 1'b0;
    parameter READ_MODE1  = 1'b0;
    parameter WRITE_MODE0 = 2'b00;
    parameter WRITE_MODE1 = 2'b00;
    parameter BIT_WIDTH_0 = 8;
    parameter BIT_WIDTH_1 = 8;
    parameter BLK_SEL_0   = 3'b000;
    parameter BLK_SEL_1   = 3'b000;
    parameter RESET_MODE  = "SYNC";

    // Address shift for a given port width, per Gowin's BSRAM addressing.
    function integer shift_of;
        input integer w;
        begin
            if      (w <= 1) shift_of = 0;
            else if (w <= 2) shift_of = 1;
            else if (w <= 4) shift_of = 2;
            else if (w <= 9) shift_of = 3;
            else             shift_of = 4;
        end
    endfunction

    localparam SHA = shift_of(BIT_WIDTH_0);
    localparam SHB = shift_of(BIT_WIDTH_1);

    // 18 Kbit, held as the widest word each port can ask for.
    reg [17:0] mem [0:2047];

    wire [13:0] aa = ADA >> SHA;
    wire [13:0] ab = ADB >> SHB;
    wire        sela = (BLKSELA == BLK_SEL_0);
    wire        selb = (BLKSELB == BLK_SEL_1);

    integer i;
    initial begin
        for (i = 0; i < 2048; i = i + 1) mem[i] = 18'd0;
        DOA = 18'd0;
        DOB = 18'd0;
    end

    always @(posedge CLKA)
        if (RESETA)      DOA <= 18'd0;
        else if (CEA && sela) begin
            if (WREA) mem[aa] <= DIA;      // WRITE_MODE 00: DO holds
            else      DOA     <= mem[aa];
        end

    always @(posedge CLKB)
        if (RESETB)      DOB <= 18'd0;
        else if (CEB && selb) begin
            if (WREB) mem[ab] <= DIB;
            else      DOB     <= mem[ab];
        end
endmodule
