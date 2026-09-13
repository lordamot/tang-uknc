//------------------------------------------------------------------------
// flashwr.v - tang-ultima: the configuration flash, from user logic.
//
// The Tang Nano 20K's SPI flash (Winbond W25Q64, 8 MB) hangs on the
// FPGA's MSPI pins.  The FPGA reads its own bitstream from it at
// power-up, and `-use_mspi_as_gpio` hands those pins to user logic once
// configuration is done - UG290 4.1.2 and table 4-2: "FASTRD_N, MCLK,
// MCS_N, MO, and MI are used as GPIO after configuration".  The same
// trick openFPGALoader uses to write this flash, only from a bitstream
// that came out of the flash rather than one pushed in over JTAG.
//
// This module is the MCU's way onto that bus.  It is deliberately NOT a
// flash controller: it knows nothing of erase, program or status, and
// the whole W25Q command set stays in the firmware (mnano/flashwr.c).
// What it offers is one transaction - a 512-byte buffer, "shift TX bytes
// of it out, then read RX bytes back into it, with CS held down".  The
// engine runs that at its own pace, MCLK at clk/4, so nothing here has
// to keep up with the 20 MHz m0s link, which a bit-level bridge would
// have had to.
//
// Why it exists: pulsing RECONFIG_N from user logic does not reload this
// FPGA (the pad loses its path to the configuration controller when it
// is reused as a GPIO; seen on the board 13 Sep 2026).  So a core switch
// writes the wanted machine to flash address 0 - which is what power-up
// always loads - and asks for a power cycle.
//
// The MCU's stream, SYS CMD 10, first byte the sub-command:
//
//   00  status        the next byte back is {7'b0, busy}
//   01  set pointer   two bytes, high then low: the buffer offset the
//                     MCU's own reads and writes start at
//   02  write         every byte after this one goes into the buffer,
//                     pointer post-incrementing
//   03  read          bytes come back from the buffer, pointer
//                     post-incrementing, one strobe behind as the rest
//                     of sysctrl.v's read commands are
//   04  go            four bytes - TX high, TX low, RX high, RX low -
//                     and the transaction starts.  The RX bytes land at
//                     offset 0, overwriting the command that asked for
//                     them.
//
// The MCU must not touch the buffer while `busy`; the one memory port is
// shared by a mux on that, not by arbitration.
//------------------------------------------------------------------------

module flashwr (
    input            clk,
    input            reset,      // high while in reset, as sysctrl.v's is

    // SYS CMD 10, forwarded by sysctrl.v
    input            stb,        // a payload byte has arrived
    input            first,      // ... and it is the sub-command
    input      [7:0] din,
    output reg [7:0] dout,

    // the flash, on MCLK 59, MCS_N 60, MO 61, MI 62
    output reg       mspi_clk,
    output reg       mspi_cs_n,
    output reg       mspi_do,
    input            mspi_di
);

localparam SUB_STATUS = 8'h00, SUB_PTR = 8'h01, SUB_WRITE = 8'h02,
           SUB_READ   = 8'h03, SUB_GO  = 8'h04;

localparam S_IDLE  = 3'd0, S_LOAD = 3'd1, S_TX  = 3'd2,
           S_RX    = 3'd3, S_RXWR = 3'd4, S_END = 3'd5;

// ---- the buffer ------------------------------------------------------
reg  [7:0] mem [0:511];
reg  [7:0] mem_q;
reg  [8:0] ptr;             // the MCU's offset
reg  [8:0] eptr;            // the engine's

// ---- the MCU's side --------------------------------------------------
reg  [7:0] sub;
reg  [1:0] arg;             // payload bytes of this sub-command seen so far
reg  [9:0] tx_len, rx_len;
reg        go;

// ---- the engine ------------------------------------------------------
reg  [2:0] st;
reg  [1:0] div;
reg  [2:0] bitn;
reg  [7:0] sh_out, sh_in;
reg  [9:0] left;

wire busy = (st != S_IDLE) || go;

// One port: the MCU's while idle, the engine's otherwise.  The engine
// only ever writes in S_RXWR, and reads through mem_q everywhere else.
wire [8:0] maddr = (st == S_IDLE) ? ptr : eptr;
wire       mwe   = (st == S_IDLE) ? (stb && !first && sub == SUB_WRITE)
                                  : (st == S_RXWR);
wire [7:0] mdin  = (st == S_IDLE) ? din : sh_in;

always @(posedge clk) begin
    if(mwe) mem[maddr] <= mdin;
    mem_q <= mem[maddr];
end

