module keybrd(
   clk50,
   rst,

   press_btn,
   keycode,
   read,

   PS2_CLK,
   PS2_DAT,
   
   led_act,

   osd_en
);
input  clk50;
input  rst;

output press_btn;
output [7:0]keycode;
input  read;

inout	 PS2_CLK;
inout  PS2_DAT;

output led_act;

output reg osd_en;
//--------------------------------------------------------
//
//--------------------------------------------------------
wire [7:0]received_data;
wire received_data_en;

assign led_act = ~press_btn;

reg [ 7:0]the_command = 0;
reg send_command = 0;
wire command_was_sent;
wire error_communication_timed_out;

altera_up_ps2 ps2(
	// Inputs
	.clk(clk50),
	.reset(rst),

	.the_command(the_command),
	.send_command(send_command),

	// Bidirectionals
	.PS2_CLK(PS2_CLK),					// PS2 Clock
 	.PS2_DAT(PS2_DAT),					// PS2 Data

	// Outputs
	.command_was_sent(command_was_sent),
	.error_communication_timed_out(error_communication_timed_out),

	.received_data(received_data),
	.received_data_en(received_data_en)	// If 1 - new data has been received
);

reg add_key = 1'b0;
reg key_up  = 1'b0;
reg [7:0]keycode;

always @(negedge received_data_en)
		if(add_key)
		case(received_data)
          8'hF0:    key_up  <= 1'b1;
