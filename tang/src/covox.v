// covox.v - the 8-bit DAC at 0177372 on the PPU bus: the "ЦАП (Covox)" of
// the Aberrant sound module's map, the "new covox" that UKNC players probe
// for before falling back to the printer port (blairecas/badapple:
// "LPT port A 177100 or new covox 177372 if detected").
//
// What software does with it, read out of the players rather than a data
// sheet, since none was found (Sep 2026):
//   - detects it the way every UKNC device is detected: a TST @#177372
//     under a trap-4 handler, and a bus timeout means absent.  So reads
//     are acknowledged, and answer with the last sample in the low byte.
//   - writes a sample as the low byte of a MOV, or as a MOVB; spcplay's
//     PPU loop is `mov R0,(R2)` with the sample in the low byte and R2 the
//     port.  Both are taken here: a word or a byte to 0177372 is the low
//     byte, a byte to 0177373 is the high byte.  Mono.
//   - the value is unsigned, 0..255, written straight.  Whether the real
//     DAC inverts it (the UKNC bus is inverted, the printer port too, and
//     UKNCBTL's Covox on 0177100 XORs with 0xff) only flips the polarity
//     of a waveform, which nothing can hear; it is not inverted here.
//
// One register, one clock, no state machine.  0177370/4/6 stay
// unacknowledged (MIDI, OPL2, unused on the real module); aberrant.v
// answers 0177360/2/4 and nothing else, and sim/tb/tb_covox.v checks the
// two never ack the same address.
//
// `en` is the OSD's "Covox" setting for this port (sysctrl 'c' bit 0):
// off, the DAC is not on the bus - 0177372 is a bus timeout, which is how
// a player learns to fall back to the printer port - and its sample is
// held at zero so nothing of it reaches the mixer.
module covox(
   input             clk,       // the PPU clock, as aberrant takes it
   input             init,
   input             en,        // the port exists (a level on mist_clk; the tool times it)
   input      [16:0] adr,
   input      [15:0] dat_i,
   output     [15:0] dat_o,
   input             wre,
   input      [ 1:0] sel,
   input             stb,
   output            ack,
   output reg [ 7:0] sample     // the DAC's input, for the mixer
);
initial sample = 8'd0;

wire ce = ({adr[15:1], 1'b0} == 16'o177372) && stb && en;   // 0177372, and 0177373 as its odd byte

assign ack   = ce;
assign dat_o = ce ? {8'd0, sample} : 16'd0;

always @(posedge clk)
    if(init || !en)
        sample <= 8'd0;
    else if(ce && wre) begin
        if(sel[0])      sample <= dat_i[7:0];
        else if(sel[1]) sample <= dat_i[15:8];
    end
endmodule
