`timescale 1ns / 100ps

module vp1_120
(
    clk,
    //cpu_vm_clk_p,

    cpu_vm_init_i,

    cpu_vm_virq_o,

    cpu_wbm_adr_i,
    cpu_wbm_dat_i,
    cpu_wbm_dat_o,
    cpu_wbm_cyc_i,
    cpu_wbm_wre_i,
    cpu_wbm_sel_i,
    cpu_wbm_stb_i,
    cpu_wbm_ack_o,
    cpu_wbi_dat_o,
    cpu_wbi_ack_o,
    cpu_wbi_stb_i,

    cpu_wbi_stb_o,

//--------------------------------------------

	//ppu_vm_clk_p,

    ppu_vm_init_i,

    ppu_vm_virq_o,

    ppu_wbm_adr_i,
    ppu_wbm_dat_i,
    ppu_wbm_dat_o,
    ppu_wbm_cyc_i,
    ppu_wbm_wre_i,
    ppu_wbm_sel_i,
    ppu_wbm_stb_i,
    ppu_wbm_ack_o,
    ppu_wbi_dat_o,
    ppu_wbi_ack_o,
    ppu_wbi_stb_i,

    ppu_wbi_stb_o
);
input        clk;
//input        cpu_vm_clk_p;

input        cpu_vm_init_i;

output       cpu_vm_virq_o;

input  [16:0]cpu_wbm_adr_i;
input  [15:0]cpu_wbm_dat_i;
output [15:0]cpu_wbm_dat_o;
input        cpu_wbm_cyc_i;
input        cpu_wbm_wre_i;
input  [ 1:0]cpu_wbm_sel_i;
input        cpu_wbm_stb_i;
output       cpu_wbm_ack_o;
output [15:0]cpu_wbi_dat_o;
output       cpu_wbi_ack_o;
input        cpu_wbi_stb_i;
output       cpu_wbi_stb_o;
//--------------------------------------------
//input        ppu_vm_clk_p;

input        ppu_vm_init_i;

output       ppu_vm_virq_o;

input  [16:0]ppu_wbm_adr_i;
input  [15:0]ppu_wbm_dat_i;
output [15:0]ppu_wbm_dat_o;
input        ppu_wbm_cyc_i;
input        ppu_wbm_wre_i;
input  [ 1:0]ppu_wbm_sel_i;
input        ppu_wbm_stb_i;
output       ppu_wbm_ack_o;
output [15:0]ppu_wbi_dat_o;
output       ppu_wbi_ack_o;
input        ppu_wbi_stb_i;
output       ppu_wbi_stb_o;
//______________________________________________________________________________

wire ceppu = (ppu_wbm_adr_i[15:7]== 9'o774 && ppu_wbm_stb_i);
reg  ceppu_old = 1'b0;
reg  ppu_wbi_stb_i_old = 0;

reg  [15:0]ppu_wbm_dat_o;
reg        ppu_wbm_ack_o = 1'b0;

reg  [15:0]ppu_wbi_dat_o;
reg        ppu_wbi_ack_o = 1'b0;

reg  [ 4:0]P177076 = 5'b11_0_00;
reg  [ 6:0]P177066 = 7'b0000_000;

reg  [ 7:0]P177060 = 0;
reg  [ 7:0]P177062 = 0;
reg  [ 7:0]P177064 = 0;

reg  [ 7:0]portA = 0;
reg  [ 7:0]portB = 0;
reg  [ 7:0]portC = 0;
reg  [ 7:0]portW = 0;

wire cecpu = &cpu_wbm_adr_i[15:10] && cpu_wbm_stb_i;
reg  cecpu_old = 1'b0;
reg  cpu_wbi_stb_i_old = 0;

reg  [15:0]cpu_wbm_dat_o;
reg        cpu_wbm_ack_o = 1'b0;

reg  [15:0]cpu_wbi_dat_o;
reg        cpu_wbi_ack_o = 1'b0;

reg        C177560 = 0;
reg        C176660 = 0;

reg  [ 7:0]C177562 = 0;
reg  [ 7:0]C176662 = 0;

reg        C177564 = 1'b0;
reg        C176664 = 1'b0;
reg        C176674 = 1'b0;

assign cpu_wbi_stb_o = |setVIRQCrx || |setVIRQCtx ? 1'b0 : cpu_wbi_stb_i;
assign ppu_wbi_stb_o = |setVIRQPtx || |setVIRQPrx ? 1'b1 : ppu_wbi_stb_i;

assign cpu_vm_virq_o = (|{setVIRQCrx[1]&enVIRQCrx[1],setVIRQCrx[0]&enVIRQCrx[0],setVIRQCtx[2]&enVIRQCtx[2],setVIRQCtx[1]&enVIRQCtx[1],setVIRQCtx[0]&enVIRQCtx[0]});
assign ppu_vm_virq_o = (|{setVIRQPtx[1]&enVIRQPtx[1],setVIRQPtx[0]&enVIRQPtx[0],setVIRQPrx[3]&enVIRQPrx[3],setVIRQPrx[2]&enVIRQPrx[2],setVIRQPrx[1]&enVIRQPrx[1],setVIRQPrx[0]&enVIRQPrx[0]});
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// ПП передатчик, ЦП приемник, прерывания
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
wire [1:0]setVIRQCrx;
reg  [1:0]enVIRQCrx;
assign setVIRQCrx[1:0] = {~P177076[4]&C176660,~P177076[3]&C177560};

wire [1:0]setVIRQPtx;
reg  [1:0]enVIRQPtx;
assign setVIRQPtx[1:0] = {P177076[4] & P177076[1], P177076[3] & P177076[0]};
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// ЦП передатчик, ПП приемник, прерывания
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
wire [2:0]setVIRQCtx;
reg  [2:0]enVIRQCtx;
assign setVIRQCtx[2:0] = {~P177066[5]&C176674, ~P177066[4]&C176664, ~P177066[3]&C177564};

wire [3:0]setVIRQPrx;
reg  [3:0]enVIRQPrx;
assign setVIRQPrx[3:0] = {~cpu_vm_init_i & P177066[6], P177066[5] & P177066[2], P177066[4] & P177066[1], P177066[3] & P177066[0]};
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
always @(posedge clk)begin
            if(ppu_vm_init_i)begin
                ceppu_old <= 1'b0;
                P177076 <= 5'b11_0_00;
                P177066 <= 7'b0000_000;
                ppu_wbm_ack_o <= 1'b0;
                ppu_wbi_ack_o <= 1'b0;
                portA <= 0;
                portB <= 0;
                portC <= 0;
                portW <= 0;
                enVIRQPtx <= 2'b11;
                enVIRQPrx <= 4'b1111;
            end else begin
                ceppu_old <= ceppu;
					 if(!ppu_wbm_stb_i)begin
							ppu_wbm_dat_o <= 16'o0;
							ppu_wbm_ack_o <= 1'b0;
					 end else
                if(~ceppu_old & ceppu)begin
                    case({ppu_wbm_wre_i, ppu_wbm_adr_i[6:1]})
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//	read	read	read	read	read	read	read	read	read	read	read	read	read	read	read
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//				Приемники ПП 0,1 и 2 канал
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                    // 177060 k0 - data
                    {1'b0,6'o30}: begin ppu_wbm_dat_o <= P177060; P177066[3] <= 1'b0; enVIRQPrx[0] <= 1'b1; ppu_wbm_ack_o <= 1'b1; end
                    // 177062 k1 - data
                    {1'b0,6'o31}: begin ppu_wbm_dat_o <= P177062; P177066[4] <= 1'b0; enVIRQPrx[1] <= 1'b1; ppu_wbm_ack_o <= 1'b1; end
                    // 177064 k2 - data
                    {1'b0,6'o32}: begin ppu_wbm_dat_o <= P177064; P177066[5] <= 1'b0; enVIRQPrx[2] <= 1'b1; ppu_wbm_ack_o <= 1'b1; end
                    // 177066 k0,1,2 - sos
                    {1'b0,6'o33}: begin ppu_wbm_dat_o <= {1'b0,P177066}; ppu_wbm_ack_o <= 1'b1; end
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//				Передатчики ПП 0 и 1 канал
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                    // 177070 k0- data
                    {1'b0,6'o34}: begin ppu_wbm_dat_o <= 16'o0; ppu_wbm_ack_o <= 1'b1; end
                    // 177072 k1- data
                    {1'b0,6'o35}: begin ppu_wbm_dat_o <= 16'o0; ppu_wbm_ack_o <= 1'b1; end
                    // 177074 k1- reserve
                    {1'b0,6'o36}: begin ppu_wbm_dat_o <= 16'o0; ppu_wbm_ack_o <= 1'b1; end
                    // 177076 k0,1- sos
                    {1'b0,6'o37}: begin ppu_wbm_dat_o <= {3'b000,P177076}; ppu_wbm_ack_o <= 1'b1; end
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//				LPT
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                    // Port A/B
                    {1'b0,6'o40}: begin ppu_wbm_dat_o <= ppu_wbm_adr_i[0] ? portB : portA; ppu_wbm_ack_o <= 1'b1; end
                    // Port C / Set byte
                    {1'b0,6'o41}: begin ppu_wbm_dat_o <= ppu_wbm_adr_i[0] ? portW : portC; ppu_wbm_ack_o <= 1'b1; end
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//	write	write	write	write	write	write	write	write	write	write	write	write	write	write	write
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//				Приемники ПП 0,1 и 2 канал
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                    // 177060 k0 - data
                    {1'b1,6'o30}: ppu_wbm_ack_o <= 1'b1;
                    // 177062 k1 - data
                    {1'b1,6'o31}: ppu_wbm_ack_o <= 1'b1;
                    // 177064 k2 - data
                    {1'b1,6'o32}: ppu_wbm_ack_o <= 1'b1;
                    // 177066 k0,1,2 - sos
                    {1'b1,6'o33}: begin P177066[2:0] <= ppu_wbm_dat_i[2:0]; P177066[6] <= ppu_wbm_dat_i[6]; enVIRQPrx[3:0] <= ppu_wbm_dat_i[2:0]; ppu_wbm_ack_o <= 1'b1; end
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//				Передатчики ПП 0 и 1 канал
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                    // 177070 k0- data
                    {1'b1,6'o34}: begin C177562 <= ppu_wbm_dat_i[7:0]; P177076[3] <= 1'b0; enVIRQPtx[0] <= 1'b1; ppu_wbm_ack_o <= 1'b1; end
                    // 177072 k1- data
                    {1'b1,6'o35}: begin C176662 <= ppu_wbm_dat_i[7:0]; P177076[4] <= 1'b0; enVIRQPtx[1] <= 1'b1; ppu_wbm_ack_o <= 1'b1; end
                    // 177074 k1- reserve
                    {1'b1,6'o36}: ppu_wbm_ack_o <= 1'b1;
                    // 177076 k0,1- sos
                    {1'b1,6'o37}: begin P177076[2:0] <= ppu_wbm_dat_i[2:0]; enVIRQPtx[1:0] <= ppu_wbm_dat_i[1:0]; ppu_wbm_ack_o <= 1'b1; end
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//				LPT
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                    // Port A/B
                    {1'b1,6'o40}: begin if(ppu_wbm_adr_i[0])portB <= ppu_wbm_dat_i[7:0]; else portA <= ppu_wbm_dat_i[7:0]; ppu_wbm_ack_o <= 1'b1; end
                    // Port C / Set byte
                    {1'b1,6'o41}: begin if(ppu_wbm_adr_i[0])portW <= ppu_wbm_dat_i[7:0]; else portC <= ppu_wbm_dat_i[7:0]; ppu_wbm_ack_o <= 1'b1; end
                    endcase
                end
                ppu_wbi_stb_i_old <= ppu_wbi_stb_i;
					 if(!ppu_wbi_stb_i)begin
						  ppu_wbi_dat_o <= 16'o0;
                    ppu_wbi_ack_o <= 1'b0;
					 end else
                if(~ppu_wbi_stb_i_old & ppu_wbi_stb_i)begin
							if(setVIRQPrx[3] && enVIRQPrx[3]) begin ppu_wbi_dat_o <= 16'o314; enVIRQPrx[3] <= 1'b0; ppu_wbi_ack_o <= 1'b1; end
							else if(setVIRQPrx[0] && enVIRQPrx[0]) begin ppu_wbi_dat_o <= 16'o320; enVIRQPrx[0] <= 1'b0; ppu_wbi_ack_o <= 1'b1; end
								else if(setVIRQPtx[0] && enVIRQPtx[0])begin ppu_wbi_dat_o <= 16'o324; enVIRQPtx[0] <= 1'b0; ppu_wbi_ack_o <= 1'b1; end
									else if(setVIRQPrx[1] && enVIRQPrx[1]) begin ppu_wbi_dat_o <= 16'o330; enVIRQPrx[1] <= 1'b0; ppu_wbi_ack_o <= 1'b1; end
										else if(setVIRQPtx[1] && enVIRQPtx[1])begin ppu_wbi_dat_o <= 16'o334; enVIRQPtx[1] <= 1'b0; ppu_wbi_ack_o <= 1'b1; end
											else if(setVIRQPrx[2] && enVIRQPrx[2]) begin ppu_wbi_dat_o <= 16'o340; enVIRQPrx[2] <= 1'b0; ppu_wbi_ack_o <= 1'b1; end
												else begin ppu_wbi_ack_o <= 1'b0; ppu_wbi_dat_o <= 16'o0; end
                end
            end
            if(cpu_vm_init_i)begin
                cecpu_old <= 1'b0;
                cpu_wbm_ack_o <= 1'b0;
                cpu_wbi_ack_o <= 1'b0;
                C177560 <= 1'b0;
                C176660 <= 1'b0;
                C177564 <= 1'b0;
                C176664 <= 1'b0;
                C176674 <= 1'b0;
                enVIRQCrx <= 2'b11;
                enVIRQCtx <= 3'b111;
                enVIRQPrx[3] <= 1'b1;
            end else begin
                cecpu_old <= cecpu;
					 if(!cpu_wbm_stb_i)begin
							cpu_wbm_dat_o <= 16'o0;
							cpu_wbm_ack_o <= 1'b0;
					 end else
                if(~cecpu_old & cecpu)begin
                    case({cpu_wbm_wre_i, cpu_wbm_adr_i[9:1]})
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//	read	read	read	read	read	read	read	read	read	read	read	read	read	read	read
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//				Приемники ЦП 0 и 1 канал
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                    //1560 k0 - sos
                    {1'b0,9'o670}: if(P177076[2]) cpu_wbm_ack_o <= 1'b0; else begin cpu_wbm_dat_o <= {1'b0,~P177076[3],C177560,6'o00}; cpu_wbm_ack_o <= 1'b1; end
                    //0660 k1 - sos
                    {1'b0,9'o330}: begin cpu_wbm_dat_o <= {1'b0,~P177076[4],C176660,6'o00}; cpu_wbm_ack_o <= 1'b1; end
                    
                    //1562 k0 - data
                    {1'b0,9'o671}: if(P177076[2]) cpu_wbm_ack_o <= 1'b0; 
											  else begin cpu_wbm_dat_o <= {1'b0,C177562}; P177076[3] <= 1'b1; enVIRQCrx[0] <= 1'b1; cpu_wbm_ack_o <= 1'b1; end
                    //0662 k1 - data
                    {1'b0,9'o331}: begin cpu_wbm_dat_o <= {1'b0,C176662}; P177076[4] <= 1'b1; enVIRQCrx[1] <= 1'b1; cpu_wbm_ack_o <= 1'b1; end
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//				Передатчики ЦП 0, 1 и 2 канал
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                    //1564 k0 - sos
                    {1'b0,9'o672}: if(P177076[2]) cpu_wbm_ack_o <= 1'b0; else begin cpu_wbm_dat_o <= {1'b0,~P177066[3],C177564,6'o00}; cpu_wbm_ack_o <= 1'b1; end
                    //0664 k1 - sos
                    {1'b0,9'o332}: begin cpu_wbm_dat_o <= {1'b0,~P177066[4],C176664,6'o00}; cpu_wbm_ack_o <= 1'b1; end
                    //0674 k2 - sos
                    {1'b0,9'o336}: begin cpu_wbm_dat_o <= {1'b0,~P177066[5],C176674,6'o00}; cpu_wbm_ack_o <= 1'b1; end
                    
                    //1566 k0 - data
                    {1'b0,9'o673}: if(P177076[2]) cpu_wbm_ack_o <= 1'b0; else begin cpu_wbm_dat_o <= 9'o0; cpu_wbm_ack_o <= 1'b1; end
                    //0666 k1 - data
                    {1'b0,9'o333}: begin cpu_wbm_dat_o <= 9'o0; cpu_wbm_ack_o <= 1'b1; end
                    //0676 k2 - data
                    {1'b0,9'o337}: begin cpu_wbm_dat_o <= 9'o0; cpu_wbm_ack_o <= 1'b1; end

                    //0670 - reserve
                    {1'b0,9'o334}: cpu_wbm_ack_o <= 1'b1;
                    //0672 - reserve
                    {1'b0,9'o335}: cpu_wbm_ack_o <= 1'b1;
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//	write	write	write	write	write	write	write	write	write	write	write	write	write	write	write
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//				Приемники ЦП 0 и 1 канал
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                    //1560 k0 - sos
                    {1'b1,9'o670}: if(P177076[2]) cpu_wbm_ack_o <= 1'b0; else begin C177560 <= cpu_wbm_dat_i[6]; enVIRQCrx[0] <= cpu_wbm_dat_i[6]; cpu_wbm_ack_o <= 1'b1; end
                    //0660 k1 - sos
                    {1'b1,9'o330}: begin C176660 <= cpu_wbm_dat_i[6]; enVIRQCrx[1] <= cpu_wbm_dat_i[6]; cpu_wbm_ack_o <= 1'b1; end
                    
                    //1562 k0 - data
                    {1'b1,9'o671}: if(P177076[2]) cpu_wbm_ack_o <= 1'b0; else cpu_wbm_ack_o <= 1'b1;
                    //0662 k1 - data
                    {1'b1,9'o331}: cpu_wbm_ack_o <= 1'b1;
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//				Передатчики ЦП 0, 1 и 2 канал
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                    //1564 k0 - sos
                     {1'b1,9'o672}: if(P177076[2]) cpu_wbm_ack_o <= 1'b0; else begin C177564 <= cpu_wbm_dat_i[6]; enVIRQCtx[0] <= cpu_wbm_dat_i[6]; cpu_wbm_ack_o <= 1'b1; end
                    //0664 k1 - sos
                    {1'b1,9'o332}: begin C176664 <= cpu_wbm_dat_i[6]; enVIRQCtx[1] <= cpu_wbm_dat_i[6]; cpu_wbm_ack_o <= 1'b1; end
                    //0674 k2 - sos
                    {1'b1,9'o336}: begin C176674 <= cpu_wbm_dat_i[6]; enVIRQCtx[2] <= cpu_wbm_dat_i[6]; cpu_wbm_ack_o <= 1'b1; end
                    
                    //1566 k0 - data
                    {1'b1,9'o673}: if(P177076[2]) cpu_wbm_ack_o <= 1'b0; else begin P177060 <= cpu_wbm_dat_i[7:0]; P177066[3] <= 1'b1; enVIRQCtx[0] <= 1'b1; cpu_wbm_ack_o <= 1'b1; end
                    //0666 k1 - data
                    {1'b1,9'o333}: begin P177062 <= cpu_wbm_dat_i[7:0]; P177066[4] <= 1'b1; enVIRQCtx[1] <= 1'b1; cpu_wbm_ack_o <= 1'b1; end
                    //0676 k2 - data
                    {1'b1,9'o337}: begin P177064 <= cpu_wbm_dat_i[7:0]; P177066[5] <= 1'b1; enVIRQCtx[2] <= 1'b1; cpu_wbm_ack_o <= 1'b1; end

                    //0670 - reserve
                    {1'b1,9'o334}: cpu_wbm_ack_o <= 1'b1;
                    //0672 - reserve
                    {1'b1,9'o335}: cpu_wbm_ack_o <= 1'b1;
                    endcase
                end
                cpu_wbi_stb_i_old <= cpu_wbi_stb_i;
					 if(!cpu_wbi_stb_i)begin
						  cpu_wbi_dat_o <= 16'o0;
                    cpu_wbi_ack_o <= 1'b0;
					 end else
                if(~cpu_wbi_stb_i_old & cpu_wbi_stb_i)begin
                     if(setVIRQCrx[0] && enVIRQCrx[0])begin cpu_wbi_dat_o <= 16'o60; enVIRQCrx[0] <= 1'b0; cpu_wbi_ack_o <= 1'b1; end
							else if(setVIRQCtx[0] && enVIRQCtx[0])begin cpu_wbi_dat_o <= 16'o64; enVIRQCtx[0] <= 1'b0; cpu_wbi_ack_o <= 1'b1; end
								else if(setVIRQCrx[1] && enVIRQCrx[1])begin cpu_wbi_dat_o <= 16'o460; enVIRQCrx[1] <= 1'b0; cpu_wbi_ack_o <= 1'b1; end
									else if(setVIRQCtx[1] && enVIRQCtx[1])begin cpu_wbi_dat_o <= 16'o464; enVIRQCtx[1] <= 1'b0; cpu_wbi_ack_o <= 1'b1; end
										else if(setVIRQCtx[2] && enVIRQCtx[2])begin cpu_wbi_dat_o <= 16'o474; enVIRQCtx[2] <= 1'b0; cpu_wbi_ack_o <= 1'b1; end
											else begin cpu_wbi_ack_o <= 1'b0; cpu_wbi_dat_o <= 16'o0; end
                end
            end
        end

endmodule
