`timescale 1ns/1ps
//========================================================================
// tb_fdd4.v - the floppy controller, before and after re-clocking.
//
// fdd4.v used to clock five flops off data signals (see the comment in
// it).  In Sep 2026 they were moved onto pin_25mhz_ck with enables.  This
// bench instantiates the old module (fdd4_old, fetched out of git by the
// Makefile) beside the new one, drives both with the same PPU-side
// commands and the same stand-in SD reader, and compares what the PPU
// would read: the sequence of distinct data_out words, the head position,
// the sectors requested, and the status lines - as sequences, since the
// new module is allowed to be one or two 25 MHz cycles later.
//========================================================================
module tb_fdd4;

reg clk = 1'b0;
always #19.943 clk = ~clk;           // 25.07 MHz

reg        init  = 1'b1;
reg [15:0] din   = 16'd0;
reg        write = 1'b0;
reg [1:0]  drive = 2'd0;
reg        motor = 1'b0, step = 1'b0, dir = 1'b0, head = 1'b0;
reg [3:0]  mount = 4'b0001;

// a stand-in SD reader: busy for 700 clocks after a request, then done,
// and it delivers a sector whose bytes are the sector number.  One per
// module - a shared one would go busy on the first module's request and
// that busy would cancel the other's, since the new module is a cycle
// behind.

`define PORTS(inst, r_start, r_sector, r_dout, r_valid, r_sync, r_crc, r_tr0, r_ind) \
    .pin_25mhz_ck(clk), .ppu_vm_init_i(init), .data_in(din), .data_out(r_dout), .write(write), \
    .drive(drive), .motor(motor), .step(step), .dir(dir), .head(head), \
    .valid(r_valid), .sync(r_sync), .crc_ok(r_crc), .rdy(), .tr0(r_tr0), .ind(r_ind), .led_init(), \
    .rstart(r_start), .wstart(), .rsector(r_sector), .rbusy(rbusy_``inst), .rdone(rdone_``inst), \
    .outen(outen_``inst), .outaddr(outaddr_``inst), .inbyte(inbyte_``inst), .outbyte(), .mount_dsk(mount)

wire [3:0] st_o, st_n;  wire [31:0] sec_o, sec_n;  wire [15:0] do_o, do_n;
wire v_o, v_n, s_o, s_n, c_o, c_n, t_o, t_n, i_o, i_n;
fdd4_old uo(`PORTS(o, st_o, sec_o, do_o, v_o, s_o, c_o, t_o, i_o));
fdd4     un(`PORTS(n, st_n, sec_n, do_n, v_n, s_n, c_n, t_n, i_n));

reg  rbusy_o, rdone_o, outen_o; reg [8:0] outaddr_o; reg [7:0] inbyte_o;
reg  rbusy_n, rdone_n, outen_n; reg [8:0] outaddr_n; reg [7:0] inbyte_n;
sd_stub rd_o(clk, st_o, sec_o, rbusy_o, rdone_o, outen_o, outaddr_o, inbyte_o);
sd_stub rd_n(clk, st_n, sec_n, rbusy_n, rdone_n, outen_n, outaddr_n, inbyte_n);

// event logs: every distinct data_out value, in order, and every request
reg [15:0] log_o [0:65535]; reg [15:0] log_n [0:65535];
integer no = 0, nn = 0;
reg [15:0] prev_o = 16'hFFFF, prev_n = 16'hFFFF;
reg [31:0] rq_o [0:4095]; reg [31:0] rq_n [0:4095];
integer ro = 0, rn = 0; reg [3:0] pst_o = 0, pst_n = 0;
always @(posedge clk) begin
    if (do_o != prev_o) begin log_o[no] = do_o; no = no + 1; prev_o = do_o; end
    if (do_n != prev_n) begin log_n[nn] = do_n; nn = nn + 1; prev_n = do_n; end
    if (|st_o && !(|pst_o)) begin rq_o[ro] = sec_o; ro = ro + 1; end
    if (|st_n && !(|pst_n)) begin rq_n[rn] = sec_n; rn = rn + 1; end
    pst_o <= st_o; pst_n <= st_n;
end

