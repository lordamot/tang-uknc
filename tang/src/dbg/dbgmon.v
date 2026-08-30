// dbgmon.v - board diagnostics out of the USB-C serial console.
//
// Pin 69 is uart_tx into the Tang's own BL616, which presents it to the
// host as interface B of its FT2232 - /dev/ttyUSB1 on Linux.  Nothing in
// the machine transmits there (vp065's port is the UKNC's own C2 line and
// the software does not use it), so the line is free to carry numbers out
// of a running board.  That is the only measurement channel this design
// has: everything else about a fault has to be inferred from a picture and
// a loudspeaker.
//
// This module is deliberately dumb.  It prints NPROBE 16-bit words as
// lower-case hex, space separated, CR LF terminated, once every WIN
// clocks, and it knows nothing about what they mean - the counters and
// the min/max live in top.v, next to the signals they watch, and get
// snapshotted there.  Reusing it for the next fault is a matter of wiring
// different words into `probes`.
//
// win_tog toggles once a line, one clock before `probes` is latched.  It
// is a LEVEL, not a pulse, because the accumulators it tells to snapshot
// are on the 3.13 MHz PPU clock and a 20 ns pulse from this 50 MHz domain
// would be missed nine times in ten.  The consequence is that the line
// printed after a toggle carries the window that ENDED at the previous
// toggle - one window of latency, constant, so a change still lands in a
// known place.
//
// 12 words is 62 characters, 5.4 ms at 115200 baud, and at ten lines a
// second the line is idle 95% of the time.
module dbgmon #(
    parameter integer CLK_FRE = 50,         // MHz on `clk`
    parameter integer BAUD    = 115200,
    parameter integer NPROBE  = 12,
    parameter integer WIN     = 5000000     // clocks per line - 100 ms
)(
    input                        clk,
    input                        rst_n,
    input       [16*NPROBE-1:0]  probes,
    output reg                   win_tog,
    output                       tx_pin
);

// Five bits, not four.  NPROBE is 17 now, and a four-bit LASTP took
// NPROBE[3:0] = 1, so the printer emitted word 0 and went straight to the
// end of line - the board sent "db01" and nothing else, ten times a
// second, for a whole test run.  Anything up to 32 words fits here.
localparam [4:0] LASTP = NPROBE[4:0] - 5'd1;

localparam S_IDLE = 2'd0,   // between lines
           S_HEX  = 2'd1,   // four nibbles of one word
           S_SP   = 2'd2,   // the space after it
           S_EOL  = 2'd3;   // CR then LF

reg [31:0]             wcnt  = 32'd0;
reg [16*NPROBE-1:0]    snap  = {(16*NPROBE){1'b0}};
reg [15:0]             cur   = 16'd0;
reg [ 4:0]             pi    = 5'd0;    // which word
reg [ 2:0]             ki    = 3'd0;    // which nibble of it
reg [ 1:0]             st    = S_IDLE;
reg [ 7:0]             ch    = 8'd0;
reg                    vld   = 1'b0;

wire [4:0] pinext = pi + 5'd1;
wire       rdy;

function [7:0] hexchar;
    input [3:0] n;
    hexchar = (n < 4'd10) ? (8'h30 + {4'd0, n}) : (8'h57 + {4'd0, n});
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wcnt    <= 32'd0;
        st      <= S_IDLE;
        vld     <= 1'b0;
        win_tog <= 1'b0;
        pi      <= 5'd0;
        ki      <= 3'd0;
    end else begin
        vld <= 1'b0;

        // The window.  A line that has not finished printing when the next
        // one is due is not a case worth handling - the window is twenty
        // times the line - so the new line is simply skipped and the
        // counter restarts, which shows up as a missing line rather than
        // as garbage.
        if (wcnt >= WIN - 1) begin
            wcnt <= 32'd0;
            if (st == S_IDLE) begin
                win_tog <= ~win_tog;
                snap    <= probes;
                cur     <= probes[15:0];
                pi      <= 5'd0;
                ki      <= 3'd0;
                st      <= S_HEX;
            end
        end else begin
            wcnt <= wcnt + 32'd1;
        end

        // One character per uart_tx handshake.  vld is a single clock and
        // tx_data_ready is still high the cycle after it, so the !vld term
        // is what stops the same character going out twice.
        if (st != S_IDLE && rdy && !vld) begin
            vld <= 1'b1;
            case (st)
            S_HEX: begin
                ch  <= hexchar(cur[15:12]);
                cur <= {cur[11:0], 4'd0};
                if (ki == 3'd3) begin ki <= 3'd0; st <= S_SP; end
                else                  ki <= ki + 3'd1;
            end
            S_SP: begin
                ch <= 8'h20;
                if (pi == LASTP) begin
                    st <= S_EOL;
                    ki <= 3'd0;
                end else begin
                    pi  <= pinext;
                    cur <= snap[pinext*16 +: 16];
                    st  <= S_HEX;
                end
            end
            S_EOL: begin
                ch <= (ki == 3'd0) ? 8'h0d : 8'h0a;
                if (ki == 3'd0) ki <= 3'd1;
                else            st <= S_IDLE;
            end
            default: st <= S_IDLE;
            endcase
        end
    end
end

uart_tx #(
    .CLK_FRE  (CLK_FRE),
    .BAUD_RATE(BAUD)
) tx (
    .clk           (      clk),
    .rst_n         (    rst_n),
    .tx_data       (       ch),
    .tx_data_valid (      vld),
    .tx_data_ready (      rdy),
    .tx_pin        (   tx_pin)
);

endmodule
