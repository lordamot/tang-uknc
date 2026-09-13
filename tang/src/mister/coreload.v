//------------------------------------------------------------------------
// coreload.v - tang-ultima: the UART to the board's own BL616.
//
// The Tang Nano 20K's on-board BL616 - the chip behind the USB-C socket,
// the board's programmer - reaches this FPGA on its JTAG and on one UART:
// pin 69 is the FPGA's TX into it (its GPIO 13), pin 70 its TX back (its
// GPIO 11).  tang-ultima's stage 2 firmware in that chip listens on the
// UART and, told to, writes what it is sent into its own flash and loads
// it into this FPGA's SRAM over the JTAG - a core switch in seconds and
// no power cycle, the configuration flash untouched.
//
// This module is the MCU's way onto that UART, and nothing more: a TX
// FIFO it fills, a count and a copy of what came back, and a UART at
// BAUD between them and the pins.  The protocol the bytes carry belongs
// to the firmware at both ends (mnano/coreload.c, onboard/main.c), and
// it is built so that the FPGA never has to hand the MCU a byte STREAM:
// every answer from the far end is one byte, and the MCU reads it, and
// the status, as a single byte that is the same on every strobe of the
// command - the one read shape this link is known to get right.
//
// The MCU's stream, SYS CMD 11, first byte the sub-command:
//
//   00  status   {room, count[6:0]} on every strobe after it: `room` is
//                "the TX FIFO has 512 bytes free", `count` how many
//                bytes have arrived since the last flush, saturating
//   01  write    every byte after this one goes into the TX FIFO (the
//                MCU writes 512 at a time, when `room` says so)
//   02  last     the most recent byte that arrived, on every strobe
//   03  claim    one byte: 1 takes the TX pin for this module, 0 gives it
//                back to whatever else drives it (the UKNC's serial port
//                lives on the same pins; `active` is that claim)
//   04  flush    empty the TX FIFO, zero the count and the last byte
//
// The baud generator is a phase accumulator, so BAUD is met on average
// from any CLK_HZ; a bit edge is at most one clock late.
//------------------------------------------------------------------------

module coreload #(
    parameter CLK_HZ = 27000000,
    parameter BAUD   = 2000000
) (
    input            clk,
    input            reset,      // high while in reset

    // SYS CMD 11, forwarded by sysctrl.v
    input            stb,        // a payload byte has arrived
    input            first,      // ... and it is the sub-command
    input      [7:0] din,
    output reg [7:0] dout,

    output reg       active,     // the MCU has claimed the TX pin
    output reg       tx,         // pin 69, into the on-board BL616
    input            rx          // pin 70, out of it
);

localparam SUB_STATUS = 8'h00, SUB_WRITE = 8'h01, SUB_LAST = 8'h02,
           SUB_CLAIM  = 8'h03, SUB_FLUSH = 8'h04;

