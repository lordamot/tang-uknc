//========================================================================
// ide.v - the УКНЦ IDE hard disk cartridge: Oleg H.'s "КНЖМД" controller
// with its WD ROM, as UKNCBTL emulates it (emubase/Hard.cpp, Board.cpp,
// Memory.cpp - the reference for every constant below).
//
// It lives in the PPU's ROM cartridge slot 1.  When R177054 puts window
// block 0 (0100000-0117777) into cartridge mode - bit 0 clear, bit 4
// clear, bits 2:1 the bank (1..3), bit 3 the slot - this module answers:
//
//   0100000-0107777   the ROM, bank (bits 2:1) - 1, 8 KB banks of a 24 KB
//                     image (tang/rom/ide_wdromv0110.bin -> ide_rom.v)
//   0110000-0117777   the IDE registers, which shadow the upper 4 KB of
//                     every bank while a disk is attached
//
// The register index is the INVERTED address bits 3:1 - 0110016 is the
// data register and 0110000 is status/command - and every word on the
// bus is inverted, both ways ("QBUS inverts the bits").  So a register
// reads as {8'h00, ~value} and a written value is ~bus[7:0].  Sector data
// is inverted once more when the image on the card is stored in the
// "inverted" form (a raw dump of a real drive: the drive holds ~software
// data), which the MCU detects from the first sector at mount time and
// reports with the geometry.  Net effect: the software always sees its
// own view of the disk, whichever way the image is stored.
//
// Addressing is CHS, as the driver does it; the LBA sent to the SD path
// is (cyl * heads + head) * spt + sector - 1, with spt and heads coming
// from the image's first sector via the MCU and overridable by the SET
// CONFIG command, exactly as in the emulator.  The cartridge exists only
// while a disk image is mounted (hdd_present): with none, the slot is
// empty and the window times out as on a machine without the board.
//
// Clocked on clk_25 with the PPU's bus sampled the way vp1_120 does it -
// strobe edge detected, address and data taken on that edge - so the
// crossing is the one test003.sdc analyses.  The SD side is the same
// clock as sd_card.v.
//========================================================================
module ide(
    input             clk,          // clk_25
    input             rst,          // PPU INIT, active high

    // the PPU's bus
    input      [16:0] wbm_adr_i,
    input      [15:0] wbm_dat_i,
    output reg [15:0] wbm_dat_o,
    input             wbm_wre_i,
    input      [ 1:0] wbm_sel_i,
    input             wbm_stb_i,
    output reg        wbm_ack_o,

    // the window, from ppu.v
    input             cart_sel,     // block 0 is in cartridge mode, slot 1
    input      [ 1:0] cart_bank,    // R177054[2:1], 1..3

    // the disk, from the MCU
    input             hdd_present,  // an image is mounted in slot 4
    input      [ 7:0] geo_spt,      // sectors per track, from sector 0
    input      [ 7:0] geo_heads,    // heads, from sector 0
    input             geo_inv,      // image stored inverted, as detected
    input      [15:0] geo_cyl,      // cylinders = file size / 512 / spt / heads, from the MCU
    input      [ 1:0] geo_mode,     // OSD override: 0 detected, 1 plain, 2 inverted
    input             wprot,        // OSD "HDD prot.": writes fail with ERROR, the card is untouched

    // the SD path, sd_card.v's request interface (clk_25)
    output reg        sd_rstart,
    output reg        sd_wstart,
    output reg [31:0] sd_sector,
    input             sd_rbusy,
    input             sd_rdone,
    input             sd_other,     // another requester is pending or busy
    input             sd_outen,     // a byte of our sector arrives (gated by top.v)
    input      [ 8:0] sd_outaddr,
    input      [ 7:0] sd_inbyte,
    output     [ 7:0] sd_outbyte,   // a byte of our sector for a write
    output            sd_active     // our transfer owns the SD path
);

//------------------------------------------------------------------------
// Constants, from Hard.cpp
//------------------------------------------------------------------------
localparam [7:0] ST_ERROR = 8'h01, ST_INDEX = 8'h02, ST_DRQ = 8'h08,
                 ST_SEEK  = 8'h10, ST_READY = 8'h40, ST_BUSY = 8'h80;
