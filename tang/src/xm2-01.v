module xm2_01(
   pin_vm_clk25,
   pin_vm_clk_p,

   pin_vm_init_i,

   pin_vm_virq_o,

   pin_wbm_adr_i,
   pin_wbm_dat_i,
   pin_wbm_dat_o,
   pin_wbm_wre_i,
   pin_wbm_stb_i,
   pin_wbm_ack_o,
   pin_wbi_dat_o,
   pin_wbi_ack_o,
   pin_wbi_stb_i,

   pin_vm_dclo_o,
   pin_vm_aclo_o,
   pin_vm_halt_o,

   pin_wbi_stb_o,

   but_data,

    sound
);
input       pin_vm_clk25;
input       pin_vm_clk_p;

input       pin_vm_init_i;

output      pin_vm_virq_o;

input  [16:0]pin_wbm_adr_i;
input  [15:0]pin_wbm_dat_i;
output [15:0]pin_wbm_dat_o;

input        pin_wbm_wre_i;

input        pin_wbm_stb_i;
output       pin_wbm_ack_o;
output [15:0]pin_wbi_dat_o;
output       pin_wbi_ack_o;
input        pin_wbi_stb_i;

output       pin_vm_dclo_o;
output       pin_vm_aclo_o;
output       pin_vm_halt_o;

output       pin_wbi_stb_o;

input  [ 7:0]but_data;

output       sound;
//========================================================================================
wire       ce;
reg        ce_old        = 1'b0;
reg        press_btn     = 1'b0;
reg        wbi_stb_i_old = 0;
reg        ask           = 1'b0;
reg        pin_wbi_ack_o = 1'b0;
reg  [15:0]pin_wbi_dat_o = 0;

reg  [15:0]wbm_dat_o     = 0;
reg  [15:0]R177716       = 16'o40;
reg        R177700       = 1'b0;
reg  [ 7:0]R177702       = 8'd0;
reg  [ 7:0]R177710       = 8'd0;
reg  [11:0]R177712       = 12'd0;
reg  [11:0]R177714       = 12'd0;

wire       setVIRQtm;
wire       setVIRQbt;
reg        enVIRQtm      = 1'b1;
reg        enVIRQbt      = 1'b1;

reg  [ 8:0]count_2mks    = 0;
reg  [ 3:0]count_clk     = 0;
reg  [11:0]count_tmr     = 12'd0;

wire       zero_tmr;
reg        zero_tmr_old  = 0;
wire       timer_clk;

reg        clk8kHz = 0;
wire       clk1kHz;
wire       clk500Hz;
wire       clk250Hz;
wire       clk60Hz;

//========================================================================================
assign pin_wbm_dat_o = wbm_dat_o;
assign pin_wbm_ack_o = ask;// & pin_wbm_stb_i;
assign pin_vm_virq_o = (|{setVIRQtm & enVIRQtm, setVIRQbt & enVIRQbt});
assign pin_vm_aclo_o =~R177716[15];
assign pin_vm_dclo_o = R177716[5];
assign pin_wbi_stb_o = setVIRQtm|setVIRQbt ? 1'b0 : pin_wbi_stb_i;
assign pin_vm_halt_o = R177716[4];
assign setVIRQtm     = &R177710[7:6];
assign setVIRQbt     = press_btn & R177700;

assign ce            = &pin_wbm_adr_i[15:6] && pin_wbm_stb_i;
assign zero_tmr      = !count_tmr;
assign timer_clk     = R177710[2:1]==2'b00 ? count_clk[0] :
                       R177710[2:1]==2'b01 ? count_clk[1] :
                       R177710[2:1]==2'b10 ? count_clk[2] : count_clk[3];
//========================================================================================
/*always @(posedge pin_vm_clk_p or posedge read_kbd)
    if(read_kbd) begin press_btn <= 1'b0; end
    else if(R177702!=but_data && |but_data)begin press_btn <= 1'b1; R177702 <= but_data; end*/
//========================================================================================
reg [11:0]sount_count = 0;
reg [ 6:0]sound_div = 0;
always @(posedge pin_vm_clk25)
   if(sount_count==3124)begin
      sount_count <= 12'd0;
      clk8kHz <= ~clk8kHz;
   end else begin
      sount_count <= sount_count + 1'b1;
      if(sount_count==1562)clk8kHz <= ~clk8kHz;
   end

always @(posedge clk8kHz)sound_div <= sound_div + 1'b1;

assign clk1kHz  = sound_div[4];  // 8000/8   = 1000 Hz
assign clk500Hz = sound_div[5];  // 8000/16  = 500  Hz
assign clk250Hz = sound_div[6];  // 8000/32  = 250  Hz
assign clk60Hz  = !sound_div;    // 8000/128 = 60   Hz
assign sound         = R177716[7] & (clk8kHz & R177716[12]) & (clk1kHz & R177716[11]) &
                      (clk500Hz & R177716[10]) & (clk250Hz & R177716[9]) & (clk60Hz & R177716[8]) || ~(|R177716[12:8]) & R177716[7];
