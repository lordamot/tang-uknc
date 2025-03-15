module cpu_wb(
    clk_ppu_p,
    clk_ppu_n,
    clk50hz,

    addr_ram,
    duot_ram,
    dinp_ram,
    mask_ram,
    read_ram,
    wrte_ram,
    askn_ram,

    pin_vm_init_o,
    pin_vm_dclo_i,
    pin_vm_aclo_i,
    pin_vm_halt_i,

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

    pin_tmr_ena_i
);
input        clk_ppu_p;
input        clk_ppu_n;
input        clk50hz;

output [15:0]addr_ram;
output [31:0]duot_ram;
input  [31:0]dinp_ram;
output [ 3:0]mask_ram;
output       read_ram;
output       wrte_ram;
input        askn_ram;

output       pin_vm_init_o;
input        pin_vm_dclo_i;
input        pin_vm_aclo_i;
input        pin_vm_halt_i;

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

input        pin_tmr_ena_i;
//========================================================================================
//  Wishbone CPU
//========================================================================================
wire       vm_clk_p = clk_ppu_p;
wire       vm_clk_n = clk_ppu_n;

wire       vm_clk_ena  = 1'b0;
wire       vm_clk_slow = 1'b0;

wire       vm_init;
wire       vm_halt   = pin_vm_halt_i;
wire       vm_evnt;
wire       vm_virq;

wire       wbm_gnt_i = 1'b1;
wire       wbm_ios_o;
wire [16:0]wbm_adr_o;
wire [15:0]wbm_dat_o;
reg  [15:0]wbm_dat_i;
wire       wbm_cyc_o;
wire       wbm_we_o;
wire [ 1:0]wbm_sel_o;
wire       wbm_stb_o;
wire       wbm_ack_i;

wire [15:0]wbi_dat_i;
wire       wbi_ack_i;
wire       wbi_stb_o;
wire       wbi_una_o;

reg        ram_rd     = 0;
reg        ram_wr     = 0;
reg        rio        = 0;
reg        rio_ram_wr = 0;
reg        rio_ram_rd = 0;
reg        ask        = 0;

reg  [15:0]addr_ram = 0;
reg  [15:0]data_rio = 0;
reg  [31:0]ramd_rio = 0;
reg  [ 3:0]mask_rio = 0;


reg  [15:0]R176640 = 0;
reg  [15:0]R176642 = 0;
//========================================================================================
//  Wishbone out
//========================================================================================
assign pin_vm_init_o = vm_init;
assign vm_virq       = pin_vm_virq_i;
assign pin_wbm_adr_o = wbm_adr_o;
assign pin_wbm_dat_o = wbm_dat_o;
assign pin_wbm_cyc_o = wbm_cyc_o;
assign pin_wbm_wre_o = wbm_we_o;
assign pin_wbm_sel_o = wbm_sel_o;
assign pin_wbm_stb_o = wbm_stb_o;
assign pin_wbi_stb_o = wbi_una_o ? 1'b0 : wbi_stb_o;
//========================================================================================
// VIRQ
//========================================================================================
assign wbi_dat_i = (wbi_una_o)? 16'o160000 : ((pin_wbi_stb_o) ? pin_wbi_dat_i : 16'o000);
assign wbi_ack_i = wbi_una_o|pin_wbi_ack_i;
//========================================================================================
always @(*)
    casex({wbm_we_o,pin_wbm_ack_i,rio,read_ram})
    'b0_xx1: wbm_dat_i <= dinp_ram[31:16];
    'b0_x10: wbm_dat_i <= data_rio;
    'b0_100: wbm_dat_i <= pin_wbm_dat_i;
    default: wbm_dat_i <= 16'o0;
    endcase

assign wbm_ack_i = (ask|askn_ram|pin_wbm_ack_i) & wbm_stb_o;