localparam [7:0] ER_NONE = 8'h00, ER_DEFAULT = 8'h01, ER_UNKNOWN = 8'h04,
                 ER_BADLOC = 8'h10, ER_BADSECT = 8'h80;
localparam [7:0] CMD_READ = 8'h20, CMD_READ1 = 8'h21, CMD_WRITE = 8'h30,
                 CMD_WRITE1 = 8'h31, CMD_SETCFG = 8'h91, CMD_IDENT = 8'hEC;

//------------------------------------------------------------------------
// Decode
//------------------------------------------------------------------------
wire in_window = (wbm_adr_i[15:13] == 3'b100);           // 0100000-0117777
wire ce        = wbm_stb_i && in_window && cart_sel && hdd_present;
wire is_io     = wbm_adr_i[12];                          // 0110000-0117777
wire [2:0] ridx = ~wbm_adr_i[3:1];                       // register index
wire [1:0] bank_m1 = cart_bank - 2'd1;
reg  ce_old = 1'b0;
reg  wr_byte;                                            // a write with the low byte

//------------------------------------------------------------------------
// The ROM.  Address is presented combinationally; the pROM registers it
// on every clock, so its output is valid one clock after the address
// settled, which is before the second cycle of any bus strobe.
//------------------------------------------------------------------------
wire [15:0] rom_dout;
ide_rom rom (
    .dout (rom_dout),
    .clk  (clk),
    .ce   (1'b1),
    .reset(1'b0),
    .ad   ({bank_m1, 1'b0, wbm_adr_i[11:1]})
);

//------------------------------------------------------------------------
// The sector buffer: 512 bytes.  Port A, bytes, is the SD card's side;
// port B, words, is the bus's.  A second instance of the floppy's IP.
//------------------------------------------------------------------------
reg  [7:0]  bufoff  = 8'd0;          // word index 0..255
reg         bwr     = 1'b0;
reg  [7:0]  bwaddr  = 8'd0;
reg  [15:0] bwdata  = 16'd0;
wire [15:0] bdout;
// The word the bus will read next is always addressed, so it is there
// when the strobe comes; while a write is going on the port carries
// that instead.
wire [7:0]  badb = bwr ? bwaddr : bufoff;

dbufsec16 buffer(
    .clka  (clk),
    .cea   (1'b1),
    .reseta(1'b0),
    .ada   (sd_outaddr),
    .wrea  (sd_outen),
    .dina  (sd_inbyte),
    .douta (sd_outbyte),
    .ocea  (1'b0),
    .oceb  (1'b0),
    .clkb  (clk),
    .ceb   (1'b1),
    .resetb(1'b0),
    .wreb  (bwr),
    .adb   (badb),
    .dinb  (bwdata),
    .doutb (bdout)
);

//------------------------------------------------------------------------
// Drive state
//------------------------------------------------------------------------
reg  [7:0]  status = ST_BUSY, error = ER_NONE;
reg  [8:0]  sectorcount = 9'd0;      // 1..256
reg  [7:0]  cursector = 8'd0, curheadreg = 8'd0;
reg  [3:0]  curhead = 4'd0;
reg  [15:0] curcyl = 16'd0;
reg  [7:0]  spt_r = 8'd0, heads_r = 8'd0;
reg  [7:0]  resetcnt = 8'd0;

// Transfer engine states
localparam [3:0] S_IDLE = 4'd0, S_RD_LBA1 = 4'd1, S_RD_LBA2 = 4'd2, S_RD_REQ = 4'd3,
                 S_RD_WAIT = 4'd4, S_WR_LBA1 = 4'd5, S_WR_LBA2 = 4'd6, S_WR_REQ = 4'd7,
                 S_WR_WAIT = 4'd8, S_ID_FILL = 4'd9;
reg  [3:0]  st = S_IDLE;
reg  [23:0] lba_t = 24'd0;
reg  [8:0]  fill = 9'd0;
assign sd_active = (st == S_RD_REQ) || (st == S_RD_WAIT) || (st == S_WR_REQ) || (st == S_WR_WAIT);

// The IDENTIFY sector, word by word, as Hard.cpp builds it - and
// inverted, as it inverts the buffer at the end.  Strings are stored
// with the first character in the high byte of each word.
function [15:0] ident;
    input [7:0] w;
    input [15:0] cyl; input [7:0] hd; input [7:0] sp;
    reg [31:0] total; reg [15:0] hs;
    begin
        total = cyl * hd * sp;
        hs    = hd * sp;
        case (w)
        8'd0:  ident = 16'h045a;
        8'd1:  ident = cyl;
        8'd3:  ident = {8'd0, hd};
        8'd6:  ident = {8'd0, sp};
        8'd10, 8'd11, 8'd12, 8'd13, 8'd14, 8'd15, 8'd16, 8'd17, 8'd18, 8'd19:
               ident = "00";                     // serial "0000000000"
        8'd23: ident = "1.";                     // firmware "1.0 "
        8'd24: ident = "0 ";
        8'd25, 8'd26: ident = "  ";
        8'd27: ident = "UK";                     // model "UKNC Nano Hard Disk"
        8'd28: ident = "NC";
        8'd29: ident = " N";
        8'd30: ident = "an";
        8'd31: ident = "o ";
        8'd32: ident = "Ha";
        8'd33: ident = "rd";
        8'd34: ident = " D";
        8'd35: ident = "is";
        8'd36: ident = "k ";
        8'd37, 8'd38, 8'd39, 8'd40, 8'd41, 8'd42, 8'd43, 8'd44, 8'd45, 8'd46:
               ident = "  ";
        8'd47: ident = 16'h8001;
        8'd49: ident = 16'h2f00;
        8'd53: ident = 16'd1;
        8'd54: ident = cyl;
        8'd55: ident = {8'd0, hd};
        8'd56: ident = {8'd0, sp};
        8'd57: ident = hs;                       // heads*spt, low word
        8'd58: ident = 16'd0;
        8'd60: ident = total[15:0];
        8'd61: ident = total[31:16];
        8'd100: ident = total[15:0];
        8'd101: ident = total[31:16];
        default: ident = 16'd0;
        endcase
    end
endfunction

// IDENTIFY reaches the software COMPLEMENTED, whatever form the image
// is in.  That is what the bus does to the drive's identify words on
// real hardware, and it is what the software expects: WDINIT's identify
// loop (build/wdinit.dsk, at 007702: MOV #177423,(R4) then MOV (R5),R0;
// COM R0) complements every word it reads, while its sector reads store
// the words as they come - because on the card the sectors are held
// complemented and the bus undoes that, whereas identify comes from the
// drive itself.  A build that put identify on the bus plain made WDINIT
// print 64555, 65525, 65501 - the complements of 980, 10 and 34 - and
// the WD ROM refuse a correct boot block.  So the buffer is loaded with
// ~identify ^ inv, and the data-register read's ^ inv leaves ~identify
// on the bus for either image form.  (Hard.cpp gets this right only for
// inverted images, the only ones anyone used with it.)
wire [15:0] numcyl = geo_cyl;

// Bus word for a register read: {8'h00, ~value}; for data: buffer ^ inv.
// The OSD's "HDD image" setting can overrule the detected form, which is
// a heuristic on twelve bytes of sector 0 (sdc.c, after Hard.cpp).
wire        inv_eff  = (geo_mode == 2'd1) ? 1'b0 : (geo_mode == 2'd2) ? 1'b1 : geo_inv;
wire [15:0] inv_mask = {16{inv_eff}};

// next CHS after a sector, Hard.cpp NextSector()
task next_sector;
    begin
        // Hard.cpp NextSector(): sectors are 1-based, heads compared in full
        // width (a 4-bit compare wrapped the head after every sector on a
        // 16-head geometry - found 2 Sep 2026 while reading for another bug)
        if ({1'b0, cursector} + 9'd1 > {1'b0, spt_r}) begin
            cursector <= 8'd1;
            if ({4'd0, curhead} + 8'd1 >= heads_r) begin
                curhead <= 4'd0;
                curcyl  <= curcyl + 16'd1;
            end else
                curhead <= curhead + 4'd1;
        end else
            cursector <= cursector + 8'd1;
    end
endtask

always @(posedge clk) begin
    ce_old    <= ce;
    bwr       <= 1'b0;
    sd_rstart <= sd_rstart;
    sd_wstart <= sd_wstart;

    if (rst || !hdd_present) begin
        status      <= ST_BUSY;
        error       <= ER_NONE;
        resetcnt    <= 8'd64;              // Reset(): BUSY, then READY|SEEK
        st          <= S_IDLE;
        sd_rstart   <= 1'b0;
        sd_wstart   <= 1'b0;
        bufoff      <= 8'd0;
        sectorcount <= 9'd0;
        spt_r       <= geo_spt;
        heads_r     <= geo_heads;
        wbm_ack_o   <= 1'b0;
        wbm_dat_o   <= 16'd0;
    end else begin
        // power-on / reset timing
        if (resetcnt != 8'd0) begin
            resetcnt <= resetcnt - 8'd1;
            if (resetcnt == 8'd1)
                status <= (status & ~ST_BUSY) | ST_READY | ST_SEEK;
        end

        //----------------------------------------------------------------
        // The bus.  ack rises on the second clock of a strobe and stays
        // until the strobe drops.
        //----------------------------------------------------------------
        if (!wbm_stb_i) begin
            wbm_ack_o <= 1'b0;
        end else if (ce && ce_old && !wbm_ack_o) begin
            wbm_ack_o <= 1'b1;
            if (!is_io) begin
                wbm_dat_o <= rom_dout;                          // ROM read (writes ack and drop)
            end else if (!wbm_wre_i) begin
                case (ridx)
                3'd0: begin                                      // DATA
                    wbm_dat_o <= bdout ^ inv_mask;
                    if (status[3]) begin
                        if (bufoff == 8'd255) begin              // sector consumed
                            bufoff <= 8'd0;
                            status <= status & ~ST_DRQ & ~ST_BUSY;
                            if (sectorcount != 9'd0) begin      // ContinueRead -> next sector
                                status <= (status & ~ST_DRQ) | ST_BUSY;
                                st     <= S_RD_LBA1;
                            end
                        end else
                            bufoff <= bufoff + 8'd1;
                    end
                end
                3'd1: wbm_dat_o <= {8'h00, ~error};
                3'd2: wbm_dat_o <= {8'h00, ~sectorcount[7:0]};
                3'd3: wbm_dat_o <= {8'h00, ~cursector};
                3'd4: wbm_dat_o <= {8'h00, ~curcyl[7:0]};
                3'd5: wbm_dat_o <= {8'h00, ~curcyl[15:8]};
                3'd6: wbm_dat_o <= {8'h00, ~curheadreg};
                3'd7: wbm_dat_o <= {8'h00, ~status};
                endcase
            end else begin
                case (ridx)
                3'd0: if (status[3]) begin                 // DATA write
                    bwr    <= 1'b1;
                    bwaddr <= bufoff;
                    bwdata <= wbm_dat_i ^ inv_mask;              // Board inverts, WritePort inverts back: stored = bus, or ~bus for an inverted image
                    if (bufoff == 8'd255) begin                  // ContinueWrite
                        bufoff <= 8'd0;
                        status <= (status & ~ST_DRQ) | ST_BUSY;
                        st     <= S_WR_LBA1;
                    end else
                        bufoff <= bufoff + 8'd1;
                end
                3'd1: ;                                          // precompensation, ignored
                3'd2: if (wbm_sel_i[0]) sectorcount <= (~wbm_dat_i[7:0] == 8'd0) ? 9'd256 : {1'b0, ~wbm_dat_i[7:0]};
                3'd3: if (wbm_sel_i[0]) cursector   <= ~wbm_dat_i[7:0];
                3'd4: if (wbm_sel_i[0]) curcyl[7:0] <= ~wbm_dat_i[7:0];
                3'd5: if (wbm_sel_i[0]) curcyl[15:8]<= ~wbm_dat_i[7:0];
                3'd6: if (wbm_sel_i[0]) begin curheadreg <= ~wbm_dat_i[7:0]; curhead <= ~wbm_dat_i[3:0]; end
                3'd7: if (wbm_sel_i[0]) begin                    // COMMAND
                    case (~wbm_dat_i[7:0])
                    CMD_READ, CMD_READ1: begin
                        status <= (status | ST_BUSY) & ~ST_DRQ & ~ST_ERROR;
                        st     <= S_RD_LBA1;
                    end
                    CMD_SETCFG: begin
                        spt_r   <= sectorcount[7:0];
                        heads_r <= {4'd0, curhead} + 8'd1;
                    end
                    CMD_WRITE, CMD_WRITE1: begin
                        bufoff <= 8'd0;
                        status <= (status | ST_DRQ) & ~ST_ERROR;     // a new command clears ERR, as on a drive
                    end
                    CMD_IDENT: begin
                        fill   <= 9'd0;
                        status <= (status | ST_BUSY) & ~ST_DRQ;
                        st     <= S_ID_FILL;
                    end
                    default: ;
                    endcase
                end
                endcase
            end
        end

        //----------------------------------------------------------------
        // The transfer engine
        //----------------------------------------------------------------
        case (st)
        S_IDLE: ;
        // read: LBA in two multiply stages, then the SD request
        S_RD_LBA1, S_WR_LBA1: begin
            lba_t <= curcyl * heads_r + {20'd0, curhead};
            st    <= (st == S_RD_LBA1) ? S_RD_LBA2 : S_WR_LBA2;
        end
        S_RD_LBA2, S_WR_LBA2: begin
            sd_sector <= lba_t * spt_r + {24'd0, cursector} - 32'd1;
            st        <= (st == S_RD_LBA2) ? S_RD_REQ : S_WR_REQ;
        end
        S_RD_REQ: begin
            // one requester at a time on the shared SD path: raise the
            // request when nobody else is up, keep it until the card has
            // gone busy on it (top.v's arbiter grants it in between)
            if (!sd_other && !sd_rbusy) sd_rstart <= 1'b1;
            if (sd_rstart && sd_rbusy) begin sd_rstart <= 1'b0; st <= S_RD_WAIT; end
        end
        S_RD_WAIT: if (sd_rdone) begin                            // ReadSectorDone
            status <= (status & ~ST_BUSY & ~ST_ERROR) | ST_DRQ | ST_SEEK;
            error  <= ER_NONE;
            bufoff <= 8'd0;
            if (sectorcount != 9'd0) sectorcount <= sectorcount - 9'd1;
            if (sectorcount > 9'd1) next_sector;
            st <= S_IDLE;
        end
        S_WR_REQ: begin
            if (wprot) begin
                // Hard.cpp WriteSectorDone() on a read-only image: no write,
                // ERROR with BAD_SECTOR, the buffer left as it is.
                status <= (status & ~ST_BUSY) | ST_ERROR | ST_DRQ | ST_SEEK;
                error  <= ER_BADSECT;
                bufoff <= 8'd0;
                st     <= S_IDLE;
            end else begin
                if (!sd_other && !sd_rbusy) sd_wstart <= 1'b1;
                if (sd_wstart && sd_rbusy) begin sd_wstart <= 1'b0; st <= S_WR_WAIT; end
            end
        end
        S_WR_WAIT: if (sd_rdone) begin                            // WriteSectorDone
            status <= (status & ~ST_BUSY & ~ST_ERROR) | ST_DRQ | ST_SEEK;
            error  <= ER_NONE;
            bufoff <= 8'd0;
            if (sectorcount != 9'd0) sectorcount <= sectorcount - 9'd1;
            if (sectorcount > 9'd1) next_sector;
            st <= S_IDLE;
        end
        S_ID_FILL: begin
            bwr    <= 1'b1;
            bwaddr <= fill[7:0];
            bwdata <= ~ident(fill[7:0], numcyl, heads_r, spt_r) ^ inv_mask;
            fill   <= fill + 9'd1;
            if (fill == 9'd255) begin
                bufoff      <= 8'd0;
                sectorcount <= 9'd1;
                status      <= (status | ST_DRQ | ST_SEEK | ST_READY) & ~ST_BUSY & ~ST_ERROR;
                st          <= S_IDLE;
            end
        end
        default: st <= S_IDLE;
        endcase
    end
end
endmodule
