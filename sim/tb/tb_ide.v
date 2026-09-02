`timescale 1ns/1ps
//========================================================================
// tb_ide.v - a unit test for the IDE cartridge (src/ide/ide.v).
//
// Drives the PPU's wishbone the way ppu.v's core does it (strobe held,
// address and data stable), with a stand-in for sd_card.v that answers
// a request after a while and streams a sector whose bytes are a
// function of the LBA - so a wrong CHS-to-LBA, a wrong byte order or a
// missed inversion all show up as wrong words on the bus.  Every
// expected value is computed from UKNCBTL's Hard.cpp / Board.cpp
// conventions: register index = ~adr[3:1], every bus word inverted,
// data inverted once more for an "inverted" image.
//========================================================================
module tb_ide;

reg clk = 1'b0;
always #19.943 clk = ~clk;              // clk_25

reg         rst = 1'b1;
reg  [16:0] adr = 17'o0;
reg  [15:0] dat = 16'o0;
reg         wre = 1'b0;
reg  [ 1:0] sel = 2'b11;
reg         stb = 1'b0;
wire [15:0] dout;
wire        ack;
reg         cart_sel = 1'b0;
reg  [ 1:0] cart_bank = 2'd1;
reg         present = 1'b0;
reg  [ 7:0] spt = 8'd8, heads = 8'd2;
reg         inv = 1'b0;
reg         wprot = 1'b0;

wire        rstart, wstart, active;
wire [31:0] rsector;
reg         rbusy = 1'b0, rdone = 1'b0, outen = 1'b0;
reg  [ 8:0] outaddr = 9'd0;
reg  [ 7:0] inbyte = 8'd0;
wire [ 7:0] outbyte;

ide dut(
    .clk(clk), .rst(rst),
    .wbm_adr_i(adr), .wbm_dat_i(dat), .wbm_dat_o(dout), .wbm_wre_i(wre),
    .wbm_sel_i(sel), .wbm_stb_i(stb), .wbm_ack_o(ack),
    .cart_sel(cart_sel), .cart_bank(cart_bank),
    .hdd_present(present), .geo_spt(spt), .geo_heads(heads), .geo_inv(inv), .geo_mode(2'd0), .geo_cyl(16'd980), .wprot(wprot),
    .sd_rstart(rstart), .sd_wstart(wstart), .sd_sector(rsector),
    .sd_rbusy(rbusy), .sd_rdone(rdone), .sd_other(1'b0),
    .sd_outen(outen), .sd_outaddr(outaddr), .sd_inbyte(inbyte),
    .sd_outbyte(outbyte), .sd_active(active));

integer errors = 0;

// the SD stand-in: byte i of sector n is (n*7 + i) & 255
function [7:0] pat; input [31:0] n; input [8:0] i; pat = (n * 7 + i) & 8'hff; endfunction
reg [7:0] wbuf [0:511];
integer   nreq = 0, nwr = 0, k;
reg [31:0] last_sector; reg is_read;
always @(posedge clk) begin
    rdone <= 1'b0; outen <= 1'b0;
    if ((rstart || wstart) && !rbusy) begin
        rbusy <= 1'b1; last_sector = rsector; is_read = rstart;   // the request drops once busy is seen
        repeat (50) @(posedge clk);
        if (is_read) begin
            nreq = nreq + 1;
            for (k = 0; k < 512; k = k + 1) begin
                @(posedge clk); outen <= 1'b1; outaddr <= k; inbyte <= pat(last_sector, k);
            end
            @(posedge clk); outen <= 1'b0;
        end else begin
            nwr = nwr + 1;
            for (k = 0; k < 512; k = k + 1) begin
                @(posedge clk); outaddr <= k; @(posedge clk); @(posedge clk); wbuf[k] = outbyte;
            end
        end
        repeat (10) @(posedge clk);
        rdone <= 1'b1; rbusy <= 1'b0;
    end
end

// a PPU bus cycle: strobe held until ack, at least four PPU clocks (8 clk_25)
task bus(input w, input [16:0] a, input [15:0] d, output [15:0] r, output acked);
    integer t;
    begin
        @(negedge clk); adr = a; dat = d; wre = w; stb = 1'b1; acked = 0; t = 0;
        while (!acked && t < 40) begin @(posedge clk); #1; if (ack) begin acked = 1; r = dout; end t = t + 1;
            if ($test$plusargs("DBG") && t < 6) $display("    [bus] t=%0d adr=%o stb=%b ce=%b ce_old=%b is_io=%b ack=%b st=%0d hp=%b cs=%b", t, adr, stb, dut.ce, dut.ce_old, dut.is_io, ack, dut.st, dut.hdd_present, dut.cart_sel); end
        repeat (2) @(negedge clk); stb = 1'b0; wre = 1'b0;
        repeat (3) @(posedge clk);
    end
endtask
// IDE register access: register n sits at 0110000 + (~n & 7) * 2
task regwr(input [2:0] n, input [7:0] v);
    reg [15:0] r; reg a;
    begin bus(1, {1'b0, 12'h900, ~n, 1'b0}, ~{8'hff, v}, r, a);
          if (!a) begin $display("  FAIL: no ack writing register %0d", n); errors = errors + 1; end end
endtask
task regrd(input [2:0] n, output [7:0] v);
    reg [15:0] r; reg a;
    begin bus(0, {1'b0, 12'h900, ~n, 1'b0}, 16'd0, r, a);
          if (!a) begin $display("  FAIL: no ack reading register %0d", n); errors = errors + 1; end
          v = ~r[7:0];
          if (r[15:8] !== 8'h00) begin $display("  FAIL: register %0d high byte %h, want 00", n, r[15:8]); errors = errors + 1; end end
endtask
task datard(output [15:0] v);
    reg a; begin bus(0, 17'o0110016, 16'd0, v, a); if (!a) begin $display("  FAIL: no ack on data"); errors = errors + 1; end end
endtask
task datawr(input [15:0] v);
    reg [15:0] r; reg a; begin bus(1, 17'o0110016, v, r, a); if (!a) begin $display("  FAIL: no ack on data write"); errors = errors + 1; end end
endtask
task check(input [255:0] what, input [31:0] got, input [31:0] want);
    begin if (got !== want) begin $display("  FAIL %0s: got %h want %h", what, got, want); errors = errors + 1; end
          else $display("  ok   %0s = %h", what, got); end
endtask
task wait_ready;   // poll status until BUSY clears
    reg [7:0] s; integer t;
    begin t = 0; s = 8'h80; while (s[7] && t < 2000) begin regrd(7, s); t = t + 1; end
          if (s[7]) begin $display("  FAIL: still BUSY"); errors = errors + 1; end end
endtask

reg [15:0] r; reg a; reg [7:0] s; integer i; reg [15:0] w;
initial begin
    repeat (5) @(negedge clk); rst = 1'b0; repeat (5) @(negedge clk);

    $display("[tb_ide] no disk, cartridge mode: the window must not answer");
    cart_sel = 1'b1; bus(0, 17'o0100000, 0, r, a); check("ack with no disk", a, 0);

    $display("[tb_ide] disk mounted: ROM bank 1 word 0, bank 2 word 0");
    present = 1'b1; repeat (100) @(negedge clk);
    bus(0, 17'o0100000, 0, r, a); check("rom[0] ack", a, 1); check("rom[0]", r, 16'h00A0);
    bus(0, 17'o0100002, 0, r, a); check("rom[1]", r, 16'h8D17);
    cart_bank = 2'd2; bus(0, 17'o0100000, 0, r, a); check("bank2 rom[4096]", r, dut.rom.mem[4096]);
    cart_bank = 2'd1;
    cart_sel = 1'b0; bus(0, 17'o0100000, 0, r, a); check("ack outside cart mode", a, 0); cart_sel = 1'b1;

    $display("[tb_ide] status after reset: READY|SEEK");
    regrd(7, s); check("status", s, 8'h50);

    $display("[tb_ide] IDENTIFY");
    regwr(7, 8'hEC); wait_ready; regrd(7, s); check("status DRQ", s & 8'h08, 8'h08);
    datard(w); check("ident word 0: ~045a on the bus", w, 32'h0000fba5);   // buffer holds ~ident, bus = buffer
    datard(w); check("ident word 1: ~980", w, 32'h0000fc2b);
    for (i = 2; i < 27; i = i + 1) datard(w);
    datard(w); check("ident word 27: ~UK", w, 32'h0000aab4);
    for (i = 28; i < 256; i = i + 1) datard(w);
    regrd(7, s); check("DRQ dropped after 256 words", s & 8'h08, 8'h00);

    $display("[tb_ide] READ 2 sectors at C=2 H=1 S=3, spt 8, heads 2: LBA 42, 43");
    regwr(2, 8'd2); regwr(3, 8'd3); regwr(4, 8'd2); regwr(5, 8'd0); regwr(6, 8'ha1);
    regwr(7, 8'h20); wait_ready; check("sector requested", last_sector, 42);
    regrd(7, s); check("status DRQ|READY|SEEK", s & 8'hd8, 8'h58);
    for (i = 0; i < 256; i = i + 1) begin datard(w); if (w !== {pat(42, 2*i+1), pat(42, 2*i)}) begin
        if (errors < 5) $display("  FAIL sector 42 word %0d: %h want %h", i, w, {pat(42,2*i+1), pat(42,2*i)}); errors = errors + 1; end end
    $display("  ok   sector 42 read back");
    wait_ready; check("second sector requested", last_sector, 43);
    regrd(3, s); check("sector number advanced", s, 8'd4);
    for (i = 0; i < 256; i = i + 1) begin datard(w); if (w !== {pat(43, 2*i+1), pat(43, 2*i)}) begin
        if (errors < 10) $display("  FAIL sector 43 word %0d: %h", i, w); errors = errors + 1; end end
    $display("  ok   sector 43 read back");
    regrd(2, s); check("sector count exhausted", s, 8'd0);

    $display("[tb_ide] inverted image: the same read comes back inverted");
    inv = 1'b1; regwr(2, 8'd1); regwr(7, 8'h20); wait_ready;
    datard(w); check("inverted word 0", w, {16'd0, ~{pat(last_sector, 1), pat(last_sector, 0)}});
    for (i = 1; i < 256; i = i + 1) datard(w);
    inv = 1'b0;

    $display("[tb_ide] WRITE 1 sector at C=0 H=0 S=1: LBA 0");
    regwr(2, 8'd1); regwr(3, 8'd1); regwr(4, 8'd0); regwr(5, 8'd0); regwr(6, 8'ha0);
    regwr(7, 8'h30); regrd(7, s); check("DRQ for write data", s & 8'h08, 8'h08);
    for (i = 0; i < 256; i = i + 1) datawr({8'd0, i[7:0]} ^ 16'h5a00);
    wait_ready; check("write went to LBA", last_sector, 0); check("writes seen", nwr, 1);
    for (i = 0; i < 256; i = i + 1) if (wbuf[2*i] !== i[7:0] || wbuf[2*i+1] !== 8'h5a) begin
        if (errors < 15) $display("  FAIL written byte pair %0d: %h %h", i, wbuf[2*i], wbuf[2*i+1]); errors = errors + 1; end
    $display("  ok   written sector arrived in order");

    $display("[tb_ide] SET CONFIG spt 16 heads 4 then READ C=1 H=3 S=2 -> LBA (1*4+3)*16+1 = 113");
    regwr(2, 8'd16); regwr(6, 8'ha3); regwr(7, 8'h91);
    regwr(2, 8'd1); regwr(3, 8'd2); regwr(4, 8'd1); regwr(5, 8'd0); regwr(6, 8'ha3);
    regwr(7, 8'h20); wait_ready; check("LBA with new geometry", last_sector, 113);

    $display("[tb_ide] 16 heads: READ 2 at C=0 H=0 S=16 (spt 16) -> LBA 15 then head 1 sector 1 = LBA 16");
    regwr(2, 8'd16); regwr(6, 8'haf); regwr(7, 8'h91);          // spt 16, heads 16
    regwr(2, 8'd2); regwr(3, 8'd16); regwr(4, 8'd0); regwr(5, 8'd0); regwr(6, 8'ha0);
    regwr(7, 8'h20); wait_ready; check("first LBA", last_sector, 15);
    for (i = 0; i < 256; i = i + 1) datard(w);
    wait_ready; check("second LBA (head 1, not cylinder 1)", last_sector, 16);
    for (i = 0; i < 256; i = i + 1) datard(w);

    $display("[tb_ide] write-protected: WRITE completes with ERROR and no card write");
    wprot = 1'b1; regwr(2, 8'd1); regwr(3, 8'd1); regwr(4, 8'd0); regwr(5, 8'd0); regwr(6, 8'ha0);
    regwr(7, 8'h30); for (i = 0; i < 256; i = i + 1) datawr(16'h1234);
    wait_ready; regrd(7, s); check("status ERROR", s & 8'h01, 8'h01); regrd(1, s); check("error BAD_SECTOR", s, 8'h80);
    check("no write reached the card", nwr, 1); wprot = 1'b0;

    $display("[tb_ide] WDINIT's write sequence: count, sector, cyl lo, cyl hi, head, WRITE, 256 words with DRQ polls, FLUSH, then READ back");
    // geometry as the 16x63 image: SET CONFIG the way a driver would
    regwr(2, 8'd63); regwr(6, 8'haf); regwr(7, 8'h91);
    nwr = 0; nreq = 0;
    regwr(2, 8'd1); regwr(3, 8'd1); regwr(4, 8'd0); regwr(5, 8'd0); regwr(6, 8'ha0);
    regwr(7, 8'h30);
    regrd(7, s); check("no ERROR after WRITE cmd", s & 8'h01, 8'h00);
    for (i = 0; i < 256; i = i + 1) begin
        s = 8'h00; while (!s[3]) regrd(7, s);              // BIT #10: wait for DRQ
        datawr(16'h3f10 ^ i[15:0]);
    end
    regwr(7, 8'hE7);                                      // FLUSH CACHE, as the tool does
    regrd(7, s);
    wait_ready; check("write LBA for track 0 sector 1", last_sector, 0); check("one write", nwr, 1);
    regwr(2, 8'd1); regwr(3, 8'd1); regwr(4, 8'd0); regwr(5, 8'd0); regwr(6, 8'ha0);
    regwr(7, 8'h20); wait_ready; check("read-back LBA", last_sector, 0);

    $display("[tb_ide] %0d error(s)", errors);
    $finish;
end
endmodule