/* up  */ 8'h75:    begin keycode <=  key_up ? (8'o154 & 8'o17)|8'o200 : 8'o154 & 8'o177; add_key <= 1'b0; key_up <= 1'b0; end // row up
/* down*/ 8'h72:    begin keycode <=  key_up ? (8'o134 & 8'o17)|8'o200 : 8'o134 & 8'o177; add_key <= 1'b0; key_up <= 1'b0; end // row down
/* left*/ 8'h6B:    begin keycode <=  key_up ? (8'o116 & 8'o17)|8'o200 : 8'o116 & 8'o177; add_key <= 1'b0; key_up <= 1'b0; end // row left
/* rght*/ 8'h74:    begin keycode <=  key_up ? (8'o133 & 8'o17)|8'o200 : 8'o133 & 8'o177; add_key <= 1'b0; key_up <= 1'b0; end // row right
/* GRAF*/ 8'h1F:    begin keycode <=  key_up ? (8'o66  & 8'o17)|8'o200 : 8'o66  & 8'o177; add_key <= 1'b0; key_up <= 1'b0; end // Win
          default:  begin add_key <= 1'b0; key_up <= 1'b0; keycode <= 0; end
		endcase
		
		else case (received_data)
              8'hE0: add_key <= 1'b1;
              8'hF0: key_up  <= 1'b1;
    /*enter*/ 8'h5A: begin keycode <=  key_up ? (8'o153 & 8'o17)|8'o200 : 8'o153 & 8'o177; key_up <= 1'b0; end // enter
    /* A   */ 8'h1C: begin keycode <=  key_up ? (8'o72  & 8'o17)|8'o200 : 8'o72  & 8'o177; key_up <= 1'b0; end
    /* B   */ 8'h32: begin keycode <=  key_up ? (8'o76  & 8'o17)|8'o200 : 8'o76  & 8'o177; key_up <= 1'b0; end
    /* C   */ 8'h21: begin keycode <=  key_up ? (8'o50  & 8'o17)|8'o200 : 8'o50  & 8'o177; key_up <= 1'b0; end
    /* D   */ 8'h23: begin keycode <=  key_up ? (8'o57  & 8'o17)|8'o200 : 8'o57  & 8'o177; key_up <= 1'b0; end
    /* E   */ 8'h24: begin keycode <=  key_up ? (8'o33  & 8'o17)|8'o200 : 8'o33  & 8'o177; key_up <= 1'b0; end
    /* F   */ 8'h2B: begin keycode <=  key_up ? (8'o47  & 8'o17)|8'o200 : 8'o47  & 8'o177; key_up <= 1'b0; end
    /* G   */ 8'h34: begin keycode <=  key_up ? (8'o55  & 8'o17)|8'o200 : 8'o55  & 8'o177; key_up <= 1'b0; end
    /* H   */ 8'h33: begin keycode <=  key_up ? (8'o156 & 8'o17)|8'o200 : 8'o156 & 8'o177; key_up <= 1'b0; end
    /* I   */ 8'h43: begin keycode <=  key_up ? (8'o73  & 8'o17)|8'o200 : 8'o73  & 8'o177; key_up <= 1'b0; end
    /* J   */ 8'h3B: begin keycode <=  key_up ? (8'o27  & 8'o17)|8'o200 : 8'o27  & 8'o177; key_up <= 1'b0; end
    /* K   */ 8'h42: begin keycode <=  key_up ? (8'o52  & 8'o17)|8'o200 : 8'o52  & 8'o177; key_up <= 1'b0; end
    /* L   */ 8'h4B: begin keycode <=  key_up ? (8'o56  & 8'o17)|8'o200 : 8'o56  & 8'o177; key_up <= 1'b0; end
    /* M   */ 8'h3A: begin keycode <=  key_up ? (8'o112 & 8'o17)|8'o200 : 8'o112 & 8'o177; key_up <= 1'b0; end
    /* N   */ 8'h31: begin keycode <=  key_up ? (8'o54  & 8'o17)|8'o200 : 8'o54  & 8'o177; key_up <= 1'b0; end
    /* O   */ 8'h44: begin keycode <=  key_up ? (8'o75  & 8'o17)|8'o200 : 8'o75  & 8'o177; key_up <= 1'b0; end
    /* P   */ 8'h4D: begin keycode <=  key_up ? (8'o53  & 8'o17)|8'o200 : 8'o53  & 8'o177; key_up <= 1'b0; end
    /* Q   */ 8'h15: begin keycode <=  key_up ? (8'o67  & 8'o17)|8'o200 : 8'o67  & 8'o177; key_up <= 1'b0; end
    /* R   */ 8'h2D: begin keycode <=  key_up ? (8'o74  & 8'o17)|8'o200 : 8'o74  & 8'o177; key_up <= 1'b0; end
    /* S   */ 8'h1B: begin keycode <=  key_up ? (8'o111 & 8'o17)|8'o200 : 8'o111 & 8'o177; key_up <= 1'b0; end
    /* T   */ 8'h2C: begin keycode <=  key_up ? (8'o114 & 8'o17)|8'o200 : 8'o114 & 8'o177; key_up <= 1'b0; end
    /* U   */ 8'h3C: begin keycode <=  key_up ? (8'o51  & 8'o17)|8'o200 : 8'o51  & 8'o177; key_up <= 1'b0; end
    /* V   */ 8'h2A: begin keycode <=  key_up ? (8'o137 & 8'o17)|8'o200 : 8'o137 & 8'o177; key_up <= 1'b0; end
    /* W   */ 8'h1D: begin keycode <=  key_up ? (8'o71  & 8'o17)|8'o200 : 8'o71  & 8'o177; key_up <= 1'b0; end
    /* X   */ 8'h22: begin keycode <=  key_up ? (8'o115 & 8'o17)|8'o200 : 8'o115 & 8'o177; key_up <= 1'b0; end
    /* Y   */ 8'h35: begin keycode <=  key_up ? (8'o70  & 8'o17)|8'o200 : 8'o70  & 8'o177; key_up <= 1'b0; end
    /* Z   */ 8'h1A: begin keycode <=  key_up ? (8'o157 & 8'o17)|8'o200 : 8'o157 & 8'o177; key_up <= 1'b0; end
    /* 0   */ 8'h45: begin keycode <=  key_up ? (8'o176 & 8'o17)|8'o200 : 8'o176 & 8'o177; key_up <= 1'b0; end
    /* 1   */ 8'h16: begin keycode <=  key_up ? (8'o30  & 8'o17)|8'o200 : 8'o30  & 8'o177; key_up <= 1'b0; end
    /* 2   */ 8'h1E: begin keycode <=  key_up ? (8'o31  & 8'o17)|8'o200 : 8'o31  & 8'o177; key_up <= 1'b0; end
    /* 3   */ 8'h26: begin keycode <=  key_up ? (8'o32  & 8'o17)|8'o200 : 8'o32  & 8'o177; key_up <= 1'b0; end
    /* 4   */ 8'h25: begin keycode <=  key_up ? (8'o13  & 8'o17)|8'o200 : 8'o13  & 8'o177; key_up <= 1'b0; end
    /* 5   */ 8'h2E: begin keycode <=  key_up ? (8'o34  & 8'o17)|8'o200 : 8'o34  & 8'o177; key_up <= 1'b0; end
    /* 6   */ 8'h36: begin keycode <=  key_up ? (8'o35  & 8'o17)|8'o200 : 8'o35  & 8'o177; key_up <= 1'b0; end
    /* 7   */ 8'h3D: begin keycode <=  key_up ? (8'o16  & 8'o17)|8'o200 : 8'o16  & 8'o177; key_up <= 1'b0; end
    /* 8   */ 8'h3E: begin keycode <=  key_up ? (8'o17  & 8'o17)|8'o200 : 8'o17  & 8'o177; key_up <= 1'b0; end
    /* 9   */ 8'h46: begin keycode <=  key_up ? (8'o177 & 8'o17)|8'o200 : 8'o177 & 8'o177; key_up <= 1'b0; end
    /* ~   */ 8'h0E: begin keycode <=  key_up ? (8'o77  & 8'o17)|8'o200 : 8'o77  & 8'o177; key_up <= 1'b0; end // @
    /* -   */ 8'h4E: begin keycode <=  key_up ? (8'o25  & 8'o17)|8'o200 : 8'o25  & 8'o177; key_up <= 1'b0; end // dop
    /* =   */ 8'h55: begin keycode <=  key_up ? (8'o175 & 8'o17)|8'o200 : 8'o175 & 8'o177; key_up <= 1'b0; end
    /* \   */ 8'h5D: begin keycode <=  key_up ? (8'o136 & 8'o17)|8'o200 : 8'o136 & 8'o177; key_up <= 1'b0; end
    /* [   */ 8'h54: begin keycode <=  key_up ? (8'o36  & 8'o17)|8'o200 : 8'o36  & 8'o177; key_up <= 1'b0; end
    /* ]   */ 8'h5B: begin keycode <=  key_up ? (8'o37  & 8'o17)|8'o200 : 8'o37  & 8'o177; key_up <= 1'b0; end
    /* ;   */ 8'h4C: begin keycode <=  key_up ? (8'o7   & 8'o17)|8'o200 : 8'o7   & 8'o177; key_up <= 1'b0; end
    /* '   */ 8'h52: begin keycode <=  key_up ? (8'o5   & 8'o17)|8'o200 : 8'o5   & 8'o177; key_up <= 1'b0; end
    /* ,   */ 8'h41: begin keycode <=  key_up ? (8'o117 & 8'o17)|8'o200 : 8'o117 & 8'o177; key_up <= 1'b0; end
    /* .   */ 8'h49: begin keycode <=  key_up ? (8'o135 & 8'o17)|8'o200 : 8'o135 & 8'o177; key_up <= 1'b0; end
    /* /   */ 8'h4A: begin keycode <=  key_up ? (8'o173 & 8'o17)|8'o200 : 8'o173 & 8'o177; key_up <= 1'b0; end
    /* BSP */ 8'h66: begin keycode <=  key_up ? (8'o132 & 8'o17)|8'o200 : 8'o132 & 8'o177; key_up <= 1'b0; end // bksp
    /* ESC */ 8'h76: begin keycode <=  key_up ? (8'o6   & 8'o17)|8'o200 : 8'o6   & 8'o177; key_up <= 1'b0; end // AP2
    /* TAB */ 8'h0D: begin keycode <=  key_up ? (8'o26  & 8'o17)|8'o200 : 8'o26  & 8'o177; key_up <= 1'b0; end // Tab
    /* Ctrl*/ 8'h14: begin keycode <=  key_up ? (8'o46  & 8'o17)|8'o200 : 8'o46  & 8'o177; key_up <= 1'b0; end // UPR
    /* spas*/ 8'h29: begin keycode <=  key_up ? (8'o113 & 8'o17)|8'o200 : 8'o113 & 8'o177; key_up <= 1'b0; end // Space
    /* F12 */ 8'h07: begin keycode <=  key_up ? (8'o4   & 8'o17)|8'o200 : 8'o4   & 8'o177; key_up <= 1'b0; end // STOP
    /* F11 */ 8'h78: begin keycode <=  key_up ? (8'o171 & 8'o17)|8'o200 : 8'o171 & 8'o177; key_up <= 1'b0; end // RST
    /* F10 */ 8'h09: begin keycode <=  key_up ? (8'o151 & 8'o17)|8'o200 : 8'o151 & 8'o177; key_up <= 1'b0; end // ISP
    /* F9  */ 8'h01: begin keycode <=  key_up ? (8'o152 & 8'o17)|8'o200 : 8'o152 & 8'o177; key_up <= 1'b0; end // UST
    /* F8  */ 8'h0A: begin keycode <=  key_up ? (8'o172 & 8'o17)|8'o200 : 8'o172 & 8'o177; key_up <= 1'b0; end // POM
    /* shft*/ 8'h12: begin keycode <=  key_up ? (8'o105 & 8'o17)|8'o200 : 8'o105 & 8'o177; key_up <= 1'b0; end // Shift
    /* shft*/ 8'h59: begin keycode <=  key_up ? (8'o105 & 8'o17)|8'o200 : 8'o105 & 8'o177; key_up <= 1'b0; end // Shift
    /* Caps*/ 8'h58: begin keycode <=  key_up ? (8'o107 & 8'o17)|8'o200 : 8'o107 & 8'o177; key_up <= 1'b0; end // Fix
    /* Alt */ 8'h11: begin keycode <=  key_up ? (8'o106 & 8'o17)|8'o200 : 8'o106 & 8'o177; key_up <= 1'b0; end // Alf
    /* F1  */ 8'h05: begin keycode <=  key_up ? (8'o10  & 8'o17)|8'o200 : 8'o10  & 8'o177; key_up <= 1'b0; end // K1
    /* F2  */ 8'h06: begin keycode <=  key_up ? (8'o11  & 8'o17)|8'o200 : 8'o11  & 8'o177; key_up <= 1'b0; end // K2
    /* F3  */ 8'h04: begin keycode <=  key_up ? (8'o11  & 8'o17)|8'o200 : 8'o11  & 8'o177; key_up <= 1'b0; end // K3
    /* F4  */ 8'h0C: begin keycode <=  key_up ? (8'o11  & 8'o17)|8'o200 : 8'o11  & 8'o177; key_up <= 1'b0; end // K4
    /* F5  */ 8'h03: begin keycode <=  key_up ? (8'o11  & 8'o17)|8'o200 : 8'o11  & 8'o177; key_up <= 1'b0; end // K5
    /* *   */ 8'h7C: begin keycode <=  key_up ? (8'o174 & 8'o17)|8'o200 : 8'o174 & 8'o177; key_up <= 1'b0; end // * :
    /* |   */ 8'h61: begin keycode <=  key_up ? (8'o174 & 8'o17)|8'o200 : 8'o174 & 8'o177; key_up <= 1'b0; end // * :
              8'h7E: begin osd_en  <=  key_up ? 1'b0 : 1'b1; key_up <= 1'b0; end // osd menu
              default: begin key_up  <= 1'b0; keycode <= 0; end
			endcase

reg [7:0]keycode_old = 0;
reg		press_btn = 0;

always @(negedge clk50)
	if(keycode_old!=keycode && |keycode)begin press_btn <= 1'b1;keycode_old <= keycode; end
	else if(read) begin press_btn <= 1'b0; end

endmodule