assign duot_ram = rio_ram_wr ? ramd_rio : {wbm_dat_o,wbm_dat_o};
assign mask_ram = rio_ram_wr ? {mask_rio[3:2],2'b11} : {~wbm_sel_o,2'b11};
assign read_ram = (ram_rd|rio_ram_rd) & wbm_stb_o;
assign wrte_ram = (ram_wr|rio_ram_wr) & wbm_stb_o;
//========================================================================================
assign vm_evnt = pin_tmr_ena_i|clk50hz;
//========================================================================================
vm2_wb #(.VM2_CORE_FIX_PREFETCH(0)) cpu
(
   //
   // Processor core clock section:
   //    - vm_clk_p     - processor core positive clock, also feeds the wishbone buses
   //    - vm_clk_n     - processor core negative clock, should be vm_clk_p 180 degree phase shifted
   //    - vm_clk_ena   - slow clock simulation strobe, enables clock at vm_clk_p
   //    - vm_clk_slow  - clock mode selector, enables clock slowdown simulation,
   //                     the external I/O cycles is launched with rate of vm_clk_ena
   //
    .vm_clk_p   (     vm_clk_p),  // positive edge clock
    .vm_clk_n   (     vm_clk_n),  // negative edge clock
    .vm_clk_ena (   vm_clk_ena),  // slow clock enable
    .vm_clk_slow(  vm_clk_slow),  // slow clock sim mode
                                  //
    .vm_init    (      vm_init),  // peripheral reset output
    .vm_dclo    (pin_vm_dclo_i),  // processor reset
    .vm_aclo    (pin_vm_aclo_i),  // power fail notificaton
    .vm_halt    (      vm_halt),  // halt mode interrupt
    .vm_evnt    (      vm_evnt),  // timer interrupt requests
    .vm_virq    (      vm_virq),  // vectored interrupt request
                                  //
                                  // adr MSB is halt mode flag
    .wbm_gnt_i  (    wbm_gnt_i),  // master wishbone granted
    .wbm_ios_o  (    wbm_ios_o),  // master wishbone I/O select
    .wbm_adr_o  (    wbm_adr_o),  // master wishbone address
    .wbm_dat_o  (    wbm_dat_o),  // master wishbone data output
    .wbm_dat_i  (    wbm_dat_i),  // master wishbone data input
    .wbm_cyc_o  (    wbm_cyc_o),  // master wishbone cycle
    .wbm_we_o   (     wbm_we_o),  // master wishbone direction
    .wbm_sel_o  (    wbm_sel_o),  // master wishbone byte selection
    .wbm_stb_o  (    wbm_stb_o),  // master wishbone strobe
    .wbm_ack_i  (    wbm_ack_i),  // master wishbone acknowledgement
                                  //
    .wbi_dat_i  (    wbi_dat_i),  // interrupt vector input
    .wbi_ack_i  (    wbi_ack_i),  // interrupt vector acknowledgement
    .wbi_stb_o  (    wbi_stb_o),  // interrupt vector strobe
    .wbi_una_o  (    wbi_una_o)   // unaddressed read access
);

reg wbm_stb_o_old = 0;

