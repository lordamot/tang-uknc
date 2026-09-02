//========================================================================
// sd_arbiter.v - one owner at a time for sd_card.v's request interface.
//
// sd_card.v has a single request interface and the MCU picks the drive
// out of a one-hot mask, so two requesters must never be visible to it
// at once.  The floppies (fdd4.v, slots 0-3) and the IDE cartridge
// (ide.v, slot 4) both want it.  The cartridge is granted when it asks,
// no floppy request is up and the card is idle; it keeps the grant until
// sd_card reports done.  While it owns the path the floppies' request
// bits are masked and fdd4.v is told to hold back (taken); while it does
// not, the cartridge is told (other).  The sector number, the write data
// and the incoming-byte strobe all follow the owner.  Sep 2026, after a
// WD home block landed in block 21 of a disk image - the floppy's sector
// number for the track RT-11 was reading at that moment.
//========================================================================
module sd_arbiter(
    input             clk,
    // the floppies
    input      [3:0]  fdd_rd, fdd_wr,
    input      [31:0] fdd_sector,
    input      [7:0]  fdd_wr_data,
    output            fdd_taken,       // to fdd4.v sd_taken
    output            fdd_outen,
    // the cartridge
    input             hdd_rd, hdd_wr,
    input      [31:0] hdd_sector,
    input      [7:0]  hdd_wr_data,
    output            hdd_other,       // to ide.v sd_other
    output            hdd_outen,
    // sd_card.v
    output     [4:0]  sd_rd, sd_wr,
    output     [31:0] sd_sector,
    output     [7:0]  sd_wr_data,
    input             sd_busy, sd_done, sd_outen,
    output            owner_hdd
);
wire hdd_req = hdd_rd | hdd_wr;
wire fdd_req = (|fdd_rd) | (|fdd_wr);
reg  owner = 1'b0;
always @(posedge clk)
    if (owner) begin
        if (sd_done) owner <= 1'b0;
    end else if (hdd_req && !fdd_req && !sd_busy)
        owner <= 1'b1;
assign owner_hdd  = owner;
assign sd_rd      = {hdd_rd & owner, fdd_rd & {4{~owner}}};
assign sd_wr      = {hdd_wr & owner, fdd_wr & {4{~owner}}};
assign sd_sector  = owner ? hdd_sector  : fdd_sector;
assign sd_wr_data = owner ? hdd_wr_data : fdd_wr_data;
assign fdd_outen  = sd_outen & ~owner;
assign hdd_outen  = sd_outen &  owner;
assign fdd_taken  = owner | hdd_req;
assign hdd_other  = fdd_req | (sd_busy & ~owner);
endmodule
