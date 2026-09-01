`timescale 1ns/1ps
//========================================================================
// tb_aberrant.v - a unit test for the Aberrant sound module's write path.
//
// The full-machine testbench cannot reach this: it has no SD card, so no
// game or player ever runs, and the boot ROM never touches the AYs.  That
// left the whole write path unexercised while three separate bugs were
// guessed at from the outside.  This drives the wishbone port the way
// ppu.v's core really drives it - measured with +BUSTRACE on the full
// machine: the strobe is held for four to six of aberrant's clocks with
// the address, data and sel stable throughout, reads always sel=11, and
// byte writes sel=01 or 10 by adr[0].
//
// The protocol under test, from aberranthacker/aberrant_sound_module:
//   word write to 0177360/2/4 -> latches an AY register NUMBER
//   byte write to the same    -> writes DATA into that register
//========================================================================
module tb_aberrant;

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
wire [11:0] m_ch;

aberrant dut (
    .ppu_vm_clk_p (clk), .ppu_vm_init_i(init),
    .ppu_wbm_adr_i(adr), .ppu_wbm_dat_i(dat), .ppu_wbm_dat_o(dout),
    .ppu_wbm_cyc_i(cyc), .ppu_wbm_wre_i(wre), .ppu_wbm_sel_o(sel),
    .ppu_wbm_stb_i(stb), .ppu_wbm_ack_o(ack),
    .m_channel(m_ch));

integer errors = 0;

// One bus cycle, strobe held five clocks as the real master holds it.
task bus_write(input [16:0] a, input [15:0] d, input [1:0] s);
    begin
        @(negedge clk); adr = a; dat = d; sel = s; wre = 1'b1; cyc = 1'b1; stb = 1'b1;
        repeat (5) @(posedge clk);
        @(negedge clk); stb = 1'b0; cyc = 1'b0; wre = 1'b0;
        repeat (2) @(posedge clk);
    end
endtask

// Set AY register `r` of the chip at `a` to `v`: word write then byte write.
task ay_set(input [16:0] a, input [7:0] r, input [7:0] v);
    begin
        bus_write(a, {8'd0, r}, 2'b11);   // word  -> register number
        bus_write(a, {8'd0, v}, 2'b01);   // byte  -> data
    end
endtask

task check_reg(input [255:0] name, input [7:0] got, input [7:0] want);
    begin
        if (got !== want) begin
            $display("  FAIL %0s: got %o want %o", name, got, want);
            errors = errors + 1;
        end else $display("  ok   %0s = %o", name, got);
    end
endtask

integer i;
reg [11:0] lmin, lmax;

initial begin
    repeat (10) @(posedge clk);
    init = 1'b0;
    repeat (10) @(posedge clk);

    $display("[tb_aberrant] programming AY1 at 0177360 for a tone on A");
    ay_set(17'o177360, 8'd0,  8'd200);   // R0  tone A fine
    ay_set(17'o177360, 8'd1,  8'd0);     // R1  tone A coarse
    ay_set(17'o177360, 8'd7,  8'o76);    // R7  mixer: tone A on (active low)
    ay_set(17'o177360, 8'd8,  8'd15);    // R8  channel A amplitude, max

    $display("[tb_aberrant] AY1 register file after programming:");
    check_reg("R0",  dut.dd1.ymreg[0],  8'd200);
    check_reg("R1",  dut.dd1.ymreg[1],  8'd0);
    check_reg("R7",  dut.dd1.ymreg[7],  8'o76);
    check_reg("R8",  dut.dd1.ymreg[8],  8'd15);

    // Let it run and see whether the output actually moves.
    lmin = 12'hFFF; lmax = 12'd0;
    for (i = 0; i < 200000; i = i + 1) begin
        @(posedge clk);
        if (m_ch < lmin) lmin = m_ch;
        if (m_ch > lmax) lmax = m_ch;
    end
    $display("[tb_aberrant] m_channel over 200k clocks: min=%0d max=%0d", lmin, lmax);
    if (lmax == lmin) begin
        $display("  FAIL: output never moved - the AY is silent");
        errors = errors + 1;
    end else $display("  ok   the AY is oscillating");

    // The other two chips must be independently addressable.
    ay_set(17'o177362, 8'd8, 8'd11);
    ay_set(17'o177364, 8'd8, 8'd7);
    check_reg("AY2 R8", dut.dd2.ymreg[8], 8'd11);
    check_reg("AY3 R8", dut.dd3.ymreg[8], 8'd7);
    check_reg("AY1 R8 untouched", dut.dd1.ymreg[8], 8'd15);

    $display("[tb_aberrant] %0d error(s)", errors);
    $finish;
end
endmodule
