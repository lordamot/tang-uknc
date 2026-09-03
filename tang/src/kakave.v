// kakave.v - the mouse and real-time-clock registers of the "Kakave+"
// cartridge (yrust, oshwlab.com/yrust/uknz_kakave_mouse_rtc_ide) on the
// PPU bus.  The real cartridge is a CPLD decoding two words for an
// ATmega324 that carries a PS/2 mouse and a DS3231; here the mouse is
// the USB one the BL616 already reports over SPI (hid.v) and the clock is
// a calendar counter on the PPU clock, set either by the machine through
// the cartridge's own protocol or from the OSD (sysctrl.v).  There is no
// battery anywhere on this board, so power-on time is whatever the MCU's
// saved settings say (mnano/menu.c, "Clock").
//
// The protocol is the sketch's, kakave_m_ide_rtc_v3_6.ino in
// build/rtc_kkve/, and the three RT-11 programs beside it (KKVTST, KKVRTC,
// KKVDTS) are what it was checked against:
//
//   0177400  mouse.  A read returns [dy7..1 L dx7..1 R]: the motion since
//            the previous read as two signed 7-bit counts in the PS/2
//            convention (y UP is positive), each clipped to +-63, with the
//            left button in bit 8 and the right in bit 0.  Reading clears
//            the counts.  A write leaves a command whose answer the NEXT
//            read returns instead:
//              0  RTC present          -> 0001
//              1  PS/2 device type/id  -> 00AA (a standard mouse) if a USB
//                                         mouse is attached, else 0000
//              7  sketch version       -> "3.6": 3336, high byte '3'
//              other                   -> the written word, echoed
//   0177410  RTC.  A write of 0..3 selects what the next reads return:
//              0  {minutes, seconds}   2  {month, date}
//              1  {weekday, hours}     3  year, e.g. 2026
//            all binary, 24-hour, month 1..12, weekday 1..7 with 1 =
//            SUNDAY - that is what the sketch's microDS3231 getWeekDay()
//            computes, and the bundled RT-11 programs print index 1 as
//            "Monday", so on the real cartridge the printed name is one
//            day off; this module follows the hardware.
//            A write of 4..7 makes the next write the data for one field,
//            in the sketch's order (its comments say otherwise, its code
//            does this):  4 year   5 {month, date}   6 hours   7 {min, sec}
//            and the clock is loaded when all four have been given, as the
//            sketch does (RTC_ST == 1111), seconds restarting from that
//            instant.  Other selector values are ignored.
//
// Both registers acknowledge word and byte accesses at their even and odd
// byte; nothing else in 0177000-0177777 is acknowledged here, and nothing
// else on the PPU bus acknowledges these two (sim/tb/tb_kakave.v and the
// decode walk in .claude/docs/platform.md).
//
// Clocks.  Everything runs on the PPU clock.  The mouse report comes from
// hid.v on mist_clk (clk_25, of which the PPU clock is a division - the
// tool times the paths): mouse_tgl flips once per report, after the
// report's bytes have been written, and is taken through two flops here;
// the bytes are then at least a PPU clock old.  The OSD's clock setting
// crosses the same way (set_tgl).  The seconds come from a phase
// accumulator: the PPU clock is 27 MHz * 13 / 7 / 16, so seven seconds
// are exactly 21937500 of its cycles; adding 7 per cycle and taking a
// second every 21937500 makes the rate exact by construction, and the
// crystal is the only error.
module kakave(
   input             clk,          // the PPU clock (ppuclk_n in top.v, as covox)
   input             init,         // PPU reset: clears the protocol state, NOT the clock
   input      [16:0] adr,
   input      [15:0] dat_i,
   output reg [15:0] dat_o,
   input             wre,
   input      [ 1:0] sel,
   input             stb,
   output reg        ack,
   // one USB mouse report, from hid.v
   input             mouse_tgl,    // flips once per report, after the fields below are stable
   input      [ 7:0] mouse_dx,     // signed, USB convention: right is positive
   input      [ 7:0] mouse_dy,     // signed, USB convention: DOWN is positive
   input      [ 1:0] mouse_btns,   // bit 0 left, bit 1 right - the current state
   input             mouse_present,// sysctrl 'M': a USB mouse is attached
   // the OSD's clock setting, from sysctrl.v
   input             set_tgl,      // flips once per field written
   input      [ 2:0] set_field,    // 0 year-2020  1 month-1  2 date-1  3 hours  4 minutes
   input      [ 7:0] set_val,
   // the OSD's "Hardware" switches (sysctrl 'u' and 't', Sep 2026): each
   // word is on the bus only while its switch is on - off, it is a bus
   // timeout, as on a machine without the cartridge.  The clock counts
   // either way.  Levels on mist_clk; the tool times the crossing.
   input             mouse_en,
   input             rtc_en,
   // the clock as it stands, for the OSD to show (sysctrl CMD 6)
   output     [15:0] rtc_year,
   output     [ 3:0] rtc_month,
   output     [ 4:0] rtc_date,
   output     [ 4:0] rtc_hour,
   output     [ 5:0] rtc_min,
   output     [ 5:0] rtc_sec,
   output     [ 3:0] rtc_dow
);