// 2^16 * BAUD / CLK_HZ, the accumulator's step (in 64 bits: the product
// is past 32)
localparam [63:0] INC64 = (64'd65536 * BAUD + CLK_HZ / 2) / CLK_HZ;
localparam [16:0] INC   = INC64[16:0];

// ---- the TX FIFO, 2 KB ------------------------------------------------
reg  [7:0] txm [0:2047];
reg [11:0] tx_wr, tx_rd;          // one bit wider than the address
wire [11:0] tx_used = tx_wr - tx_rd;
wire        tx_empty = (tx_wr == tx_rd);
wire        tx_full  = (tx_used == 12'd2048);
wire        room     = (tx_used <= 12'd1536);
reg  [7:0] txm_q;
always @(posedge clk) txm_q <= txm[tx_rd[10:0]];

// ---- the MCU's side --------------------------------------------------
reg  [7:0] sub;
reg        argd;                  // claim's one argument byte taken
reg  [6:0] rx_count;
reg  [7:0] rx_last;
wire [7:0] status = {room, rx_count};
wire flushing  = stb && first && (din == SUB_FLUSH);
wire mcu_write = stb && !first && (sub == SUB_WRITE) && !tx_full;
always @(posedge clk)
    if(mcu_write) txm[tx_wr[10:0]] <= din;

// ---- the transmitter -------------------------------------------------
reg [16:0] tacc;
reg  [3:0] tbit;                  // 0 idle, 1 start, 2..9 data, 10 stop
reg  [7:0] tsh;
reg        tload;
wire       ttick = tacc[16];

// ---- the receiver ----------------------------------------------------
reg  [2:0] rsync;
reg [16:0] racc;
reg  [3:0] rbit;                  // 0 idle, 1 start, 2..9 data, 10 stop
reg  [7:0] rsh;
wire       rtick = racc[16];
wire       rxs   = rsync[1];
always @(posedge clk) rsync <= {rsync[1:0], rx};

always @(posedge clk) begin
    if(reset) begin
        tx_wr <= 12'd0; tx_rd <= 12'd0;
        sub   <= 8'hff; argd <= 1'b0;
        dout  <= 8'h00;
        rx_count <= 7'd0; rx_last <= 8'h00;
        active <= 1'b0;
        tx    <= 1'b1;
        tacc  <= 17'd0; tbit <= 4'd0; tsh <= 8'h00; tload <= 1'b0;
        racc  <= 17'd0; rbit <= 4'd0; rsh <= 8'h00;
    end else begin
        //--------------------------------------------------------------
        // the MCU's stream.  The answers are set at the sub-command and
        // again at every strobe, so whichever byte the MCU reads carries
        // them - the flashwr.v status shape.
        //--------------------------------------------------------------
        if(stb) begin
            if(first) begin
                sub  <= din;
                argd <= 1'b0;
                case(din)
                SUB_STATUS: dout <= status;
                SUB_LAST:   dout <= rx_last;
                SUB_FLUSH: begin
                    tx_wr <= 12'd0; tx_rd <= 12'd0;
                    rx_count <= 7'd0; rx_last <= 8'h00;
                end
                default: ;
                endcase
            end else begin
                case(sub)
                SUB_STATUS: dout <= status;
                SUB_LAST:   dout <= rx_last;
                SUB_WRITE:  if(!tx_full) tx_wr <= tx_wr + 12'd1;   // mcu_write stored it
                SUB_CLAIM:  if(!argd) begin active <= din[0]; argd <= 1'b1; end
                default: ;
                endcase
            end
        end

        //--------------------------------------------------------------
        // TX: 8N1, LSB first, one bit per accumulator overflow.  tbit 1
        // is the start bit on the line, 2..9 the data bits, 10 the stop.
        //--------------------------------------------------------------
        tacc <= {1'b0, tacc[15:0]} + INC;
        tload <= 1'b0;
        if(tbit == 4'd0) begin
            tx <= 1'b1;
            if(tload && !flushing) begin
                tsh   <= txm_q;
                tx_rd <= tx_rd + 12'd1;
                tbit  <= 4'd1;
                tx    <= 1'b0;
                tacc  <= 17'd0;
            end else if(!tx_empty && !tload && !flushing)
                tload <= 1'b1;            // txm_q holds txm[tx_rd] next clock
        end else if(ttick) begin
            if(tbit <= 4'd8) begin        // start or data on the line: next data bit
                tx  <= tsh[0];
                tsh <= {1'b0, tsh[7:1]};
                tbit <= tbit + 4'd1;
            end else if(tbit == 4'd9) begin
                tx   <= 1'b1;             // the stop bit
                tbit <= 4'd10;
            end else
                tbit <= 4'd0;             // stop bit done, idle
        end

        //--------------------------------------------------------------
        // RX: a start edge sets the accumulator half a bit back, so the
        // ticks land in the middle of the start bit and of every bit
        // after it
        //--------------------------------------------------------------
        if(rbit == 4'd0) begin
            if(rsync[2] && !rxs) begin        // a falling edge: start
                racc <= 17'd32768;
                rbit <= 4'd1;
            end
        end else begin
            racc <= {1'b0, racc[15:0]} + INC;
            if(rtick) begin
                if(rbit == 4'd1) begin
                    rbit <= rxs ? 4'd0 : 4'd2;   // still low: a start bit
                end else if(rbit <= 4'd9) begin
                    rsh  <= {rxs, rsh[7:1]};
                    rbit <= rbit + 4'd1;
                end else begin
                    rbit <= 4'd0;
                    if(rxs && !flushing) begin   // a stop bit: keep the byte
                        rx_last <= rsh;
                        if(rx_count != 7'd127) rx_count <= rx_count + 7'd1;
                    end
                end
            end
        end
    end
end

endmodule
