/*
    sysctrl.v
 
    generic system control interface fro/via the MCU

    TODO: This is currently very core specific. This needs to be
    generic for all cores.
*/

module sysctrl (
  input             clk,
  input             reset,

  input             data_in_strobe,
  input             data_in_start,
  input [7:0]       data_in,
  output reg [7:0]  data_out,

  // interrupt interface
  output            int_out_n,
  input [7:0]       int_in,
  output reg [7:0]  int_ack,

  input [1:0]       buttons, // S0 and S1 buttons on Tang Nano 20k

  output reg [1:0]  leds, // two leds can be controlled from the MCU
  output reg [23:0] color, // a 24bit color to e.g. be used to drive the ws2812

  // values that can be configured by the user
  output reg        system_video,
  output reg [1:0]  system_reset,
  output reg [1:0]  system_volume,
  // the mounted IDE image's geometry, from its first sector (mnano/sdc.c):
  // 'S' sectors per track, 'H' heads, 'I' bit 0 = image stored inverted
  output reg [7:0]  system_hdd_spt,
  output reg [7:0]  system_hdd_heads,
  output reg [7:0]  system_hdd_flags,
  // 'J' from the OSD: 0 take the detected form, 1 read the image as plain,
  // 2 read it as inverted - the override for when the detection is wrong
  output reg [1:0]  system_hdd_mode,
  // 'C' low byte, 'Y' high byte: cylinders, for IDENTIFY
  output reg [15:0] system_hdd_cyl,
  // 'K' from the OSD: 1 = the IDE image is write-protected
  output reg        system_hdd_wprot,
  // 'D' from the OSD: stretch of every IDE data-register read, ~25 us a
  // sector per step - it sets the sample rate of a program that streams
  // its sound out of the sector data (ide.v, Sep 2026)
  output reg [5:0]  system_hdd_delay,
  // 'p' 'q' 'r' 's' from the OSD "FDD controller" form: one letter a
  // drive, 1 = write-protected (vp1-128fdd.v).  Until Sep 2026 this was
  // one letter, 'P', carrying the INDEX of a six-entry list as if it were
  // a bitmask - "2:" protected drives 0 and 1, "All" protected 0 and 2.
  output reg [3:0]  system_floppy_wprot,
  // The hardware the OSD can take out of the machine or leave in
  // (Sep 2026, the "Hardware" form).  A device that is off does not
  // acknowledge its addresses - a bus timeout, as on a machine without
  // it - and plays nothing; the beeper is a standard part and only leaves
  // the mixer.
  output reg        system_beeper,    // 'b' 0 mute, 1 on
  output reg [2:0]  system_ay_en,     // '1' '2' '3' the three AY-3-8912s of the Aberrant
  output reg [1:0]  system_covox,     // 'c' 0 off, 1 at 0177372, 2 at 0177100 (printer port A), 3 both
  output reg        system_fdd_en,    // 'f' the floppy controller's 0177130/2
  output reg        system_hdd_en,    // 'e' the IDE cartridge (with an image mounted)
  output reg        system_mouse_en,  // 'u' the Kakave+ mouse word 0177400
  output reg        system_rtc_en,    // 't' the Kakave+ clock word 0177410
  // 'M' from usb_host.c: 1 = a USB mouse is attached (the Kakave+ mouse
  // register's "who are you" answer, kakave.v)
  output reg        system_mouse,
  // the OSD's "Clock" form (menu.c), one letter a field, for kakave.v's
  // calendar: 'y' year-2020, 'm' month-1, 'd' date-1, 'h' hours,
  // 'n' minutes (which also zeroes the seconds).  Each letter is
  // announced by a flip of system_rtc_tgl with the field number and the
  // value beside it; kakave.v takes the flip through two flops.
  output reg        system_rtc_tgl,
  output reg [2:0]  system_rtc_field,
  output reg [7:0]  system_rtc_val,
  // the clock's current reading, from kakave.v, for CMD 6 (the OSD's
  // "RTC clock" form shows it).  Counted on the PPU clock; sampled here
  // on mist_clk - both declared, so the tool times the crossing - and
  // latched once per command so the bytes shifted out belong to one
  // instant, not to a second that ticked between two of them.
  input [15:0]      rtc_year,
  input [3:0]       rtc_month,
  input [4:0]       rtc_date,
  input [4:0]       rtc_hour,
  input [5:0]       rtc_min,
  input [5:0]       rtc_sec,
  input [3:0]       rtc_dow,

  // CMD 9: reload the FPGA from the next image in the SPI flash (tang-ultima)
  output reg        reconfig,

  // CMD 10: the configuration flash (tang-ultima).  The payload is passed
  // through to flashwr.v byte for byte - the sub-commands are its, not
  // this module's - and its answers come back the same way.
  output            flash_stb,
  output            flash_first,
  output      [7:0] flash_din,
  input       [7:0] flash_dout,
  // CMD 11: the UART to the board's own BL616 (tang-ultima, coreload.v),
  // passed through the same way; a core switch into the FPGA's SRAM
  output            cl_stb,
  output            cl_first,
  output      [7:0] cl_din,
  input       [7:0] cl_dout
);

