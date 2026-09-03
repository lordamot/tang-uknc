`timescale 1ns/1ps
//========================================================================
// tb_hwen.v - the two OSD "Hardware" switches that live in modules with
// no unit test of their own (Sep 2026):
//   - vp1-128fdd.v's fdd_en: on, 0177130/0177132 are acknowledged; off,
//     neither is, a write is not taken, and the rest of the page is
//     untouched either way
//   - vp1_120.v's lpt_data: the byte last written to port A of the printer
//     port, 0177100, which top.v mixes as the older Covox when the OSD
//     says so; the register stays on the bus whatever the OSD says, so
//     only the read-out is checked here, against word and byte writes
//
// The PPU wishbone is driven the way ppu.v's core drives it (tb_covox.v):
// strobe held five PPU clocks, address and data stable throughout.  The
// floppy controller runs on the PPU clock and vp1_120 on clk_25, as in
// top.v; both see the same bus.
//========================================================================
module tb_hwen;

reg clk = 1'b0;
always #159.5 clk = ~clk;          // the PPU clock, 3.134 MHz
reg mclk = 1'b0;
always #19.943 mclk = ~mclk;       // clk_25

reg         init = 1'b1;
reg  [16:0] adr  = 17'o0;
reg  [15:0] dat  = 16'o0;
reg         wre  = 1'b0;
reg  [ 1:0] sel  = 2'b11;
reg         stb  = 1'b0;
reg         fdd_en = 1'b1;

wire [15:0] fdd_dout, vp_dout;
wire        fdd_ack, vp_ack;
wire [ 7:0] lpt_data;
wire [15:0] disk_data_in;
wire        disk_write, disk_motor, disk_step, disk_dir, disk_head;
wire [ 1:0] disk_drive;

vp1_128fdd fdd (
    .ppu_vm_clk_p(clk), .ppu_vm_init_i(init),
    .ppu_wbm_adr_i(adr), .ppu_wbm_dat_i(dat), .ppu_wbm_dat_o(fdd_dout),
    .ppu_wbm_cyc_i(stb), .ppu_wbm_wre_i(wre), .ppu_wbm_stb_i(stb), .ppu_wbm_ack_o(fdd_ack),
    .data_in(16'o0), .data_out(disk_data_in), .write(disk_write),
    .drive(disk_drive), .motor(disk_motor), .step(disk_step), .dir(disk_dir), .head(disk_head),
    .valid(1'b0), .sync(1'b0), .crc_ok(1'b0), .rdy(1'b1), .tr0(1'b1), .ind(1'b0),
    .wrprt_dsk(4'b0000), .fdd_en(fdd_en));

wire cpu_virq, ppu_virq, cpu_wbi_stb_o, ppu_wbi_stb_o, cpu_ack, cpu_wbi_ack, ppu_wbi_ack;
wire [15:0] cpu_dout, cpu_wbi_dout, ppu_wbi_dout;
vp1_120 vp (
    .clk(mclk),
    .cpu_vm_init_i(1'b0), .cpu_vm_virq_o(cpu_virq),
    .cpu_wbm_adr_i(17'o0), .cpu_wbm_dat_i(16'o0), .cpu_wbm_dat_o(cpu_dout),
    .cpu_wbm_cyc_i(1'b0), .cpu_wbm_wre_i(1'b0), .cpu_wbm_sel_i(2'b11), .cpu_wbm_stb_i(1'b0), .cpu_wbm_ack_o(cpu_ack),
    .cpu_wbi_dat_o(cpu_wbi_dout), .cpu_wbi_ack_o(cpu_wbi_ack), .cpu_wbi_stb_i(1'b0), .cpu_wbi_stb_o(cpu_wbi_stb_o),
    .ppu_vm_init_i(init), .ppu_vm_virq_o(ppu_virq),
    .ppu_wbm_adr_i(adr), .ppu_wbm_dat_i(dat), .ppu_wbm_dat_o(vp_dout),
    .ppu_wbm_cyc_i(stb), .ppu_wbm_wre_i(wre), .ppu_wbm_sel_i(sel), .ppu_wbm_stb_i(stb), .ppu_wbm_ack_o(vp_ack),
    .ppu_wbi_dat_o(ppu_wbi_dout), .ppu_wbi_ack_o(ppu_wbi_ack), .ppu_wbi_stb_i(1'b0), .ppu_wbi_stb_o(ppu_wbi_stb_o),
    .lpt_data(lpt_data));

integer errors = 0;
reg acked_fdd, acked_vp;
reg [15:0] rd;

task bus(input w, input [16:0] a, input [15:0] d, input [1:0] s);
    begin
        acked_fdd = 0; acked_vp = 0;
        @(negedge clk); adr = a; dat = d; sel = s; wre = w; stb = 1'b1;
        repeat (5) begin @(posedge clk); #1; acked_fdd = acked_fdd | fdd_ack; acked_vp = acked_vp | vp_ack; if(fdd_ack) rd = fdd_dout; end
        @(negedge clk); stb = 1'b0; wre = 1'b0;
        repeat (2) @(posedge clk);
    end
endtask

task expect_fdd(input [16:0] a, input want, input [8*40-1:0] what);
    begin
        bus(1'b0, a, 16'o0, 2'b11);
        if(acked_fdd !== want) begin $display("FAIL: %0s: %06o ack=%0d, expected %0d", what, a, acked_fdd, want); errors = errors + 1; end
    end
endtask

task expect_lpt(input [7:0] v, input [8*40-1:0] what);
    if(lpt_data !== v) begin $display("FAIL: %0s: lpt_data %03o, expected %03o", what, lpt_data, v); errors = errors + 1; end
endtask

integer a;
initial begin
    repeat (4) @(posedge clk);
    init = 1'b0;
    repeat (4) @(posedge clk);

    //---- the floppy controller ----
    expect_fdd(17'o177130, 1'b1, "on: 177130");
    expect_fdd(17'o177132, 1'b1, "on: 177132");
    expect_fdd(17'o177134, 1'b0, "on: 177134 is not the controller");
    bus(1'b1, 17'o177130, 16'o000020, 2'b11);           // motor on
    if(!acked_fdd) begin $display("FAIL: on: write to 177130 not acknowledged"); errors = errors + 1; end
    if(disk_motor !== 1'b1) begin $display("FAIL: on: motor not set by the write"); errors = errors + 1; end

    fdd_en = 1'b0; repeat (2) @(posedge clk);
    expect_fdd(17'o177130, 1'b0, "off: 177130 must time out");
    expect_fdd(17'o177132, 1'b0, "off: 177132 must time out");
    bus(1'b1, 17'o177130, 16'o000000, 2'b11);           // would stop the motor
    if(acked_fdd) begin $display("FAIL: off: write to 177130 acknowledged"); errors = errors + 1; end
    if(disk_motor !== 1'b1) begin $display("FAIL: off: a write landed (motor changed)"); errors = errors + 1; end
    // nothing else on the page answers from the controller, on or off
    for(a = 17'o177000; a <= 17'o177776; a = a + 2) begin
        bus(1'b0, a, 16'o0, 2'b11);
        if(acked_fdd) begin $display("FAIL: off: %06o acknowledged by the floppy controller", a); errors = errors + 1; end
    end
    fdd_en = 1'b1; repeat (2) @(posedge clk);
    expect_fdd(17'o177130, 1'b1, "back on: 177130");
    bus(1'b1, 17'o177130, 16'o000000, 2'b11);
    if(disk_motor !== 1'b0) begin $display("FAIL: back on: write did not land"); errors = errors + 1; end

    //---- the printer port byte ----
    expect_lpt(8'o000, "after init");
    bus(1'b1, 17'o177100, 16'o000125, 2'b11);           // a word: the low byte is port A
    if(!acked_vp) begin $display("FAIL: write to 177100 not acknowledged"); errors = errors + 1; end
    expect_lpt(8'o125, "word write to 177100");
    bus(1'b1, 17'o177101, 16'o000252, 2'b10);           // the odd byte is port B
    expect_lpt(8'o125, "byte write to 177101 leaves port A");
    bus(1'b1, 17'o177100, 16'o000377, 2'b01);           // a byte to port A
    expect_lpt(8'o377, "byte write to 177100");
    bus(1'b1, 17'o177102, 16'o000000, 2'b11);           // port C
    expect_lpt(8'o377, "write to 177102 leaves port A");
    bus(1'b0, 17'o177100, 16'o0, 2'b11);
    if(!acked_vp) begin $display("FAIL: read of 177100 not acknowledged"); errors = errors + 1; end

    if(errors == 0) $display("PASS: FDD controller switch (177130/2 on and off, writes held off, the page clean) and printer port A read-out");
    else $display("FAIL: %0d errors", errors);
    $finish;
end
endmodule