integer errors = 0, k;
task compare(input [255:0] what);
    begin
        if (no != nn) begin $display("  FAIL %0s: %0d distinct data_out words old, %0d new", what, no, nn); errors = errors + 1; end
        else begin
            for (k = 0; k < no; k = k + 1)
                if (log_o[k] !== log_n[k]) begin
                    if (errors < 10) $display("  FAIL %0s: word %0d old %h new %h", what, k, log_o[k], log_n[k]);
                    errors = errors + 1;
                end
            $display("  ok   %0s: %0d data_out words agree", what, no);
        end
        if (ro != rn) begin $display("  FAIL %0s: %0d sector requests old, %0d new", what, ro, rn); errors = errors + 1; end
        else begin
            for (k = 0; k < ro; k = k + 1)
                if (rq_o[k] !== rq_n[k]) begin $display("  FAIL %0s: request %0d old %0d new %0d", what, k, rq_o[k], rq_n[k]); errors = errors + 1; end
            $display("  ok   %0s: %0d sector requests agree", what, ro);
        end
        if (uo.no_trk !== un.no_trk) begin $display("  FAIL %0s: track old %0d new %0d", what, uo.no_trk, un.no_trk); errors = errors + 1; end
        else $display("  ok   %0s: track %0d", what, un.no_trk);
        no = 0; nn = 0; ro = 0; rn = 0;
    end
endtask

// status lines are combinational off the rotation counter, which is
// untouched; check they never disagree for more than a couple of cycles
integer dis = 0, dis_max = 0;
always @(posedge clk) begin
    if ({v_o,s_o,c_o,t_o,i_o} != {v_n,s_n,c_n,t_n,i_n}) dis = dis + 1; else dis = 0;
    if (dis > dis_max) dis_max = dis;
end

task pulse_step(input d);
    begin
        dir = d; @(negedge clk); step = 1'b1; repeat (8) @(negedge clk); step = 1'b0; repeat (8) @(negedge clk);
    end
endtask

initial begin
    repeat (20) @(negedge clk); init = 1'b0; repeat (20) @(negedge clk);

    $display("[tb_fdd4] motor on, two revolutions on track 5 head 0");
    motor = 1'b1;
    repeat (2 * 1600 * 361) @(negedge clk);        // 361 words a track, 1600 clocks a word
    compare("spin");

    $display("[tb_fdd4] step in 3, out 8 (past track 0), head 1, one revolution");
    pulse_step(1); pulse_step(1); pulse_step(1);
    repeat (1600 * 400) @(negedge clk);
    pulse_step(0); pulse_step(0); pulse_step(0); pulse_step(0); pulse_step(0); pulse_step(0); pulse_step(0); pulse_step(0);
    head = 1'b1;
    repeat (1600 * 400) @(negedge clk);
    compare("step");

    $display("[tb_fdd4] no disk in drive 1: no requests");
    drive = 2'd1;
    repeat (1600 * 400) @(negedge clk);
    if (ro != 0 || rn != 0) begin $display("  FAIL: requests with no disk"); errors = errors + 1; end
    compare("empty");

    $display("[tb_fdd4] motor off mid-word, on again");
    drive = 2'd0; repeat (1600 * 50 + 777) @(negedge clk);
    motor = 1'b0; repeat (3000) @(negedge clk); motor = 1'b1;
    repeat (1600 * 400) @(negedge clk);
    compare("restart");

    $display("[tb_fdd4] status lines disagreed for at most %0d consecutive cycles", dis_max);
    if (dis_max > 3) begin $display("  FAIL: status lines differ"); errors = errors + 1; end
    $display("[tb_fdd4] %0d error(s)", errors);
    $finish;
end
endmodule

module sd_stub(input clk, input [3:0] st, input [31:0] sec,
               output reg rbusy = 1'b0, output reg rdone = 1'b0, output reg outen = 1'b0,
               output reg [8:0] outaddr = 9'd0, output reg [7:0] inbyte = 8'd0);
integer busy_cnt = 0; reg [31:0] rsec = 0;
always @(posedge clk) begin
    rdone <= 1'b0; outen <= 1'b0;
    if (|st && !rbusy) begin rbusy <= 1'b1; busy_cnt <= 0; rsec <= sec; end
    else if (rbusy) begin
        busy_cnt <= busy_cnt + 1;
        if (busy_cnt >= 100 && busy_cnt < 612) begin outen <= 1'b1; outaddr <= busy_cnt - 100; inbyte <= rsec[7:0] ^ (busy_cnt - 100); end
        if (busy_cnt == 700) begin rbusy <= 1'b0; rdone <= 1'b1; end
    end
end
endmodule
