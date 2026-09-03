`timescale 1ns/1ps
//========================================================================
// tb_kakave.v - the Kakave+ mouse (0177400) and RTC (0177410) registers
// (kakave.v), with hid.v in front of it the way top.v wires it, so that a
// USB report goes in as the MCU sends it over SPI.
//
// Drives the PPU wishbone the way ppu.v's core does (see tb_covox.v) and
// checks, against the sketch in build/rtc_kkve/ and the RT-11 programs
// beside it:
//   - only 0177400/1 and 0177410/1 are acknowledged in 0177000-0177777
//   - mouse: nothing gives 0; a report gives [dy L dx R] with dy inverted
//     to the PS/2 sense; a read clears; counts clip at +-63; buttons are
//     the current state; the command answers (0, 1 with and without a
//     mouse, 7, echo) come on the next read only
//   - RTC: the four-field set loads the clock, selectors 0-3 read it back,
//     a partial set changes nothing; the weekday is microDS3231's
//     (1 = Sunday); 28 Feb rolls to 29 Feb in 2024 and to 1 Mar in 2023;
//     31 Dec rolls the year; seven seconds are exactly 21937500 PPU clocks
//   - the OSD's field-at-a-time set (sysctrl 'y','m','d','h','n')
//   - a PPU reset clears a pending command and leaves the time alone
//========================================================================
module tb_kakave;

// the PPU clock, 3.134 MHz (the exact period does not matter: the second
// is checked in clocks, not in ns)
reg clk = 1'b0;
always #159.5 clk = ~clk;
// mist_clk, 25 MHz
reg mclk = 1'b0;
always #20 mclk = ~mclk;

reg         init = 1'b1;
reg  [16:0] adr  = 17'o0;
reg  [15:0] dat  = 16'o0;
reg         wre  = 1'b0;
reg  [ 1:0] sel  = 2'b11;
reg         stb  = 1'b0;
wire [15:0] dout;
wire        ack;

// hid.v side
reg         hrst      = 1'b1;
reg         hstrobe   = 1'b0;
reg         hstart    = 1'b0;
reg  [7:0]  hdata     = 8'd0;
wire [7:0]  hdout;
wire [5:0]  mouse_q;
wire [7:0]  keycode, js0, js1;
wire        hirq;
wire        rep_tgl;
wire [7:0]  rep_dx, rep_dy;

reg         mouse_present = 1'b0;
reg         set_tgl   = 1'b0;
reg  [2:0]  set_field = 3'd0;
reg  [7:0]  set_val   = 8'd0;

hid hd (
    .clk(mclk), .reset(hrst),
    .data_in_strobe(hstrobe), .data_in_start(hstart), .data_in(hdata), .data_out(hdout),
    .db9_port(6'd0), .irq(hirq), .iack(1'b0),
    .mouse(mouse_q), .keyboard(keycode), .joystick0(js0), .joystick1(js1),
    .mouse_rep_tgl(rep_tgl), .mouse_rep_dx(rep_dx), .mouse_rep_dy(rep_dy));

kakave dut (
    .clk(clk), .init(init), .adr(adr), .dat_i(dat), .dat_o(dout),
    .wre(wre), .sel(sel), .stb(stb), .ack(ack),
    .mouse_tgl(rep_tgl), .mouse_dx(rep_dx), .mouse_dy(rep_dy), .mouse_btns(mouse_q[5:4]),
    .mouse_present(mouse_present),
    .set_tgl(set_tgl), .set_field(set_field), .set_val(set_val));

integer errors = 0;
reg        acked;
reg [15:0] rd;

task bus_write(input [16:0] a, input [15:0] d, input [1:0] s);
    begin
        @(negedge clk); adr = a; dat = d; sel = s; wre = 1'b1; stb = 1'b1;
        repeat (5) @(posedge clk);
        @(negedge clk); stb = 1'b0; wre = 1'b0;
        repeat (2) @(posedge clk);
    end
endtask

task bus_read(input [16:0] a);
    begin
        acked = 0; rd = 16'hxxxx;
        @(negedge clk); adr = a; sel = 2'b11; wre = 1'b0; stb = 1'b1;
        repeat (5) begin @(posedge clk); #1; if(ack) begin acked = 1; rd = dout; end end
        @(negedge clk); stb = 1'b0;
        repeat (2) @(posedge clk);
    end
endtask

task expect_rd(input [16:0] a, input [15:0] v, input [8*40-1:0] what);
    begin
        bus_read(a);
        if(!acked) begin $display("FAIL: %0s: %06o not acknowledged", what, a); errors = errors + 1; end
        else if(rd !== v) begin $display("FAIL: %0s: %06o read %06o (%04x), expected %06o (%04x)", what, a, rd, rd, v, v); errors = errors + 1; end
    end
endtask

// one SPI byte into hid.v: the first byte of a transaction carries start
task hid_byte(input start, input [7:0] b);
    begin
        @(negedge mclk); hstart = start; hdata = b; hstrobe = 1'b1;
        @(negedge mclk); hstrobe = 1'b0; hstart = 1'b0;
    end
endtask

// a mouse report as usb_host.c's mouse_parse() sends it
task hid_mouse(input [7:0] btns, input [7:0] dx, input [7:0] dy);
    begin
        hid_byte(1'b1, 8'd2);
        hid_byte(1'b0, btns);
        hid_byte(1'b0, dx);
        hid_byte(1'b0, dy);
        repeat (4) @(posedge clk);      // through the synchroniser
    end
endtask

// the RTC read pair: selector then read
task rtc_expect(input [7:0] selr, input [15:0] v, input [8*40-1:0] what);
    begin
        bus_write(17'o177410, {8'd0, selr}, 2'b11);
        expect_rd(17'o177410, v, what);
    end
endtask

// the four-field set, in the sketch's order
task rtc_set(input [15:0] yr, input [7:0] mo, input [7:0] dt, input [7:0] hr, input [7:0] mi, input [7:0] se);
    begin
        bus_write(17'o177410, 16'd4, 2'b11); bus_write(17'o177410, yr, 2'b11);
        bus_write(17'o177410, 16'd5, 2'b11); bus_write(17'o177410, {mo, dt}, 2'b11);
        bus_write(17'o177410, 16'd6, 2'b11); bus_write(17'o177410, {8'd0, hr}, 2'b11);
        bus_write(17'o177410, 16'd7, 2'b11); bus_write(17'o177410, {mi, se}, 2'b11);
        repeat (2) @(posedge clk);
    end
endtask

task osd_set(input [2:0] f, input [7:0] v);
    begin
        @(negedge mclk); set_field = f; set_val = v;
        @(negedge mclk); set_tgl = ~set_tgl;
        repeat (4) @(posedge clk);
    end
endtask

// wait for n seconds of the calendar
task ticks(input integer n);
    integer i;
    begin
        for(i = 0; i < n; i = i + 1) @(posedge dut.tick);
        repeat (2) @(posedge clk);
    end
endtask

integer a, i;
integer cycles;
initial begin
    repeat (4) @(posedge mclk);
    hrst = 1'b0;
    repeat (4) @(posedge clk);
    init = 1'b0;
    repeat (4) @(posedge clk);

    //---- decode: the whole I/O page, word by word ----
    for(a = 17'o177000; a <= 17'o177776; a = a + 2) begin
        bus_read(a);
        if(a == 17'o177400 || a == 17'o177410) begin
            if(!acked) begin $display("FAIL: %06o not acknowledged", a); errors = errors + 1; end
        end else if(acked) begin $display("FAIL: %06o acknowledged, must time out", a); errors = errors + 1; end
    end
    bus_read(17'o177401); if(!acked) begin $display("FAIL: 177401 (odd byte) not acknowledged"); errors = errors + 1; end
    bus_read(17'o177411); if(!acked) begin $display("FAIL: 177411 (odd byte) not acknowledged"); errors = errors + 1; end
    bus_read(17'o177402); if(acked)  begin $display("FAIL: 177402 acknowledged"); errors = errors + 1; end

    //---- mouse ----
    expect_rd(17'o177400, 16'h0000, "mouse idle");
    hid_mouse(8'd0, 8'd5, -8'd3);                       // right 5, up 3 (USB: dy = -3)
    expect_rd(17'o177400, {7'sd3, 1'b0, 7'sd5, 1'b0}, "mouse +5 right, 3 up");
    expect_rd(17'o177400, 16'h0000, "mouse cleared by the read");
    hid_mouse(8'd0, -8'd1, 8'd0);
    expect_rd(17'o177400, 16'h00FE, "mouse -1 in x");
    hid_mouse(8'd0, 8'd0, 8'd1);                        // one down
    expect_rd(17'o177400, 16'hFE00, "mouse 1 down is dy = -1");
    hid_mouse(8'd0, 8'd10, 8'd0);
    hid_mouse(8'd0, 8'd10, 8'd0);
    hid_mouse(8'd0, -8'd4, 8'd0);
    expect_rd(17'o177400, {7'sd0, 1'b0, 7'sd16, 1'b0}, "mouse accumulates 10+10-4");
    for(i = 0; i < 10; i = i + 1) hid_mouse(8'd0, 8'd20, 8'd20);
    expect_rd(17'o177400, {-7'sd63, 1'b0, 7'sd63, 1'b0}, "mouse clips at +-63");
    hid_mouse(8'd0, -8'd128, -8'd128);
    expect_rd(17'o177400, {7'sd63, 1'b0, -7'sd63, 1'b0}, "mouse -128 clips");
    hid_mouse(8'd3, 8'd0, 8'd0);                        // both buttons down
    expect_rd(17'o177400, 16'h0101, "mouse both buttons");
    hid_mouse(8'd1, 8'd0, 8'd0);                        // left only
    expect_rd(17'o177400, 16'h0100, "mouse left button");
    hid_mouse(8'd2, 8'd2, 8'd0);                        // right only, moving
    expect_rd(17'o177400, 16'h0005, "mouse right button and dx 2");
    hid_mouse(8'd0, 8'd0, 8'd0);

    // commands
    bus_write(17'o177400, 16'd7, 2'b11);
    expect_rd(17'o177400, 16'h3336, "command 7: version 3.6");
    expect_rd(17'o177400, 16'h0000, "after the answer, motion again");
    bus_write(17'o177400, 16'd1, 2'b01);                // a MOVB
    expect_rd(17'o177400, 16'h0000, "command 1 without a mouse");
    mouse_present = 1'b1;
    bus_write(17'o177400, 16'd1, 2'b11);
    expect_rd(17'o177400, 16'h00AA, "command 1 with a mouse: standard PS/2 mouse");
    bus_write(17'o177400, 16'd0, 2'b11);
    expect_rd(17'o177400, 16'h0001, "command 0: RTC present");
    bus_write(17'o177400, 16'o012345, 2'b11);
    expect_rd(17'o177400, 16'o012345, "other command: echoed");
    // motion that arrives while a command is pending is kept for the read after
    bus_write(17'o177400, 16'd7, 2'b11);
    hid_mouse(8'd0, 8'd3, 8'd0);
    expect_rd(17'o177400, 16'h3336, "command answer first");
    expect_rd(17'o177400, 16'h0006, "then the motion that came meanwhile");

    //---- RTC ----
    rtc_set(16'd2024, 8'd2, 8'd28, 8'd23, 8'd59, 8'd59);
    rtc_expect(8'd0, {8'd59, 8'd59}, "set: min/sec");
    rtc_expect(8'd1, {8'd4,  8'd23}, "set: Wed 28 Feb 2024 = 4, hours");
    rtc_expect(8'd2, {8'd2,  8'd28}, "set: month/date");
    rtc_expect(8'd3, 16'd2024,       "set: year");
    ticks(2);
    rtc_expect(8'd0, {8'd0,  8'd1},  "leap day: 00:00:01");
    rtc_expect(8'd1, {8'd5,  8'd0},  "leap day: Thu 29 Feb 2024");
    rtc_expect(8'd2, {8'd2,  8'd29}, "leap day: 29 Feb");
    rtc_expect(8'd3, 16'd2024,       "leap day: year");

    rtc_set(16'd2023, 8'd2, 8'd28, 8'd23, 8'd59, 8'd59);
    ticks(1);
    rtc_expect(8'd2, {8'd3,  8'd1},  "2023: 28 Feb rolls to 1 Mar");
    rtc_expect(8'd1, {8'd4,  8'd0},  "2023: Wed 1 Mar");

    rtc_set(16'd2024, 8'd12, 8'd31, 8'd23, 8'd59, 8'd59);
    ticks(1);
    rtc_expect(8'd3, 16'd2025,       "year end: 2025");
    rtc_expect(8'd2, {8'd1,  8'd1},  "year end: 1 Jan");
    rtc_expect(8'd1, {8'd4,  8'd0},  "year end: Wed 1 Jan 2025");

    // a partial set does nothing until the four fields are there
    bus_write(17'o177410, 16'd4, 2'b11); bus_write(17'o177410, 16'd2030, 2'b11);
    rtc_expect(8'd3, 16'd2025,       "partial set: year unchanged");
    bus_write(17'o177410, 16'd5, 2'b11); bus_write(17'o177410, {8'd6, 8'd27}, 2'b11);
    bus_write(17'o177410, 16'd6, 2'b11); bus_write(17'o177410, 16'd15, 2'b11);
    rtc_expect(8'd3, 16'd2025,       "three of four: still unchanged");
    bus_write(17'o177410, 16'd7, 2'b11); bus_write(17'o177410, {8'd10, 8'd0}, 2'b11);
    repeat (2) @(posedge clk);
    rtc_expect(8'd3, 16'd2030,       "fourth field: loaded");
    rtc_expect(8'd2, {8'd6, 8'd27},  "fourth field: 27 Jun");
    rtc_expect(8'd1, {8'd5, 8'd15},  "27 Jun 2030 is a Thursday = 5");
    // an unknown selector is ignored
    bus_write(17'o177410, 16'd9, 2'b11);
    rtc_expect(8'd0, {8'd10, 8'd0},  "selector 9 ignored, 0 still reads");

    // the second: seven of them are exactly 21937500 clocks
    @(posedge dut.tick);
    cycles = 0;
    fork
        begin : count
            forever begin @(posedge clk); cycles = cycles + 1; end
        end
        begin
            repeat (7) @(posedge dut.tick);
            disable count;
        end
    join
    if(cycles !== 21937500) begin $display("FAIL: seven seconds took %0d clocks, expected 21937500", cycles); errors = errors + 1; end
    else $display("      seven seconds = %0d PPU clocks, exact", cycles);

    //---- the OSD's set ----
    osd_set(3'd0, 8'd6);        // 2026
    osd_set(3'd1, 8'd8);        // September
    osd_set(3'd2, 8'd1);        // the 2nd
    osd_set(3'd3, 8'd13);
    osd_set(3'd4, 8'd45);
    rtc_expect(8'd0, {8'd45, 8'd0},  "OSD: 45 min, seconds restarted");
    rtc_expect(8'd1, {8'd4,  8'd13}, "OSD: Wed 2 Sep 2026, 13 h");
    rtc_expect(8'd2, {8'd9,  8'd2},  "OSD: 2 Sep");
    rtc_expect(8'd3, 16'd2026,       "OSD: 2026");

    //---- reset leaves the time, clears the protocol ----
    bus_write(17'o177400, 16'd7, 2'b11);
    bus_write(17'o177410, 16'd4, 2'b11);
    @(negedge clk); init = 1'b1; repeat (3) @(posedge clk); @(negedge clk); init = 1'b0; repeat (2) @(posedge clk);
    expect_rd(17'o177400, 16'h0000, "reset: no command pending");
    bus_write(17'o177410, 16'd1999, 2'b11);             // would have been the year
    rtc_expect(8'd3, 16'd2026,       "reset: no field pending, time kept");
    rtc_expect(8'd2, {8'd9,  8'd2},  "reset: date kept");

    if(errors == 0) $display("PASS: Kakave+ at 177400/177410 - decode, mouse motion/buttons/clip/commands, RTC set/read/rollover/weekday, exact second, OSD set, reset");
    else $display("FAIL: %0d errors", errors);
    $finish;
end
endmodule
