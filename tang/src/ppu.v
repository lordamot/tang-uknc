module ppu_wb(
    clk_ppu_p,
    clk_ppu_n,
    rst,
    clk50hz,

    addr_ram,
    duot_ram,
    dinp_ram,
    mask_ram,
    read_ram,
    wrte_ram,
    askn_ram,

    pin_vm_init_o,
    pin_vm_dclo_o,
    pin_vm_aclo_o,

    pin_vm_virq_i,

    pin_wbm_adr_o,
    pin_wbm_dat_o,
    pin_wbm_dat_i,
    pin_wbm_cyc_o,
    pin_wbm_wre_o,
    pin_wbm_sel_o,
    pin_wbm_stb_o,
    pin_wbm_ack_i,
    pin_wbi_dat_i,
    pin_wbi_ack_i,
    pin_wbi_stb_o,

    pin_tmr_ena_o
);
input        clk_ppu_p;
input        clk_ppu_n;
input        rst;
input        clk50hz;

output [15:0]addr_ram;
output [31:0]duot_ram;
input  [31:0]dinp_ram;
output [ 3:0]mask_ram;
output       read_ram;
output       wrte_ram;
input        askn_ram;

output       pin_vm_init_o;
output       pin_vm_dclo_o;
output       pin_vm_aclo_o;

input        pin_vm_virq_i;

output [16:0]pin_wbm_adr_o;
output [15:0]pin_wbm_dat_o;
input  [15:0]pin_wbm_dat_i;
output       pin_wbm_cyc_o;
output       pin_wbm_wre_o;
output [ 1:0]pin_wbm_sel_o;
output       pin_wbm_stb_o;
input        pin_wbm_ack_i;
input  [15:0]pin_wbi_dat_i;
input        pin_wbi_ack_i;
output       pin_wbi_stb_o;

output       pin_tmr_ena_o;
//========================================================================================
//  Wishbone PPU
//========================================================================================
wire        vm_clk_p = clk_ppu_p;
wire        vm_clk_n = clk_ppu_n;

wire        vm_clk_ena  = 1'b0;
wire        vm_clk_slow = 1'b0;

wire        vm_init;
wire        vm_dclo;
wire        vm_aclo;
wire        vm_halt = 1'b0;
wire        vm_evnt;
wire        vm_virq;

wire        wbm_gnt_i = 1'b1;
wire        wbm_ios_o;
wire [16:0] wbm_adr_o;
wire [15:0] wbm_dat_o;
reg  [15:0] wbm_dat_i;
wire        wbm_cyc_o;
wire        wbm_we_o;
wire [ 1:0] wbm_sel_o;
wire        wbm_stb_o;
wire        wbm_ack_i;

wire [15:0] wbi_dat_i;
wire        wbi_ack_i;
wire        wbi_stb_o;
wire        wbi_una_o;


reg         rom = 0;
reg         ram_wr = 0;
reg         ram_rd = 0;
reg         rio = 0;
reg         rio_ram_wr = 0;
reg         rio_ram_rd = 0;
wire [15:0] prom;
reg         ask = 0;

reg  [15:0] addr_ram = 0;
reg  [15:0] data_rio = 0;
reg  [31:0] ramd_rio = 0;
reg  [ 3:0] mask_rio = 0;


reg  [15:0] R177010 = 0;
reg  [15:0] R177012 = 0;
reg  [15:0] R177014 = 0;

reg  [15:0] R177016 = 0;
reg  [15:0] R177020 = 0;
reg  [15:0] R177022 = 0;
reg  [15:0] R177024 = 0;
reg  [15:0] R177026 = 0;

reg  [ 9:0] R177054 = 10'o1401;

wire [31:0] data_reg_out_plan_out;
wire [ 3:0] io_dqm_out;
wire [15:0] o177020_out;
wire [15:0] o177022_out;
//========================================================================================
//  Wishbone out
//========================================================================================
assign pin_vm_init_o = vm_init;
assign pin_vm_dclo_o = vm_dclo;
assign pin_vm_aclo_o = vm_aclo;
assign vm_virq       = pin_vm_virq_i;
assign pin_wbm_adr_o = wbm_adr_o;
assign pin_wbm_dat_o = wbm_dat_o;
assign pin_wbm_cyc_o = wbm_cyc_o;
assign pin_wbm_wre_o = wbm_we_o;
assign pin_wbm_sel_o = wbm_sel_o;
assign pin_wbm_stb_o = wbm_stb_o;
assign pin_wbi_stb_o = wbi_una_o ? 1'b0 : wbi_stb_o;
assign pin_tmr_ena_o = R177054[9];
//========================================================================================
// VIRQ
//========================================================================================
assign wbi_dat_i = (wbi_una_o)? 16'o160000 : wbi_stb_o ? pin_wbi_dat_i : 16'o0;
assign wbi_ack_i = wbi_una_o|pin_wbi_ack_i;
//========================================================================================