//------------------------------------------------------------------------
// The calendar
//------------------------------------------------------------------------
// The PPU clock in cycles per 7 s (27e6 * 13 / 7 / 16 * 7 = 27e6 * 13 / 16).
localparam [24:0] TICK_DEN = 25'd21937500;
localparam [24:0] TICK_NUM = 25'd7;

reg [24:0] frac  = 25'd0;
reg [ 5:0] sec   = 6'd0;
reg [ 5:0] min   = 6'd0;
reg [ 4:0] hour  = 5'd0;
reg [ 4:0] date  = 5'd1;
reg [ 3:0] month = 4'd1;
reg [15:0] year  = 16'd2020;    // the MCU's 'y' is year - 2020; menu.c's default lands here

wire        leap = (year[1:0] == 2'd0);       // right for 1901..2099, which is the MCU's range
reg  [ 4:0] dim;
always @(*)
    case(month)
    4'd4, 4'd6, 4'd9, 4'd11: dim = 5'd30;
    4'd2:                    dim = leap ? 5'd29 : 5'd28;
    default:                 dim = 5'd31;
    endcase

// Weekday, 1 = Sunday .. 7 = Saturday, exactly microDS3231's getWeekDay():
//   (d + days_before_month + (m > 2 && y % 4 == 0) + 365*y + (y+3)/4 + 4) % 7 + 1
// 365 = 1 mod 7, so 365*y contributes y mod 7.
function [2:0] mod7;
    input [15:0] v;
    reg   [15:0] t;
    integer i;
    begin
        t = v;
        for(i = 0; i < 8; i = i + 1)        // 8 = 1 mod 7: fold the top down
            t = {13'd0, t[2:0]} + (t >> 3);
        mod7 = (t >= 16'd7) ? t[2:0] - 3'd7 : t[2:0];
    end
endfunction

reg [8:0] days_before;
always @(*)
    case(month)
    4'd1:  days_before = 9'd0;    4'd2:  days_before = 9'd31;   4'd3:  days_before = 9'd59;
    4'd4:  days_before = 9'd90;   4'd5:  days_before = 9'd120;  4'd6:  days_before = 9'd151;
    4'd7:  days_before = 9'd181;  4'd8:  days_before = 9'd212;  4'd9:  days_before = 9'd243;
    4'd10: days_before = 9'd273;  4'd11: days_before = 9'd304;  default: days_before = 9'd334;
    endcase

wire [15:0] dow_sum = {11'd0, date} + {7'd0, days_before} + {15'd0, (month > 4'd2) & leap}
                    + {13'd0, mod7(year)} + {13'd0, mod7((year + 16'd3) >> 2)} + 16'd4;
wire [ 2:0] dow_m   = mod7(dow_sum);
wire [ 3:0] dow     = {1'b0, dow_m} + 4'd1;

// The weekday is ~30 ns of arithmetic behind the year register, and
// sysctrl samples these on clk_25, 20 ns after a PPU edge (test003.sdc):
// taken combinationally it was the one setup violation of the Sep 2026
// layout.  A PPU clock of lag on a value that changes at midnight costs
// nothing; the counters themselves are flops and go out as they are.
reg  [3:0] dow_r = 4'd1;
always @(posedge clk) dow_r <= dow;

assign rtc_year  = year;
assign rtc_month = month;
assign rtc_date  = date;
assign rtc_hour  = hour;
assign rtc_min   = min;
assign rtc_sec   = sec;
assign rtc_dow   = dow_r;

// the second
wire [24:0] frac_n  = frac + TICK_NUM;
wire        tick    = (frac_n >= TICK_DEN);

//------------------------------------------------------------------------
// Bus
//------------------------------------------------------------------------
wire ce_mouse = ({adr[15:1], 1'b0} == 16'o177400) && stb && mouse_en;
wire ce_rtc   = ({adr[15:1], 1'b0} == 16'o177410) && stb && rtc_en;
wire ce       = ce_mouse | ce_rtc;
reg  ce_old   = 1'b0;
wire cyc_go   = ce & ~ce_old;     // the first clock of an access, as xm2-01.v takes it

// a byte write puts its byte where the bus has it; the other half reads 0
wire [15:0] wdata = {sel[1] ? dat_i[15:8] : 8'd0, sel[0] ? dat_i[7:0] : 8'd0};

//------------------------------------------------------------------------
// Mouse
//------------------------------------------------------------------------
reg  [2:0] mtgl_s = 3'd0;
wire       report = mtgl_s[2] ^ mtgl_s[1];

reg  signed [6:0] acc_x = 7'sd0;
reg  signed [6:0] acc_y = 7'sd0;

// saturating +-63 add of a 9-bit signed delta to a 7-bit signed count
function signed [6:0] sat_add;
    input signed [6:0] a;
    input signed [8:0] d;
    reg   signed [9:0] s;
    begin
        s = {{3{a[6]}}, a} + {d[8], d};
        sat_add = (s > 10'sd63) ? 7'sd63 : (s < -10'sd63) ? -7'sd63 : s[6:0];
    end
endfunction

// nine bits, because -(-128) does not exist in eight
wire signed [8:0] dx =  $signed({mouse_dx[7], mouse_dx});
wire signed [8:0] dy = -$signed({mouse_dy[7], mouse_dy});    // PS/2 counts up, USB counts down

reg        cmd_pending = 1'b0;
reg [15:0] cmd_word    = 16'd0;
reg [15:0] mouse_answer;
always @(*)
    case(cmd_word[7:0])
    8'd0:    mouse_answer = 16'h0001;
    8'd1:    mouse_answer = mouse_present ? 16'h00AA : 16'h0000;
    8'd7:    mouse_answer = 16'h3336;                // '3' . '6'
    default: mouse_answer = cmd_word;
    endcase

//------------------------------------------------------------------------
// RTC protocol
//------------------------------------------------------------------------
reg  [2:0] stgl_s = 3'd0;
wire       set_go = stgl_s[2] ^ stgl_s[1];

reg [15:0] rtc_word = 16'd0;    // what a read of 0177410 returns
reg [ 2:0] rtc_set  = 3'd0;     // 0 none, else the field the next write is data for (1..4)
reg [ 3:0] rtc_have = 4'd0;     // fields collected: year, date/month, hours, min/sec
reg [15:0] s_year   = 16'd0;
reg [15:0] s_dm     = 16'd0;
reg [ 7:0] s_hour   = 8'd0;
reg [15:0] s_ms     = 16'd0;
wire       rtc_load = &rtc_have;

//------------------------------------------------------------------------
always @(posedge clk) begin
    mtgl_s <= {mtgl_s[1:0], mouse_tgl};
    stgl_s <= {stgl_s[1:0], set_tgl};
    ce_old <= ce;

    //---- the clock, which no reset touches ----
    if(rtc_load) begin
        frac  <= 25'd0;
        sec   <= (s_ms[ 7:0] > 8'd59) ? 6'd59 : s_ms[5:0];
        min   <= (s_ms[15:8] > 8'd59) ? 6'd59 : s_ms[13:8];
        hour  <= (s_hour     > 8'd23) ? 5'd23 : s_hour[4:0];
        date  <= (s_dm[ 7:0] == 8'd0) ? 5'd1 : (s_dm[7:0] > 8'd31) ? 5'd31 : s_dm[4:0];
        month <= (s_dm[15:8] == 8'd0) ? 4'd1 : (s_dm[15:8] > 8'd12) ? 4'd12 : s_dm[11:8];
        year  <= s_year;
    end else if(set_go) begin
        case(set_field)
        3'd0: year  <= 16'd2020 + {8'd0, set_val};
        3'd1: month <= (set_val > 8'd11) ? 4'd12 : set_val[3:0] + 4'd1;
        3'd2: date  <= (set_val > 8'd30) ? 5'd31 : set_val[4:0] + 5'd1;
        3'd3: hour  <= (set_val > 8'd23) ? 5'd23 : set_val[4:0];
        3'd4: begin min <= (set_val > 8'd59) ? 6'd59 : set_val[5:0]; sec <= 6'd0; frac <= 25'd0; end
        default: ;
        endcase
    end else begin
        frac <= tick ? frac_n - TICK_DEN : frac_n;
        if(tick) begin
            if(sec != 6'd59) sec <= sec + 6'd1;
            else begin
                sec <= 6'd0;
                if(min != 6'd59) min <= min + 6'd1;
                else begin
                    min <= 6'd0;
                    if(hour != 5'd23) hour <= hour + 5'd1;
                    else begin
                        hour <= 5'd0;
                        if(date < dim) date <= date + 5'd1;
                        else begin
                            date <= 5'd1;
                            if(month != 4'd12) month <= month + 4'd1;
                            else begin
                                month <= 4'd1;
                                year  <= year + 16'd1;
                            end
                        end
                    end
                end
            end
        end
    end

    //---- the registers ----
    if(init) begin
        ack         <= 1'b0;
        dat_o       <= 16'd0;
        acc_x       <= 7'sd0;
        acc_y       <= 7'sd0;
        cmd_pending <= 1'b0;
        rtc_word    <= 16'd0;
        rtc_set     <= 3'd0;
        rtc_have    <= 4'd0;
    end else begin
        // motion accumulates between reads; a read takes it and clears it,
        // and a report landing on the read's own clock is kept, not lost
        if(cyc_go && ce_mouse && !wre && !cmd_pending) begin
            acc_x <= report ? sat_add(7'sd0, dx) : 7'sd0;
            acc_y <= report ? sat_add(7'sd0, dy) : 7'sd0;
        end else if(report) begin
            acc_x <= sat_add(acc_x, dx);
            acc_y <= sat_add(acc_y, dy);
        end

        if(rtc_load) rtc_have <= 4'd0;

        if(!stb) begin
            ack   <= 1'b0;
            dat_o <= 16'd0;
        end else if(cyc_go) begin
            ack <= 1'b1;
            if(ce_mouse) begin
                if(wre) begin
                    cmd_pending <= 1'b1;
                    cmd_word    <= wdata;
                end else if(cmd_pending) begin
                    cmd_pending <= 1'b0;
                    dat_o       <= mouse_answer;
                end else
                    dat_o <= {acc_y, mouse_btns[0], acc_x, mouse_btns[1]};
            end else begin // ce_rtc
                if(wre) begin
                    if(rtc_set != 3'd0) begin
                        case(rtc_set)
                        3'd1: begin s_year <= wdata;      rtc_have[0] <= 1'b1; end
                        3'd2: begin s_dm   <= wdata;      rtc_have[1] <= 1'b1; end
                        3'd3: begin s_hour <= wdata[7:0]; rtc_have[2] <= 1'b1; end
                        default: begin s_ms <= wdata;     rtc_have[3] <= 1'b1; end
                        endcase
                        rtc_set  <= 3'd0;
                        rtc_word <= wdata;              // the sketch's RTC_x/y hold the data
                    end else
                        case(wdata[7:0])
                        8'd0: rtc_word <= {2'd0, min, 2'd0, sec};
                        8'd1: rtc_word <= {4'd0, dow, 3'd0, hour};
                        8'd2: rtc_word <= {4'd0, month, 3'd0, date};
                        8'd3: rtc_word <= year;
                        8'd4: rtc_set  <= 3'd1;
                        8'd5: rtc_set  <= 3'd2;
                        8'd6: rtc_set  <= 3'd3;
                        8'd7: rtc_set  <= 3'd4;
                        default: ;
                        endcase
                end else
                    dat_o <= rtc_word;
            end
        end
    end
end
endmodule