//========================================================================================
always @(posedge pin_vm_clk_p)
    if(pin_vm_init_i)begin
        R177716 <= 16'o40;
        {R177710[6:5],R177710[0]} <= 3'b00;
        ask <= 1'b0;
        pin_wbi_ack_o <= 1'b0;
        enVIRQtm      <= 1'b1;
        enVIRQbt      <= 1'b1;
        zero_tmr_old  <= 1'b0;
    end else begin
        ce_old <= ce;
        zero_tmr_old <= zero_tmr;
        if(!zero_tmr_old && zero_tmr)begin R177710[3] <= R177710[7]; R177710[7] <= 1'b1;end
        R177714 <= R177710[7] ? R177714 : count_tmr;
        if(!pin_wbm_stb_i)begin
            wbm_dat_o    <= 16'o0;
            ask          <= 1'b0;
            if(R177702!=but_data)begin press_btn <= but_data!=0 ? 1'b1 : 1'b0; R177702 <= but_data; end
        end else
        if(~ce_old & ce)begin
            case({pin_wbm_wre_i, pin_wbm_adr_i[5:1]})
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//	read	read	read	read	read	read	read	read	read	read	read	read	read	read	read
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
            'b0_00000: begin
                            ask          <= 1'b1;
                            wbm_dat_o    <= {8'd0,press_btn,R177700,6'b00};
                       end
            'b0_00001: begin
                            ask          <= 1'b1;
                            wbm_dat_o    <= {8'd0,R177702};
                            enVIRQbt     <= 1'b1;
                            press_btn    <= 1'b0;
                       end
            'b0_00010: begin
                            ask          <= 1'b1;
                            wbm_dat_o    <= 16'o0;
                       end
            'b0_00100: begin
                            ask          <= 1'b1;
                            wbm_dat_o    <={8'd0,R177710};
                            R177710[3]   <= 1'b0;
                       end
            'b0_00101: begin
                            //ask <= 1'b1;
                            //wbm_dat_o <={4'd0,R177712};
                       end
            'b0_00110: begin
                            ask          <= 1'b1;
                            wbm_dat_o    <= {4'd0,R177714};
                            enVIRQtm     <= 1'b1;
                            R177710[7]   <= 1'b0;
                       end
            'b0_00111: begin
                            ask          <= 1'b1;
                            wbm_dat_o    <= R177716;
                       end
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//	write	write	write	write	write	write	write	write	write	write	write	write	write	write	write
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
            'b1_00000: begin
                            ask           <= 1'b1;
                            R177700       <= pin_wbm_dat_i[6];
                       end
            'b1_00001: begin
                            ask           <= 1'b1;
                       end
            'b1_00010: begin
                            ask           <= 1'b1;
                       end
            'b1_00100: begin
                            ask           <= 1'b1;
                            R177710[6]    <= pin_wbm_dat_i[6];
                            R177710[4]    <= pin_wbm_dat_i[4];
                            R177710[2:0]  <= pin_wbm_dat_i[2:0];
                       end
            'b1_00101: begin
                            ask           <= 1'b1;
                            R177712       <= pin_wbm_dat_i[11:0];
                            //R177714       <= R177710[7] ? R177714 : pin_wbm_dat_i[11:0];
                       end
            'b1_00110: begin
                            ask           <= 1'b1;
                       end
            'b1_00111: begin
                            ask           <= 1'b1;
                            R177716[15:1] <= pin_wbm_dat_i[15:1];
                       end
            default:        wbm_dat_o     <= 16'o0;
            endcase
        end
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//	VIRQ	VIRQ	VIRQ	VIRQ	VIRQ	VIRQ	VIRQ	VIRQ	VIRQ	VIRQ	VIRQ	VIRQ	VIRQ	VIRQ	VIRQ
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
        wbi_stb_i_old<=pin_wbi_stb_i;
        if(!pin_wbi_stb_i)begin
            pin_wbi_ack_o <= 1'b0;
            pin_wbi_dat_o <= 16'o0;
        end else
        if(!wbi_stb_i_old&&pin_wbi_stb_i)begin
            if(setVIRQtm && enVIRQtm)begin pin_wbi_dat_o <= 16'o304; enVIRQtm <= 1'b0; pin_wbi_ack_o <= 1'b1; end
            else if(setVIRQbt && enVIRQbt)begin pin_wbi_dat_o <= 16'o300; enVIRQbt <= 1'b0; pin_wbi_ack_o <= 1'b1; end
        end
    end
//========================================================================================
always @(posedge pin_vm_clk25)
   if(count_2mks == 24)begin
      count_2mks <=  9'd0;
      count_clk <= count_clk + 1'b1;
   end else count_2mks <= count_2mks + 1'b1;

always @(posedge timer_clk)begin
      if(R177710[0])begin
         if(zero_tmr)count_tmr <= R177712 - 1'b1;
         else count_tmr <= count_tmr - 1'b1;
      end else count_tmr <= R177712;

   end
//========================================================================================
endmodule