always @(*)
    casex({wbm_we_o,pin_wbm_ack_i,rio,ram_rd,rom})
    'b0_xxx1: wbm_dat_i <= prom;
    'b0_xx10: wbm_dat_i <= dinp_ram[15:0];
    'b0_x100: wbm_dat_i <= data_rio;
    'b0_1000: wbm_dat_i <= pin_wbm_dat_i;
    default:  wbm_dat_i <= 16'o0;
    endcase


assign wbm_ack_i = (ask|askn_ram|pin_wbm_ack_i) & wbm_stb_o;
assign duot_ram = rio_ram_wr ? ramd_rio : {wbm_dat_o,wbm_dat_o};
assign mask_ram = (rio_ram_wr|rio_ram_rd) ? mask_rio : {2'b11,~wbm_sel_o};
assign read_ram = (ram_rd|rio_ram_rd) & wbm_stb_o;
assign wrte_ram = (ram_wr|rio_ram_wr) & wbm_stb_o;
//========================================================================================
rom208 d1(
    .dout (           prom), //output [15:0] dout
    .clk  (       vm_clk_n), //input clk
    .oce  (           1'b0), //input oce
    .ce   (           1'b1), //input ce
    .reset(           1'b0), //input reset
    .ad   (wbm_adr_o[14:1])  //input [13:0] ad
    );
//========================================================================================
vm_reset r1
(
   .clk  (vm_clk_p),
   .reset(     rst),
   .dclo ( vm_dclo),
   .aclo ( vm_aclo)
);
//========================================================================================
assign vm_evnt = R177054[8] | clk50hz;
//========================================================================================
vm2_wb #(.VM2_CORE_FIX_PREFETCH(0)) ppu
(
   //
   // Processor core clock section:
   //    - vm_clk_p     - processor core positive clock, also feeds the wishbone buses
   //    - vm_clk_n     - processor core negative clock, should be vm_clk_p 180 degree phase shifted
   //    - vm_clk_ena   - slow clock simulation strobe, enables clock at vm_clk_p
   //    - vm_clk_slow  - clock mode selector, enables clock slowdown simulation,
   //                     the external I/O cycles is launched with rate of vm_clk_ena
   //
    .vm_clk_p   (   vm_clk_p),  // positive edge clock
    .vm_clk_n   (   vm_clk_n),  // negative edge clock
    .vm_clk_ena ( vm_clk_ena),  // slow clock enable
    .vm_clk_slow(vm_clk_slow),  // slow clock sim mode
                                //
    .vm_init    (    vm_init),  // peripheral reset output
    .vm_dclo    (    vm_dclo),  // processor reset
    .vm_aclo    (    vm_aclo),  // power fail notificaton
    .vm_halt    (    vm_halt),  // halt mode interrupt
    .vm_evnt    (    vm_evnt),  // timer interrupt requests
    .vm_virq    (    vm_virq),  // vectored interrupt request
                                //
                                // adr MSB is halt mode flag
    .wbm_gnt_i  (  wbm_gnt_i),  // master wishbone granted
    .wbm_ios_o  (  wbm_ios_o),  // master wishbone I/O select
    .wbm_adr_o  (  wbm_adr_o),  // master wishbone address
    .wbm_dat_o  (  wbm_dat_o),  // master wishbone data output
    .wbm_dat_i  (  wbm_dat_i),  // master wishbone data input
    .wbm_cyc_o  (  wbm_cyc_o),  // master wishbone cycle
    .wbm_we_o   (   wbm_we_o),  // master wishbone direction
    .wbm_sel_o  (  wbm_sel_o),  // master wishbone byte selection
    .wbm_stb_o  (  wbm_stb_o),  // master wishbone strobe
    .wbm_ack_i  (  wbm_ack_i),  // master wishbone acknowledgement
                                //
    .wbi_dat_i  (  wbi_dat_i),  // interrupt vector input
    .wbi_ack_i  (  wbi_ack_i),  // interrupt vector acknowledgement
    .wbi_stb_o  (  wbi_stb_o),  // interrupt vector strobe
    .wbi_una_o  (  wbi_una_o)   // unaddressed read access
);

reg wbm_stb_o_old = 0;
reg read_177124 = 0;

always @(posedge vm_clk_p)
    if(vm_init)begin
        rom <= 1'b0;
        ram_wr <= 1'b0;
        ram_rd <= 1'b0;
        rio <= 1'b0;
        ask <= 1'b0;
        wbm_stb_o_old <= 1'b0;
        rio_ram_wr    <= 1'b0;
        rio_ram_rd    <= 1'b0;
        mask_rio      <= 4'b1100;
        R177054       <= 10'o1401;
    end else begin
        if(askn_ram & rio_ram_rd & !read_177124){R177014,R177012} <= dinp_ram;
        if(askn_ram & rio_ram_rd &  read_177124){R177022,R177020} <= {o177022_out,o177020_out};
        wbm_stb_o_old <= wbm_stb_o;
        if(!wbm_stb_o)begin
            rom         <= 1'b0;
            ram_wr      <= 1'b0;
            ram_rd      <= 1'b0;
            rio         <= 1'b0;
            data_rio    <= 16'o0;
            rio_ram_wr  <= 1'b0;
            rio_ram_rd  <= 1'b0;
            read_177124 <= 1'b0;
            ask <= 1'b0;
        end else
        if(~wbm_stb_o_old & wbm_stb_o)begin
            if(wbm_adr_o[15:9] < 'o100)begin
                addr_ram <= wbm_adr_o[15:0];
                rom      <= 1'b0;
                rio      <= 1'b0;
                ask      <= 1'b0;
                ram_wr   <= wbm_we_o;
                ram_rd   <=~wbm_we_o;
            end else
            if(wbm_adr_o[15:9] < 'o120)begin
                addr_ram <= wbm_adr_o[15:0];
                rom      <= R177054[0];
                ram_wr   <= wbm_we_o;
                ram_rd   <=~(R177054[0]|wbm_we_o) & R177054[4];
                ask      <=~wbm_we_o & R177054[0];
                rio      <= 1'b0;
            end else
            if(wbm_adr_o[15:9] < 'o140)begin
                addr_ram <= wbm_adr_o[15:0];
                rom      <= 1'b1;
                ram_wr   <= wbm_we_o;
                ram_rd   <= 1'b0;
                ask      <=~wbm_we_o;
                rio      <= 1'b0;
            end else
            if(wbm_adr_o[15:9] < 'o160)begin
                addr_ram <= wbm_adr_o[15:0];
                rom      <= 1'b1;
                ram_wr   <= wbm_we_o;
                ram_rd   <= 1'b0;
                ask      <=~wbm_we_o;
                rio      <= 1'b0;
            end else
            if(wbm_adr_o[15:9] < 'o177)begin
                addr_ram <= wbm_adr_o[15:0];
                rom      <= 1'b1;
                ram_wr   <= wbm_we_o;
                ram_rd   <= 1'b0;
                ask      <=~wbm_we_o;
                rio      <= 1'b0;
            end else begin
                rom <= 1'b0;
                ram_wr <= 1'b0;
                ram_rd <= 1'b0;
//========================================================================================
// write write write write write write write write write write write write write write
//========================================================================================
                if(wbm_we_o)begin
                    if(wbm_adr_o[8:1] == 'o4)begin
                        addr_ram[15:8] <= wbm_sel_o[1] ? wbm_dat_o[15:8] : 8'o0;
                        addr_ram[ 7:0] <= wbm_sel_o[0] ? wbm_dat_o[ 7:0] : 8'o0;
                        R177010[15:8]  <= wbm_sel_o[1] ? wbm_dat_o[15:8] : 8'o0;
                        R177010[ 7:0]  <= wbm_sel_o[0] ? wbm_dat_o[ 7:0] : 8'o0;
                        rio_ram_rd     <= 1'b1;
                        mask_rio       <= 4'b0000;
                        ask            <= 1'b0;
                    end else
                    if(wbm_adr_o[8:1] == 'o5)begin 
                        ramd_rio       <= wbm_sel_o[0] ? {2{wbm_dat_o[ 7:0]}} : 16'o0;
                        R177012        <= wbm_sel_o[0] ? {2{wbm_dat_o[ 7:0]}} : 16'o0;
                        addr_ram       <= R177010;
                        mask_rio       <= {2'b11,~R177010[0],R177010[0]};
                        rio_ram_wr     <= 1'b1;
                        ask            <= 1'b0;
                    end else
                    if(wbm_adr_o[8:1] == 'o6)begin
                        ramd_rio[31:24]<= wbm_sel_o[1] ? wbm_dat_o[15:8] : R177014[15:8];
                        ramd_rio[23:16]<= wbm_sel_o[0] ? wbm_dat_o[ 7:0] : R177014[ 7:0];
                        R177014[15:8]  <= wbm_sel_o[1] ? wbm_dat_o[15:8] : R177014[15:8];
                        R177014[ 7:0]  <= wbm_sel_o[0] ? wbm_dat_o[ 7:0] : R177014[ 7:0];
                        addr_ram       <= R177010;
                        mask_rio       <= 4'b0011;
                        rio_ram_wr     <= 1'b1;
                        ask            <= 1'b0;
                    end else
                    if(wbm_adr_o[8:1] == 'o7)begin
                        R177016       <= {13'o0,wbm_dat_o[2:0]};
                        ask           <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o10)begin
                        R177020[15:8] <= wbm_sel_o[1] ? wbm_dat_o[15:8] : 8'o0;
                        R177020[ 7:0] <= wbm_sel_o[0] ? wbm_dat_o[ 7:0] : 8'o0;
                        ask <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o11)begin
                        R177022[15:8] <= wbm_sel_o[1] ? wbm_dat_o[15:8] : 8'o0;
                        R177022[ 7:0] <= wbm_sel_o[0] ? wbm_dat_o[ 7:0] : 8'o0;
                        ask <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o12)begin // 0177024
                        addr_ram      <= R177010;
                        ramd_rio      <= data_reg_out_plan_out;
                        mask_rio      <= io_dqm_out;
                        rio_ram_wr    <= 1'b1;
                        ask           <= 1'b0;
                    end else
                    if(wbm_adr_o[8:1] == 'o13)begin
                        R177026       <= {13'o0,wbm_dat_o[2:0]};
                        ask           <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o26)begin
                        R177054       <= wbm_dat_o[9:0];
                        ask           <= 1'b1;
                    end else 
                    if(wbm_adr_o[8:1] >= 'o14 && wbm_adr_o[8:1] <'o26)begin
                        ask           <= 1'b1;
                    end else
                    /*if(wbm_adr_o[8:1] >= 'o54 && wbm_adr_o[8:1] <'o56)begin
                        ask           <= 1'b1;
                    end else*/
                    begin
                        //ask           <= 1'b1;
                    end

                end else begin
//========================================================================================
// read read read read read read read read read read read read read read read read read
//========================================================================================
                    if(wbm_adr_o[8:1] == 'o4)begin
                        data_rio   <= R177010;
                        ask        <= 1'b1;
                        rio        <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o5)begin
                        data_rio   <= R177010[0] ?  R177012[15:8] : R177012[ 7:0];
                        ask        <= 1'b1;
                        rio        <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o6)begin
                        data_rio   <= R177014;
                        ask        <= 1'b1;
                        rio        <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o7)begin
                        data_rio   <= {13'd0,R177016[2:0]};
                        ask        <= 1'b1;
                        rio        <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o10)begin
                        data_rio   <= R177020;
                        ask        <= 1'b1;
                        rio        <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o11)begin
                        data_rio   <= R177022;
                        ask        <= 1'b1;
                        rio        <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o12)begin //  0177024
                        data_rio   <= 16'd0;
                        rio        <= 1'b1;
                        read_177124<= 1'b1;
                        addr_ram   <= R177010;
                        mask_rio   <= 4'b0000;
                        rio_ram_rd <= 1'b1;
                        ask        <= 1'b0;
                    end else
                    if(wbm_adr_o[8:1] == 'o13)begin
                        data_rio   <= {13'd0,R177026[2:0]};
                        ask        <= 1'b1;
                        rio        <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] == 'o26)begin
                        data_rio   <= {6'd0,R177054};
                        ask        <= 1'b1;
                        rio        <= 1'b1;
                    end else
                    if(wbm_adr_o[8:1] >= 'o14 && wbm_adr_o[8:1] <'o26)begin
                        data_rio   <= 16'o000000;
                        ask        <= 1'b1;
                        rio        <= 1'b1;
                    end else
                    /*if(wbm_adr_o[8:1] >= 'o54 && wbm_adr_o[8:1] <'o56)begin
                        data_rio   <= 16'o000000;
                        ask        <= 1'b1;
                        rio        <= 1'b1;
                    end else*/
                    begin
                        //ask       <= 1'b1;
                    end

                end
            end
        end
    end
//========================================================================================
// Registers color/pixel/fon
//========================================================================================
mkcolorg mc1(
    .addr   (    R177010[0]),
    .o177016(  R177016[2:0]),
    .o177020(       R177020),
    .o177022(       R177022),
    .o177026(  R177026[2:0]),
    .ADB    (wbm_dat_o[7:0]),

    .data_reg_out_plan_out(data_reg_out_plan_out),
    .io_dqm_out           (           io_dqm_out)
);

rd_plan mc2(
    .dinp_ram   (   dinp_ram),
    .addr       (  R177010[0]),
    .o177020_out(o177020_out),
    .o177022_out(o177022_out)
);
endmodule