assign flash_stb   = data_in_strobe && !data_in_start && (command == 8'd10);
assign flash_first = (state == 4'd1);
assign flash_din   = data_in;
assign cl_stb      = data_in_strobe && !data_in_start && (command == 8'd11);
assign cl_first    = (state == 4'd1);
assign cl_din      = data_in;

reg [3:0] state;
reg [7:0] command;
reg [7:0] id;
   
// reverse data byte for rgb   
wire [7:0] data_in_rev = { data_in[0], data_in[1], data_in[2], data_in[3], 
                           data_in[4], data_in[5], data_in[6], data_in[7] };

reg coldboot = 1'b1;

// CMD 6's snapshot of the clock
reg [15:0] snap_year;
reg [ 3:0] snap_month;
reg [ 4:0] snap_date;
reg [ 4:0] snap_hour;
reg [ 5:0] snap_min;
reg [ 5:0] snap_sec;
reg [ 3:0] snap_dow;
   
assign int_out_n = (int_in != 8'h00 || coldboot)?1'b0:1'b1;

// process mouse events
always @(posedge clk) begin
   if(reset) begin
      state <= 4'd0;      
      leds <= 2'b00;        // after reset leds are off
      color <= 24'h000000;  // color black -> rgb led off

      int_ack <= 8'h00;
      coldboot = 1'b1;      // reset is actually the power-on-reset
      reconfig <= 1'b0;

      // OSD value defaults. These should be sane defaults, but the MCU
      // will very likely override these early
      system_video <= 1'b0;         // RGB
      system_volume <= 2'b00;       // mute
      system_floppy_wprot <= 4'b00; // floppy not write protected
      // the hardware defaults are the OSD's (menu.c, variables_uknc):
      // everything standard in, the add-ons out, until the MCU says
      system_beeper   <= 1'b1;
      system_ay_en    <= 3'b111;
      system_covox    <= 2'd0;
      system_fdd_en   <= 1'b1;
      system_hdd_en   <= 1'b0;
      system_mouse_en <= 1'b0;
      system_rtc_en   <= 1'b0;
      system_hdd_spt <= 8'd0;
      system_hdd_heads <= 8'd0;
      system_hdd_flags <= 8'd0;
      system_hdd_mode <= 2'd0;
      system_hdd_cyl <= 16'd0;
      system_hdd_wprot <= 1'b0;
      system_hdd_delay <= 6'd30;    // 750 us a sector, the MCU's default too - found on the board
      system_mouse <= 1'b0;
      system_rtc_tgl <= 1'b0;
      system_rtc_field <= 3'd0;
      system_rtc_val <= 8'd0;
   end else begin
      int_ack <= 8'h00;
      reconfig <= 1'b0;

      // CMD 10's answers are flashwr.v's, tracked a cycle behind it -
      // which is a dozen cycles before the MCU clocks the next byte out
      if(command == 8'd10) data_out <= flash_dout;
      if(command == 8'd11) data_out <= cl_dout;

      // iack bit 0 acknowledges the coldboot notification
      if(int_ack[0]) coldboot <= 1'b0;      
      
      if(data_in_strobe) begin      
        if(data_in_start) begin
            state <= 4'd1;
            command <= data_in;
            // one instant of the clock for whatever command this is
            snap_year  <= rtc_year;
            snap_month <= rtc_month;
            snap_date  <= rtc_date;
            snap_hour  <= rtc_hour;
            snap_min   <= rtc_min;
            snap_sec   <= rtc_sec;
            snap_dow   <= rtc_dow;
        end else if(state != 4'd0) begin
            if(state != 4'd15) state <= state + 4'd1;

            // CMD 0: status data
            if(command == 8'd0) begin
                // return some pattern that would not appear randomly
                // on e.g. an unprogrammed device
                if(state == 4'd1) data_out <= 8'h5c;
                if(state == 4'd2) data_out <= 8'h42;
                if(state == 4'd3) data_out <= 8'h05;   // core id 1 = Atari ST
            end

            // CMD 1: there are two MCU controlled LEDs
            if(command == 8'd1) begin
                if(state == 4'd1) leds <= data_in[1:0];
            end

            // CMD 2: a 24 color value to be mapped e.g. onto the ws2812
            if(command == 8'd2) begin
                if(state == 4'd1) color[15: 8] <= data_in_rev;
                if(state == 4'd2) color[ 7: 0] <= data_in_rev;
                if(state == 4'd3) color[23:16] <= data_in_rev;
            end

            // CMD 3: return button state
            if(command == 8'd3) begin
                data_out <= { 6'b000000, buttons };;
            end

            // CMD 4: config values (e.g. set by user via OSD)
            if(command == 8'd4) begin
                // second byte can be any character which identifies the variable to set 
                if(state == 4'd1) id <= data_in;

                if(state == 4'd2) begin
                    if(id == "V") system_video <= data_in[0];
                    // Value "R": coldboot(3), reset(1) or run(0)
                    if(id == "R") system_reset <= data_in[1:0];
                    // Value "A": volume mute(0), 33%(1), 66%(2) or 100%(3)
                    if(id == "A") system_volume <= data_in[1:0];
                    // floppy write protection, one letter a drive
                    if(id == "p") system_floppy_wprot[0] <= data_in[0];
                    if(id == "q") system_floppy_wprot[1] <= data_in[0];
                    if(id == "r") system_floppy_wprot[2] <= data_in[0];
                    if(id == "s") system_floppy_wprot[3] <= data_in[0];
                    // the hardware in or out of the machine
                    if(id == "b") system_beeper      <= data_in[0];
                    if(id == "1") system_ay_en[0]    <= data_in[0];
                    if(id == "2") system_ay_en[1]    <= data_in[0];
                    if(id == "3") system_ay_en[2]    <= data_in[0];
                    if(id == "c") system_covox       <= data_in[1:0];
                    if(id == "f") system_fdd_en      <= data_in[0];
                    if(id == "e") system_hdd_en      <= data_in[0];
                    if(id == "u") system_mouse_en    <= data_in[0];
                    if(id == "t") system_rtc_en      <= data_in[0];
                    // IDE image geometry, sent before the INSERTED notice
                    if(id == "S") system_hdd_spt   <= data_in;
                    if(id == "H") system_hdd_heads <= data_in;
                    if(id == "I") system_hdd_flags <= data_in;
                    if(id == "J") system_hdd_mode  <= data_in[1:0];
                    if(id == "C") system_hdd_cyl[7:0]  <= data_in;
                    if(id == "Y") system_hdd_cyl[15:8] <= data_in;
                    if(id == "K") system_hdd_wprot <= data_in[0];
                    if(id == "D") system_hdd_delay <= data_in[5:0];
                    if(id == "M") system_mouse <= data_in[0];
                    // the clock: field number and value, then the flip
                    if(id == "y" || id == "m" || id == "d" || id == "h" || id == "n") begin
                        system_rtc_field <= (id == "y") ? 3'd0 : (id == "m") ? 3'd1 :
                                            (id == "d") ? 3'd2 : (id == "h") ? 3'd3 : 3'd4;
                        system_rtc_val   <= data_in;
                        system_rtc_tgl   <= ~system_rtc_tgl;
                    end
                end
            end

            // CMD 5: interrupt control
            if(command == 8'd5) begin
                // second byte acknowleges the interrupts
                if(state == 4'd1) int_ack <= data_in;

                // interrupt[0] notifies the MCU of a FPGA cold boot e.g. if
                // the FPGA has been loaded via USB
                data_out <= { int_in[7:1], coldboot };
            end

            // CMD 6: read the Kakave+ clock (Sep 2026).  Eight bytes after
            // the command's dummy byte, as sys_get_rtc() in mnano/sysctrl.c
            // reads them: year low, year high, month 1..12, date 1..31,
            // hour, minute, second, weekday 1 = Sunday .. 7 - the snapshot
            // taken at the command byte.
            if(command == 8'd6) begin
                if(state == 4'd1) data_out <= snap_year[7:0];
                if(state == 4'd2) data_out <= snap_year[15:8];
                if(state == 4'd3) data_out <= {4'd0, snap_month};
                if(state == 4'd4) data_out <= {3'd0, snap_date};
                if(state == 4'd5) data_out <= {3'd0, snap_hour};
                if(state == 4'd6) data_out <= {2'd0, snap_min};
                if(state == 4'd7) data_out <= {2'd0, snap_sec};
                if(state == 4'd8) data_out <= {4'd0, snap_dow};
            end

            // CMD 9: reconfigure (tang-ultima's core switch).  The byte
            // after the command must be A5h, so that a stray byte on the
            // link cannot reload the FPGA; the pulse reaches top.v, which
            // drives RECONFIG_N (pin 9, a GPIO here) low, and the FPGA
            // loads the image whose flash address this bitstream's header
            // names (Gowin MultiBoot, UG290 7.5.4) - itself, for a
            // standalone build.  Nothing here survives it.
            if(command == 8'd9) begin
                if(state == 4'd1 && data_in == 8'hA5) reconfig <= 1'b1;
            end
         end
      end
   end
end
    
endmodule
