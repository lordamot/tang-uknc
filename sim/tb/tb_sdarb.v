`timescale 1ns/1ps
// tb_sdarb.v - the SD path arbiter: the floppies and the IDE cartridge
// must never both be visible to sd_card.v, whatever the timing.
module tb_sdarb;
reg clk = 0; always #19.943 clk = ~clk;
reg [3:0] fdd_rd = 0, fdd_wr = 0; reg hdd_rd = 0, hdd_wr = 0;
reg sd_busy = 0, sd_done = 0, sd_outen = 0;
wire [4:0] sd_rd, sd_wr; wire [31:0] sd_sector; wire [7:0] sd_wr_data;
wire fdd_taken, fdd_outen, hdd_other, hdd_outen, owner;
sd_arbiter a(.clk(clk), .fdd_rd(fdd_rd), .fdd_wr(fdd_wr), .fdd_sector(32'd21), .fdd_wr_data(8'hF0),
    .fdd_taken(fdd_taken), .fdd_outen(fdd_outen), .hdd_rd(hdd_rd), .hdd_wr(hdd_wr), .hdd_sector(32'd0),
    .hdd_wr_data(8'h0F), .hdd_other(hdd_other), .hdd_outen(hdd_outen), .sd_rd(sd_rd), .sd_wr(sd_wr),
    .sd_sector(sd_sector), .sd_wr_data(sd_wr_data), .sd_busy(sd_busy), .sd_done(sd_done), .sd_outen(sd_outen), .owner_hdd(owner));
integer errors = 0, both = 0;
// the invariant: never two requester bits at once, and the sector always the visible requester's
always @(posedge clk) begin
    if ((|sd_rd[3:0] | |sd_wr[3:0]) && (sd_rd[4] | sd_wr[4])) both = both + 1;
    if ((sd_rd[4] | sd_wr[4]) && sd_sector !== 32'd0) begin $display("  FAIL: hdd visible with sector %0d", sd_sector); errors = errors + 1; end
    if ((|sd_rd[3:0] | |sd_wr[3:0]) && sd_sector !== 32'd21) begin $display("  FAIL: fdd visible with sector %0d", sd_sector); errors = errors + 1; end
end
task check(input [255:0] what, input got, input want);
    begin if (got !== want) begin $display("  FAIL %0s: %b", what, got); errors = errors + 1; end else $display("  ok   %0s", what); end
endtask
// a stand-in card: busy 30 clocks after it sees any request, then done
always @(posedge clk) begin
    sd_done <= 0;
    if ((|sd_rd | |sd_wr) && !sd_busy) begin sd_busy <= 1; repeat (30) @(posedge clk); sd_done <= 1; sd_busy <= 0; end
end
initial begin
    $display("[tb_sdarb] same-cycle request from both: the floppy is served first, the cartridge waits");
    @(negedge clk); fdd_rd = 4'b0001; hdd_wr = 1;
    @(posedge clk); #1 check("floppy visible", |sd_rd[3:0], 1); check("cartridge held", sd_wr[4], 0); check("cartridge told other", hdd_other, 1);
    wait (sd_busy); @(negedge clk); fdd_rd = 0;                        // fdd4 drops its request on busy
    wait (sd_done); @(posedge clk); @(posedge clk); #1
    check("cartridge granted after the floppy", owner, 1); check("cartridge visible", sd_wr[4], 1); check("floppy told taken", fdd_taken, 1);
    wait (sd_busy); @(negedge clk); hdd_wr = 0;
    @(negedge clk); fdd_rd = 4'b0010;                                   // a floppy request during the cartridge's transfer
    @(posedge clk); #1 check("floppy masked while cartridge owns", |sd_rd[3:0], 0);
    wait (sd_done); @(posedge clk); @(posedge clk); #1 check("owner released", owner, 0); check("floppy now visible", |sd_rd[3:0], 1);
    wait (sd_busy); @(negedge clk); fdd_rd = 0; wait (sd_done);
    $display("[tb_sdarb] cartridge alone");
    @(negedge clk); hdd_rd = 1; @(posedge clk); @(posedge clk); #1 check("granted at once", owner, 1);
    wait (sd_busy); @(negedge clk); hdd_rd = 0; wait (sd_done); @(posedge clk); @(posedge clk); #1 check("released", owner, 0);
    check("never both visible", both != 0, 0);
    $display("[tb_sdarb] %0d error(s)", errors); $finish;
end
endmodule