always @(posedge vm_clk_p)
    if(vm_init)begin
        ram_rd         <= 1'b0;
        ram_wr         <= 1'b0;
        rio            <= 1'b0;
        ask            <= 1'b0;
        wbm_stb_o_old  <= 1'b0;
        rio_ram_wr     <= 1'b0;
        rio_ram_rd     <= 1'b0;
        mask_rio       <= 4'b0000;
        ramd_rio[15:0] <= 16'h0000;
    end else begin
        if(askn_ram & rio_ram_rd)R176642 <= dinp_ram[31:16];
        wbm_stb_o_old <= wbm_stb_o;
        if(!wbm_stb_o)begin
            ram_rd     <= 1'b0;
            ram_wr     <= 1'b0;
            rio        <= 1'b0;
            data_rio   <= 16'o0;
            rio_ram_wr <= 1'b0;
            rio_ram_rd <= 1'b0;
            ask        <= 1'b0;
        end else
        if(~wbm_stb_o_old & wbm_stb_o)begin
            if(wbm_adr_o[16])begin
                addr_ram <= wbm_adr_o[15:1];
                ram_rd   <=~wbm_we_o;
                ram_wr   <= wbm_we_o;
                rio      <= 1'b0;
                ask      <= 1'b0;
            end else
            if(wbm_adr_o[15:9] < 'o160)begin
                addr_ram <= wbm_adr_o[15:1];
                ram_rd   <=~wbm_we_o;
                ram_wr   <= wbm_we_o;
                rio      <= 1'b0;
                ask      <= 1'b0;
            end else begin
                ram_rd   <= 1'b0;
                ram_wr   <= 1'b0;
//========================================================================================
// write write write write write write write write write write write write write write
//========================================================================================
                if(wbm_we_o)begin
                    if(wbm_adr_o[9:1] == 'o270)begin
                        ask <= 1'b0;
                    end else
                    if(wbm_adr_o[9:1] == 'o271)begin
                        ask <= 1'b1;
                    end else
                    if(wbm_adr_o[9:1] == 'o272)begin
                        ask <= 1'b0;
                    end else
                    if(wbm_adr_o[9:1] == 'o273)begin
                        ask <= 1'b1;
                    end else
                    if(wbm_adr_o[9:1] == 'o320)begin
                        R176640[15:8]  <= wbm_sel_o[1] ? wbm_dat_o[15:8] : 8'o0;
                        R176640[ 7:0]  <= wbm_sel_o[0] ? wbm_dat_o[ 7:0] : 8'o0;
                        ask            <= 1'b1;
                    end else
                    if(wbm_adr_o[9:1] == 'o321)begin
                        ramd_rio[31:24] <= wbm_sel_o[1] ? wbm_dat_o[15:8] : R176642[15:8];
                        ramd_rio[23:16] <= wbm_sel_o[0] ? wbm_dat_o[ 7:0] : R176642[ 7:0];
                        R176642[15:8]   <= wbm_sel_o[1] ? wbm_dat_o[15:8] : R176642[15:8];
                        R176642[ 7:0]   <= wbm_sel_o[0] ? wbm_dat_o[ 7:0] : R176642[ 7:0];
                        addr_ram        <= R176640;
                        mask_rio        <= 4'b0011;
                        rio_ram_wr      <= 1'b1;
                        ask             <= 1'b0;
                    end else begin
                        ram_rd          <= 1'b0;
                        ram_wr          <= 1'b0;
                        rio             <= 1'b0;
                        data_rio        <= 16'o0;
                        rio_ram_wr      <= 1'b0;
                        rio_ram_rd      <= 1'b0;
                        ask             <= 1'b0;
                    end

                end else begin
//========================================================================================
// read read read read read read read read read read read read read read read read read
//========================================================================================
                    if(wbm_adr_o[9:1] == 'o270)begin
                        data_rio     <= 16'o0;
                        ask          <= 1'b1;
                        rio          <= 1'b1;
                    end else
                    if(wbm_adr_o[9:1] == 'o271)begin
                        data_rio     <= 16'o0;
                        ask          <= 1'b1;
                        rio          <= 1'b1;
                    end else
                    if(wbm_adr_o[9:1] == 'o272)begin
                        ask <= 1'b1;
                    end else
                    if(wbm_adr_o[9:1] == 'o273)begin
                        data_rio     <= 16'o0;
                        ask          <= 1'b1;
                        rio          <= 1'b1;
                    end else
                    if(wbm_adr_o[9:1] == 'o274)begin
                        data_rio     <= 16'o0;
                        ask          <= 1'b1;
                        rio          <= 1'b1;
                    end else
                    if(wbm_adr_o[9:1] == 'o275)begin
                        data_rio     <= 16'o0;
                        ask          <= 1'b1;
                        rio          <= 1'b1;
                    end else
                    if(wbm_adr_o[9:1] == 'o276)begin
                        data_rio     <= 16'o0;
                        ask          <= 1'b1;
                        rio          <= 1'b1;
                    end else
                    if(wbm_adr_o[9:1] == 'o277)begin
                        data_rio     <= 16'o0;
                        ask          <= 1'b1;
                        rio          <= 1'b1;
                    end else
                    if(wbm_adr_o[9:1] == 'o320)begin
                        data_rio     <= R176640;
                        rio          <= 1'b1;
                        ask          <= 1'b1;
                    end else
                    if(wbm_adr_o[9:1] == 'o321)begin
                        addr_ram     <= R176640;
                        mask_rio     <= 4'b0000;
                        rio_ram_rd   <= 1'b1;
                        ask          <= 1'b0;
                    end else begin
                        ram_rd       <= 1'b0;
                        ram_wr       <= 1'b0;
                        rio          <= 1'b0;
                        data_rio     <= 16'o0;
                        rio_ram_wr   <= 1'b0;
                        rio_ram_rd   <= 1'b0;
                        ask          <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
