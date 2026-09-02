`timescale 1ns/1ps
//========================================================================
// tb_covox.v - the 8-bit DAC at 0177372 (covox.v) beside the Aberrant.
//
// Drives the PPU wishbone the way ppu.v's core does (see tb_aberrant.v:
// strobe held five clocks, word reads sel=11, byte writes sel=01/10 by
// adr[0]) and checks:
//   - a word write, a low-byte write and a high-byte write each land
//   - a read is acknowledged and returns the sample in the low byte
//   - over the whole 0177360-0177377 range, no address is acknowledged by
//     both the Covox and the Aberrant, and 0177366/70/74/76 by neither
//     (a player probing for MIDI or an OPL2 must get its bus timeout)
//========================================================================
module tb_covox;

reg clk = 1'b0;
always #159.5 clk = ~clk;

reg         init = 1'b1;
reg  [16:0] adr  = 17'o0;
reg  [15:0] dat  = 16'o0;
reg         cyc  = 1'b0;
reg         wre  = 1'b0;
reg  [ 1:0] sel  = 2'b11;
reg         stb  = 1'b0;
wire [15:0] cvx_dout, ab_dout;
wire        cvx_ack, ab_ack;
wire [ 7:0] sample;
wire [11:0] m_ch;

covox dut (
    .clk(clk), .init(init), .adr(adr), .dat_i(dat), .dat_o(cvx_dout),
    .wre(wre), .sel(sel), .stb(stb), .ack(cvx_ack), .sample(sample));

aberrant ab (
    .ppu_vm_clk_p (clk), .ppu_vm_init_i(init),
    .ppu_wbm_adr_i(adr), .ppu_wbm_dat_i(dat), .ppu_wbm_dat_o(ab_dout),
    .ppu_wbm_cyc_i(cyc), .ppu_wbm_wre_i(wre), .ppu_wbm_sel_o(sel),
    .ppu_wbm_stb_i(stb), .ppu_wbm_ack_o(ab_ack),
    .m_channel(m_ch));

integer errors = 0;
reg acked_cvx, acked_ab;
reg [15:0] rd;

task bus_write(input [16:0] a, input [15:0] d, input [1:0] s);
    begin
        @(negedge clk); adr = a; dat = d; sel = s; wre = 1'b1; cyc = 1'b1; stb = 1'b1;
        repeat (5) @(posedge clk);
        @(negedge clk); stb = 1'b0; cyc = 1'b0; wre = 1'b0;
        repeat (2) @(posedge clk);
    end
endtask

// a read, five clocks of strobe; reports who acked and what the DAC answered
task bus_read(input [16:0] a);
    begin
        acked_cvx = 0; acked_ab = 0;
        @(negedge clk); adr = a; sel = 2'b11; wre = 1'b0; cyc = 1'b1; stb = 1'b1;
        repeat (5) begin @(posedge clk); #1; acked_cvx = acked_cvx | cvx_ack; acked_ab = acked_ab | ab_ack; rd = cvx_dout; end
        @(negedge clk); stb = 1'b0; cyc = 1'b0;
        repeat (2) @(posedge clk);
    end
endtask

task expect_sample(input [7:0] v, input [8*24-1:0] what);
    if(sample !== v) begin $display("FAIL: %0s: sample %03o, expected %03o", what, sample, v); errors = errors + 1; end
endtask

integer a;
initial begin
    repeat (4) @(posedge clk);
    init = 1'b0;
    repeat (4) @(posedge clk);
    expect_sample(8'o000, "after init");

    bus_write(17'o177372, 16'o000125, 2'b11);  expect_sample(8'o125, "word write");
    bus_write(17'o177372, 16'o000252, 2'b01);  expect_sample(8'o252, "low byte write");
    bus_write(17'o177373, 16'o036000, 2'b10);  expect_sample(8'o074, "high byte write");
    bus_write(17'o177372, 16'o177400, 2'b11);  expect_sample(8'o000, "word write, low byte 0");
    bus_write(17'o177372, 16'o000377, 2'b11);  expect_sample(8'o377, "word write, 377");

    bus_read(17'o177372);
    if(!acked_cvx) begin $display("FAIL: read of 177372 not acknowledged"); errors = errors + 1; end
    if(rd !== 16'o000377) begin $display("FAIL: read of 177372 returned %06o, expected 000377", rd); errors = errors + 1; end

    // the whole Aberrant range, word by word
    for(a = 17'o177360; a <= 17'o177376; a = a + 2) begin
        bus_read(a);
        if(acked_cvx && acked_ab) begin $display("FAIL: %06o acknowledged by both", a); errors = errors + 1; end
        case(a)
        17'o177360, 17'o177362, 17'o177364:
            if(!acked_ab || acked_cvx) begin $display("FAIL: %06o: ab=%0d cvx=%0d, expected the Aberrant alone", a, acked_ab, acked_cvx); errors = errors + 1; end
        17'o177372:
            if(acked_ab || !acked_cvx) begin $display("FAIL: %06o: ab=%0d cvx=%0d, expected the Covox alone", a, acked_ab, acked_cvx); errors = errors + 1; end
        default:
            if(acked_ab || acked_cvx) begin $display("FAIL: %06o acknowledged (ab=%0d cvx=%0d), must time out", a, acked_ab, acked_cvx); errors = errors + 1; end
        endcase
    end
    // a byte write to the AYs must not move the DAC, and vice versa
    bus_write(17'o177362, 16'o000007, 2'b01);  expect_sample(8'o377, "AY byte write leaves the DAC");
    bus_read(17'o177400);
    if(acked_cvx) begin $display("FAIL: 177400 acknowledged by the Covox"); errors = errors + 1; end

    if(errors == 0) $display("PASS: Covox at 177372 - word, low and high byte writes, read-back, and no shared ack over 177360-177376");
    $finish;
end
endmodule