always @(posedge clk) begin
    if(reset) begin
        mspi_cs_n <= 1'b1;
        mspi_clk  <= 1'b0;
        mspi_do   <= 1'b0;
        st        <= S_IDLE;
        go        <= 1'b0;
        ptr       <= 9'd0;
        eptr      <= 9'd0;
        sub       <= 8'hff;
        arg       <= 2'd0;
        tx_len    <= 10'd0;
        rx_len    <= 10'd0;
        dout      <= 8'h00;
        div       <= 2'd0;
        bitn      <= 3'd0;
        sh_out    <= 8'h00;
        sh_in     <= 8'h00;
        left      <= 10'd0;
    end else begin
        //--------------------------------------------------------------
        // the MCU's stream
        //--------------------------------------------------------------
        if(stb) begin
            if(first) begin
                sub <= din;
                arg <= 2'd0;
                // answer at once, so that the byte after the
                // sub-command already carries what was asked for
                if(din == SUB_STATUS) dout <= {7'b0, busy};
                if(din == SUB_READ)   dout <= mem_q;
            end else begin
                case(sub)
                SUB_PTR: begin
                    if(arg == 2'd0)      ptr[8]   <= din[0];
                    else if(arg == 2'd1) ptr[7:0] <= din;
                    if(arg != 2'd3) arg <= arg + 2'd1;
                end
                SUB_WRITE: ptr <= ptr + 9'd1;      // mwe did the writing
                SUB_READ: begin
                    ptr  <= ptr + 9'd1;
                    dout <= mem_q;
                end
                SUB_GO: begin
                    if(arg == 2'd0)      tx_len[9:8] <= din[1:0];
                    else if(arg == 2'd1) tx_len[7:0] <= din;
                    else if(arg == 2'd2) rx_len[9:8] <= din[1:0];
                    else begin
                        rx_len[7:0] <= din;
                        go <= 1'b1;
                    end
                    if(arg != 2'd3) arg <= arg + 2'd1;
                end
                SUB_STATUS: dout <= {7'b0, busy};
                default: ;
                endcase
            end
        end

        //--------------------------------------------------------------
        // the transaction.  SPI mode 0 at clk/4: MO settles while MCLK
        // is low and the flash samples it, and MI, on the rising edge.
        // Every byte out of the buffer costs a load state, because the
        // memory is read a cycle after its address.
        //--------------------------------------------------------------
        case(st)
        S_IDLE:
            if(go) begin
                go        <= 1'b0;
                mspi_cs_n <= 1'b0;
                eptr      <= 9'd0;
                left      <= tx_len;
                div       <= 2'd0;
                st        <= (tx_len == 10'd0) ? S_END : S_LOAD;
            end

        S_LOAD:                         // two cycles: maddr, then mem_q
            if(div == 2'd1) begin
                sh_out <= mem_q;
                bitn   <= 3'd7;
                div    <= 2'd0;
                st     <= S_TX;
            end else
                div <= div + 2'd1;

        S_TX: begin
            if(div == 2'd0) begin mspi_clk <= 1'b0; mspi_do <= sh_out[bitn]; end
            if(div == 2'd2)       mspi_clk <= 1'b1;
            if(div == 2'd3) begin
                if(bitn == 3'd0) begin
                    mspi_clk <= 1'b0;
                    eptr     <= eptr + 9'd1;
                    left     <= left - 10'd1;
                    if(left == 10'd1) begin
                        if(rx_len != 10'd0) begin
                            eptr <= 9'd0;   // the answer overwrites the command
                            left <= rx_len;
                            bitn <= 3'd7;
                            st   <= S_RX;
                        end else
                            st <= S_END;
                    end else
                        st <= S_LOAD;
                end else
                    bitn <= bitn - 3'd1;
            end
            div <= div + 2'd1;
        end

        S_RX: begin
            if(div == 2'd0) begin mspi_clk <= 1'b0; mspi_do <= 1'b0; end
            if(div == 2'd2) begin
                mspi_clk <= 1'b1;
                sh_in    <= {sh_in[6:0], mspi_di};
            end
            if(div == 2'd3) begin
                if(bitn == 3'd0) begin
                    mspi_clk <= 1'b0;
                    bitn     <= 3'd7;
                    st       <= S_RXWR;
                end else
                    bitn <= bitn - 3'd1;
            end
            div <= div + 2'd1;
        end

        S_RXWR: begin                   // mwe writes mem[eptr] <= sh_in here
            eptr <= eptr + 9'd1;
            left <= left - 10'd1;
            div  <= 2'd0;
            st   <= (left == 10'd1) ? S_END : S_RX;
        end

        S_END: begin
            mspi_cs_n <= 1'b1;
            mspi_clk  <= 1'b0;
            st        <= S_IDLE;
        end

        default: st <= S_IDLE;
        endcase
    end
end

endmodule
