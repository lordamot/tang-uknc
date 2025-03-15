module sdram(
   // interface to the MT48LC16M16 chip
   output reg [10:0] SDRAM_A,       // 13 bit multiplexed address bus
   inout      [15:0] SDRAM_DQ,
   output reg [ 1:0] SDRAM_BA,      // two banks
   output            SDRAM_nCS,     // a single chip select
   output            SDRAM_nWE,     // write enable
   output            SDRAM_nRAS,    // row address select
   output            SDRAM_nCAS,    // columns address select
   output reg        SDRAM_DQML,
   output reg        SDRAM_DQMH,

   // cpu/chipset interface
   input             clkram,      // sdram is accessed at up to 128MHz
   input             lockclk,
   output            init,     // init signal after FPGA config to initialize RAM
   
   output            hsync,
   output            vsync,
   output            visible,
   output     [ 2:0] red,
   output     [ 2:0] green,
   output     [ 2:0] blue,
   
   output            clk_25,
   output            clk_50,

   output            cpu_clk,    // 6.25 MHz
   input      [19:0] cpu_addr,   // 21 bit address 
   output reg [31:0] cpu_dout,   // data output to cpu
   input      [31:0] cpu_din,    // data input from cpu
   input      [ 3:0] cpu_dqm,    // dqm write only
   input             cpu_read,   // cpu requests read
   input             cpu_wrte,   // cpu requests write
   output reg        cpu_busy,   // operation is run
   output reg        cpu_asck,   // dout is valid. Ready to accept new read/write.

   output            ppu_clk,    // 3.12 MHz
   input      [19:0] ppu_addr,   // 20 bit address 
   output reg [31:0] ppu_dout,   // data output to cpu
   input      [31:0] ppu_din,    // data input from cpu
   input      [ 3:0] ppu_dqm,    // dqm write only
   input             ppu_read,   // ppu requests read
   input             ppu_wrte,   // ppu requests write
   output reg        ppu_busy,   // operation is run
   output reg        ppu_asck,   // dout is valid. Ready to accept new read/write.
   
   output reg [31:0] vga_regi,        // vga register isobr
   output reg [31:0] vga_regc         // vga register color
);
// ---------------------------------------------------------------------
// no burst configured
// ---------------------------------------------------------------------
localparam RASCAS_DELAY   = 3'd2;   // tRCD>=20ns -> 2 cycles@64MHz
localparam BURST_LENGTH   = 3'b010; // 000=none, 001=2, 010=4, 011=8
localparam ACCESS_TYPE    = 1'b0;   // 0=sequential, 1=interleaved
localparam CAS_LATENCY    = 3'd2;   // 2/3 allowed
localparam OP_MODE        = 2'b00;  // only 00 (standard operation) allowed
localparam NO_WRITE_BURST = 1'b1;   // 0= write burst enabled, 1=only single access write

localparam MODE = { 1'b0, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH}; 

// ---------------------------------------------------------------------
// ------------------------ cycle state machine ------------------------
// ---------------------------------------------------------------------
localparam STATE_LAST      = 3'd7;   // last state in cycle
// ---------------------------------------------------------------------
// ------------------ generate ram control signals ---------------------
// ---------------------------------------------------------------------

// all possible commands
localparam CMD_INHIBIT         = 4'b1111;
localparam CMD_NOP             = 4'b0111;
localparam CMD_ACTIVE          = 4'b0011;
localparam CMD_READ            = 4'b0101;
localparam CMD_WRITE           = 4'b0100;
localparam CMD_BURST_TERMINATE = 4'b0110;
localparam CMD_PRECHARGE       = 4'b0010;
localparam CMD_AUTO_REFRESH    = 4'b0001;
localparam CMD_LOAD_MODE       = 4'b0000;

// drive control signals according to current command
assign SDRAM_nCS  = sd_cmd[3];
assign SDRAM_nRAS = sd_cmd[2];
assign SDRAM_nCAS = sd_cmd[1];
assign SDRAM_nWE  = sd_cmd[0];
assign init = reset == 0;
assign SDRAM_DQ = SDRAM_DQR;

reg  [15:0] SDRAM_DQR = 16'hZZZZ;
reg  [ 4:0] reset;
reg  [ 3:0] sd_cmd;   // current command sent to sd ram
reg  [10:0] horz = 0;
reg  [ 9:0] vert = 0;
reg  [15:0] vga_adst = 0;        // address string in memory
reg  [15:0] vga_adnx = 16'o270;  // address next string
reg  qutro_reg = 0;
reg  types_reg = 0;
reg  vga_curs  = 0;
reg  scr_data_ll = 0;
reg  scr_data_hl = 0;
reg  ppu_ll = 0;
reg  ppu_hl = 0;
reg  cpu_vl = 0;
reg  curs_set = 1'b0;

always @(posedge curs_set or posedge new_scr)vga_curs <= new_scr ? 1'b0 : ~vga_curs;

wire refresh = !xx;
wire get_regs = xx == 1;

wire [15:0]addr_reg = qutro_reg ?  {vga_adnx[15:3],3'b000} : {vga_adnx[15:2],2'b00};
wire [15:0]addr_scr = vga_adst - 16'd2 + xx;

wire [10:0] reset_addr = (reset == 13)?11'b10000000000:MODE;
wire [ 3:0] q = horz[3:0];
wire cpu_select = &ppu_dqm_new[3:2];

wire new_scr = vert==617 && horz==1599;
wire get_regs_new = ~(vert>19 && vert[0]);



reg  [20:0] cpu_addr_new = 0;
reg  [31:0] cpu_din_new  = 0;
reg  [ 3:0] cpu_dqm_new  = 0;
reg  cpu_read_new = 0;
reg  cpu_wrte_new = 0;


reg  [20:0] ppu_addr_new = 0;
reg  [31:0] ppu_din_new  = 0;
reg  [ 3:0] ppu_dqm_new  = 0;
reg  ppu_read_new = 0;
reg  ppu_wrte_new = 0;


always @(posedge clkram)begin
   scr_data_ll <= 1'b0;
   scr_data_hl <= 1'b0;
   ppu_ll <= 1'b0;
   ppu_hl <= 1'b0;
   cpu_vl <= 1'b0;
   
   if(new_scr)begin
      vga_adnx  <= 16'o270;
      types_reg <= 0;
      qutro_reg <= 0;
      curs_set  <= 0;
   end 
// ---------------------------------------------------------------------
// --------------------------- steps/video ---------------------------
// ---------------------------------------------------------------------
   if(horz==1599)begin
      if(vert == 617)vert <= 10'd0;
      else vert <= vert + 1'b1;
      horz <= 11'd0;
   end else horz <= horz + 1'b1;
// ---------------------------------------------------------------------
// --------------------------- startup/reset ---------------------------
// ---------------------------------------------------------------------

// wait 1ms (32 clkref cycles) after FPGA config is done before going
// into normal operation. Initialize the ram in the last 16 reset cycles (cycles 15-0)
   if(!lockclk)begin
      reset <= 5'h1f;
      horz <= 0;
      vert <= 0;
      //cpu_dout[15:0] <= 0;
   end else if((q == STATE_LAST) && (reset != 0))reset <= reset - 5'd1;
   
   if(reset != 0) begin
      if(q == 0) begin
         SDRAM_A    <= reset_addr;
         SDRAM_BA   <= 2'b00;
         SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
         SDRAM_DQML <= 1;
         SDRAM_DQMH <= 1;
         if(reset == 13)  sd_cmd <= CMD_PRECHARGE;
         else if(reset ==  2)  sd_cmd <= CMD_LOAD_MODE;
         else  sd_cmd <= CMD_INHIBIT;
      end else begin
         SDRAM_A    <= reset_addr;
         SDRAM_BA   <= 2'b00;
         SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
         SDRAM_DQML <= 1;
         SDRAM_DQMH <= 1;
         sd_cmd     <= CMD_INHIBIT;
      end
   end else
   if(refresh)begin
         SDRAM_A      <= 0;
         SDRAM_BA     <= 2'b00;
         SDRAM_DQR     <= 16'bZZZZZZZZZZZZZZZZ;
         SDRAM_DQML   <= 1;
         SDRAM_DQMH   <= 1;
         if(q==7)sd_cmd <= CMD_AUTO_REFRESH;
         else  sd_cmd <= CMD_INHIBIT;
   end else begin
      case (q)
      4'd0 : begin
// ---------------------------------------------------------------------
// --------------------------- control/adress regs ---------------------
// ---------------------------------------------------------------------
               if(get_regs)begin   // Get control register
                  sd_cmd     <= CMD_ACTIVE;
                  SDRAM_A    <= {5'd0, addr_reg[15:10]}; //ppu
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end else begin      // Get adress reg
                  sd_cmd     <= CMD_ACTIVE;
                  SDRAM_A    <= {5'd0, addr_scr[15:10]}; //ppu
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end

             end
      4'd1 : begin
// ---------------------------------------------------------------------
// --------------------------- NOP operation ---------------------------
// ---------------------------------------------------------------------
               begin
                  sd_cmd     <= CMD_INHIBIT;
                  SDRAM_A    <= 0;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end

             end
      4'd2 : begin
// ---------------------------------------------------------------------
// --------------------------- READ CMD --------------------------------
// ---------------------------------------------------------------------
               if(get_regs)begin
                  sd_cmd     <= CMD_READ;
                  SDRAM_A    <= { 2'b10, addr_reg[9:1]}; //Zone ppu
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 0;
                  SDRAM_DQMH <= 0;
               end else begin
                  sd_cmd     <= CMD_READ;
                  SDRAM_A    <= { 2'b10, addr_scr[9:1]}; // Zone ppu
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 0;
                  SDRAM_DQMH <= 0;
               end

             end
      4'd3 : begin
// ---------------------------------------------------------------------
// -------if get register then NOP operation else get scr data----------
// ---------------------------------------------------------------------
               if(get_regs)begin
                  sd_cmd     <= CMD_INHIBIT;
                  SDRAM_A    <= 0;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 0;
                  SDRAM_DQMH <= 0;
               end else begin
                  sd_cmd     <= CMD_ACTIVE;
                  SDRAM_A    <= {4'd0, addr_scr[15:9]}; //Zone cpu
                  SDRAM_BA   <= 2'b01;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end

             end
      4'd4 : begin
// First word data from sdram
// ---------------------------------------------------------------------
// -------if get register then NOP operation else get scr data----------
// ---------------------------------------------------------------------
               if(get_regs)begin
// ---------------------------------------------------------------------
// Get 1 data for video register
// ---------------------------------------------------------------------
                  if(get_regs_new)begin
                     if(qutro_reg)begin
                        if(types_reg)vga_regc[15: 0] <= SDRAM_DQ;
                        else         vga_regi[15: 0] <= SDRAM_DQ;
                     end else        vga_adst        <= SDRAM_DQ;
                  end
// ---------------------------------------------------------------------
                  sd_cmd     <= CMD_INHIBIT;
                  SDRAM_A    <= 0;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 0;
                  SDRAM_DQMH <= 0;
               end else begin
// ---------------------------------------------------------------------
// Get blue data for video data
// ---------------------------------------------------------------------
                  scr_data_ll <= 1'b1;
// ---------------------------------------------------------------------
                  sd_cmd     <= CMD_INHIBIT;
                  SDRAM_A    <= 0;
                  SDRAM_BA   <= 2'b01;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end

             end
      4'd5 : begin
// Second word data from sdram
// ---------------------------------------------------------------------
// -------if get register then NOP operation else CMD scr CPU data -----
// ---------------------------------------------------------------------
               if(get_regs)begin
// ---------------------------------------------------------------------
// Get 2 data for video register
// ---------------------------------------------------------------------
                  if(get_regs_new)begin
                     if(qutro_reg) begin
                        if(types_reg)vga_regc[31:16] <= SDRAM_DQ;
                        else         vga_regi[31:16] <= SDRAM_DQ;
                     end else        vga_adnx        <= SDRAM_DQ;
                  end
// ---------------------------------------------------------------------
                  sd_cmd     <= CMD_INHIBIT;
                  SDRAM_A    <= 0;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 0;
                  SDRAM_DQMH <= 0;
               end else begin
                  sd_cmd     <= CMD_READ;
                  SDRAM_A    <= { 2'b10, addr_scr[8:0]};//cpu
                  SDRAM_BA   <= 2'b01;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 0;
                  SDRAM_DQMH <= 0;
               end

             end
      4'd6 : begin
// Third word data from sdram
// ---------------------------------------------------------------------
// -------if get register then NOP operation else get addr str scr -----
// ---------------------------------------------------------------------
               if(get_regs)begin
// ---------------------------------------------------------------------
// Get 3 data for video register
// ---------------------------------------------------------------------
                  if(get_regs_new)begin
                     if(qutro_reg) vga_adst  <= SDRAM_DQ;
                     else          types_reg <= vga_adnx[2];
                  end
// ---------------------------------------------------------------------
                  sd_cmd     <= CMD_INHIBIT;
                  SDRAM_A    <= 0;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end else begin
                  sd_cmd     <= CMD_INHIBIT;
                  SDRAM_A    <= 0;
                  SDRAM_BA   <= 2'b01;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end

             end
      4'd7 : begin
// Fourth word data from sdram or first data str scr
// ---------------------------------------------------------------------
// -------if get register then NOP operation else get addr str scr -----
// ---------------------------------------------------------------------
               if(get_regs)begin
// ---------------------------------------------------------------------
// Get 4 data for video register
// ---------------------------------------------------------------------
                  if(get_regs_new)begin
                     if(qutro_reg)begin
                        vga_adnx  <= SDRAM_DQ;
                        curs_set  <= SDRAM_DQ[0];
                        qutro_reg <= SDRAM_DQ[1];
                        types_reg <= SDRAM_DQ[2];
                     end else begin
                        qutro_reg <= vga_adnx[1];
                        curs_set  <= vga_adnx[0];
                     end
                  end
// ---------------------------------------------------------------------
                  sd_cmd     <= CMD_INHIBIT;
                  SDRAM_A    <= 0;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end else begin
// ---------------------------------------------------------------------
// Get reg/green data for video data
// ---------------------------------------------------------------------
                  scr_data_hl <= 1'b1;
// ---------------------------------------------------------------------
                  sd_cmd     <= CMD_INHIBIT;
                  SDRAM_A    <= 0;
                  SDRAM_BA   <= 2'b01;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end
// ---------------------------------------------------------------------
// ------------Get new data from ppu/cpu--------------------------------
// ---------------------------------------------------------------------
               cpu_addr_new <= cpu_addr;
               cpu_din_new  <= cpu_din;
               cpu_dqm_new  <= cpu_dqm;
               cpu_read_new <= cpu_read;
               cpu_wrte_new <= cpu_wrte;


               ppu_addr_new <= ppu_addr;
               ppu_din_new  <= ppu_din;
               ppu_dqm_new  <= ppu_dqm;
               ppu_read_new <= ppu_read;
               ppu_wrte_new <= ppu_wrte;
               
             end
      4'd8 : begin
// ---------------------------------------------------------------------
// ----------------Start get PPU data -------------------------------------
// ---------------------------------------------------------------------
               begin
                  sd_cmd     <= CMD_ACTIVE;
                  SDRAM_A    <= ppu_addr_new[20:10]; //ppu
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end

             end
      4'd9 : begin
// ---------------------------------------------------------------------
// --------------------------- NOP operation ---------------------------
// ---------------------------------------------------------------------
               begin
                  sd_cmd     <= CMD_INHIBIT;
                  SDRAM_A    <= 0;
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end

             end
      4'd10: begin
// ---------------------------------------------------------------------
// --------------------------- R/W operation ---------------------------
// ---------------------------------------------------------------------
               if(ppu_wrte_new)begin
// ---------------------------------------------------------------------
// ASK of write operation
// ---------------------------------------------------------------------
                  ppu_ll     <= cpu_select;
// ---------------------------------------------------------------------
                  sd_cmd     <= CMD_WRITE;
                  SDRAM_A    <= { 2'b10, ppu_addr_new[9:1]};//ppu
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQR   <= ppu_din_new[15:0];
                  SDRAM_DQML <= ppu_dqm_new[0];
                  SDRAM_DQMH <= ppu_dqm_new[1];
               end else begin
                  sd_cmd     <= CMD_READ;
                  SDRAM_A    <= { 2'b10, ppu_addr_new[9:1]};//ppu
                  SDRAM_BA   <= 2'b00;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 0;
                  SDRAM_DQMH <= 0;
               end

             end
      4'd11: begin
// ---------------------------------------------------------------------
// -----if ppu_dqm[3:2]!=0 then r/w oper CPU else r/w oper PPU----------
// ---------------------------------------------------------------------
               if(cpu_select)begin
                  sd_cmd     <= CMD_ACTIVE;
                  SDRAM_A    <= cpu_addr_new[19:9]; //Zone cpu
                  SDRAM_BA   <= 2'b01;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end else begin
                  sd_cmd     <= CMD_ACTIVE;
                  SDRAM_A    <= ppu_addr_new[19:9]; //Zone cpu (from register ppu)
                  SDRAM_BA   <= 2'b01;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end

             end
      4'd12: begin
// low word PPU data from sdram
// ---------------------------------------------------------------------
// -------------NOP operation to zone cpu and low word PPU -------------
// ---------------------------------------------------------------------
               if(ppu_read_new)begin 
                  ppu_dout[15: 0] <= SDRAM_DQ;
                  ppu_ll          <= cpu_select;
               end
// ---------------------------------------------------------------------
               begin
                  sd_cmd     <= CMD_INHIBIT;
                  SDRAM_A    <= 0;
                  SDRAM_BA   <= 2'b01;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end

             end
      4'd13: begin
// ---------------------------------------------------------------------
// -------------R/W operation to zone cpu (PPU  regs or CPU)------------
// ---------------------------------------------------------------------
               if(cpu_select)begin
// ---------------------------------------------------------------------
                  if(cpu_wrte_new)begin
                     cpu_vl <= 1'b1;
// ---------------------------------------------------------------------
                     sd_cmd     <= CMD_WRITE;
                     SDRAM_A    <= { 2'b10, cpu_addr_new[8:0]}; //cpu
                     SDRAM_BA   <= 2'b01;
                     SDRAM_DQR   <= cpu_din_new[31:16];
                     SDRAM_DQML <= cpu_dqm_new[2];
                     SDRAM_DQMH <= cpu_dqm_new[3];
                  end else begin
                     sd_cmd     <= CMD_READ;
                     SDRAM_A    <= { 2'b10, cpu_addr_new[8:0]}; //cpu
                     SDRAM_BA   <= 2'b01;
                     SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                     SDRAM_DQML <= 0;
                     SDRAM_DQMH <= 0;
                  end
               end else begin
                  if(ppu_wrte_new)begin
// ---------------------------------------------------------------------
                     ppu_hl <= 1'b1;
// ---------------------------------------------------------------------
                     sd_cmd     <= CMD_WRITE;
                     SDRAM_A    <= { 2'b10, ppu_addr_new[8:0]}; //cpu (from register ppu)
                     SDRAM_BA   <= 2'b01;
                     SDRAM_DQR   <= ppu_din_new[31:16];
                     SDRAM_DQML <= ppu_dqm_new[2];
                     SDRAM_DQMH <= ppu_dqm_new[3];
                  end else begin
                     sd_cmd     <= CMD_READ;
                     SDRAM_A    <= { 2'b10, ppu_addr_new[8:0]}; //cpu (from register ppu)
                     SDRAM_BA   <= 2'b01;
                     SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                     SDRAM_DQML <= 0;
                     SDRAM_DQMH <= 0;
                  end
               end

             end
      4'd14: begin
// ---------------------------------------------------------------------
// --------------------------- NOP operation ---------------------------
// ---------------------------------------------------------------------
               begin
                  sd_cmd     <= CMD_INHIBIT;
                  SDRAM_A    <= 0;
                  SDRAM_BA   <= 2'b01;
                  SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
                  SDRAM_DQML <= 1;
                  SDRAM_DQMH <= 1;
               end
               
             end
      4'd15: begin
// ---------------------------------------------------------------------
// --------------------------- Get data CPU or high PPU-----------------
// ---------------------------------------------------------------------
               if(cpu_select)begin
                  cpu_vl <= cpu_read_new;
                  cpu_dout[31:16] <= SDRAM_DQ;
               end else begin
                  ppu_hl <= ppu_read_new;
                  ppu_dout[31:16] <= SDRAM_DQ;
               end
// ---------------------------------------------------------------------
               sd_cmd     <= CMD_INHIBIT;
               SDRAM_A    <= 0;
               SDRAM_BA   <= 2'b01;
               SDRAM_DQR   <= 16'bZZZZZZZZZZZZZZZZ;
               SDRAM_DQML <= 1;
               SDRAM_DQMH <= 1;
             end
      endcase
      end
   end
//-------------------------------------------------------------------
//-------------PPU/CPU busy/asck signals-----------------------------
//-------------------------------------------------------------------
always @(posedge clkram)begin
      if(init)begin
//-------------------------------------------------------------------
           if(ppu_read|ppu_wrte && !ppu_asck)ppu_busy <= 1'b1;
           else ppu_busy <= 1'b0;
           if(!(ppu_read|ppu_wrte))ppu_asck <= 1'b0;
           if(ppu_hl||ppu_ll)ppu_asck <= 1'b1;
//-------------------------------------------------------------------
           if(cpu_read|cpu_wrte && !cpu_asck)cpu_busy <= 1'b1;
           else cpu_busy <= 1'b0;
           if(!(cpu_read|cpu_wrte))cpu_asck <= 1'b0;
           if(cpu_vl)cpu_asck <= 1'b1;
//-------------------------------------------------------------------
      end else begin
         ppu_busy <= 1'b0;
         ppu_asck <= 1'b0;
         cpu_busy <= 1'b1;
         cpu_asck <= 1'b0;
      end
   end
//---------------------------------------------------------------------------------------------------------//
//          VGA generator
//---------------------------------------------------------------------------------------------------------//
// 640x576 @ 50.00 Hz (GTF) hsync: 29.65 kHz; pclk: 23.72 MHz
// Modeline "640x600_50.00" 25.00 640 656 710 800 600 601 604 618 -HSync +Vsync
//  _____|^^^^^|_______|^^^^^^^^^^^^^^^^^^^^^^^^^^^^|______
//   FP   HSYNC   BP         ACTIVE                    FP
//---------------------------------------------------------------------------------------------------------//
`define HSYNC 64
`define HBP   80
`define HACTV 640
`define HFP   16
`define HSTR  800

`define VSYNC 3
`define VBP   14
`define VACTV 600
`define VFP   1
`define VSTR  618

`define HVS   `HFP + `HSYNC + `HBP
`define VVS   `VFP + `VSYNC + `VBP
wire [ 9:0]x  = horz[10:1];
wire [ 6:0]xx = horz[10:4];

assign clk_50  = clkram; // 50.0 MHz
assign clk_25  = horz[0];// 25.0 MHz
wire   clk_12  = horz[1];// 12.5 MHz
wire   clk_6   = horz[2];// 6.25 MHz
wire   clk_3   = horz[3];// 3.12 MHz

assign cpu_clk = horz[2];// 6.25 MHz
assign ppu_clk = horz[3];// 3.12 MHz

wire   visible_x = x >= `HVS;
wire   visible_s = xx > 1 && xx < 82;
wire   visible_y = vert >= `VVS;
wire   visible_z = vert >= `VVS + 2;
wire   visiblez  = visible_x & visible_z;
assign visible   = visible_x & visible_y;
assign hsync     = x > `HFP && x < (`HFP + `HSYNC);
assign vsync     = vert > `VFP && vert < (`VFP + `VSYNC);
//---------------------------------------------------------------------------------------------------------//
wire   clk_pix = vga_regi[21:20] == 0 ? clk_25 :
                 vga_regi[21:20] == 1 ? clk_12 :
                 vga_regi[21:20] == 2 ? clk_6  : clk_3;
                 
reg  [ 9:0] XXs = 0;
wire [ 6:0] index = XXs[9:3];

always @(posedge clk_pix)
   XXs <= visible_x ? XXs + 1'b1 : 10'd0;

wire   [ 2:0]tripl;


videofifo b1(
    .Reset(refresh), //input Reset

    .Data(addr_scr[0] ? SDRAM_DQ[15:8]:SDRAM_DQ[7:0]), //input [7:0] Data
    .WrClk(clkram), //input WrClk
    .WrEn (scr_data_ll & visible_s), //input WrEn

    .RdClk(clk_pix), //input RdClk
    .RdEn (visiblez), //input RdEn
    .Q    (tripl[0]), //output [0:0] Q

    .Empty(), //output Empty
    .Full() //output Full
	);
 

videofifo r1(
    .Reset(refresh), //input Reset

    .Data(SDRAM_DQ[7:0]), //input [7:0] Data
    .WrClk(clkram), //input WrClk
    .WrEn (scr_data_hl & visible_s), //input WrEn

    .RdClk(clk_pix), //input RdClk
    .RdEn (visiblez), //input RdEn
    .Q    (tripl[1]), //output [0:0] Q

    .Empty(), //output Empty
    .Full() //output Full
	);

videofifo g1(
    .Reset(refresh), //input Reset

    .Data(SDRAM_DQ[15:8]), //input [7:0] Data
    .WrClk(clkram), //input WrClk
    .WrEn (scr_data_hl & visible_s), //input WrEn

    .RdClk(clk_pix), //input RdClk
    .RdEn (visiblez), //input RdEn
    .Q    (tripl[2]), //output [0:0] Q

    .Empty(), //output Empty
    .Full() //output Full
	);

/*
reg  [ 3:0]cvt = 0;
always @*
   case(tripl)
   'b000: cvt <= vga_regc[ 3: 0];
   'b001: cvt <= vga_regc[ 7: 4];
   'b010: cvt <= vga_regc[11: 8];
   'b011: cvt <= vga_regc[15:12];
   'b100: cvt <= vga_regc[19:16];
   'b101: cvt <= vga_regc[23:20];
   'b110: cvt <= vga_regc[27:24];
   'b111: cvt <= vga_regc[31:28];
   endcase*/

reg  [ 3:0]cvt;

always @(*)
    case(tripl)
    3'b000: cvt <= vga_regc[ 3: 0];
    3'b001: cvt <= vga_regc[ 7: 4];
    3'b010: cvt <= vga_regc[11: 8];
    3'b011: cvt <= vga_regc[15:12];
    3'b100: cvt <= vga_regc[19:16];
    3'b101: cvt <= vga_regc[23:20];
    3'b110: cvt <= vga_regc[27:24];
    3'b111: cvt <= vga_regc[31:28];
    endcase

wire [ 2:0]curR = vga_regi[2] ? vga_regi[3] ? 3'b111: 3'b100 : 3'd0;
wire [ 2:0]curG = vga_regi[1] ? vga_regi[3] ? 3'b111: 3'b100 : 3'd0;
wire [ 2:0]curB = vga_regi[0] ? vga_regi[3] ? 3'b111: 3'b100 : 3'd0;

wire cursor_pos = xcursor==index;
wire iscursor   = cursor_pos & vga_curs;

reg  [ 6:0] xcursor = 0;
always @(*)
   case(vga_regi[21:20])
   'b00: xcursor <= vga_regi[14: 8];
   'b01: xcursor <= vga_regi[14: 9];
   'b10: xcursor <= vga_regi[14:10];
   'b11: xcursor <= vga_regi[14:11];
   endcase

assign red   = !iscursor ? (cvt[2] & visiblez ? vga_regi[18] ? 3'b111: cvt[3] ? 3'b110 : 3'b100 : 3'd0) : (visiblez ? curR : 3'd0);
assign green = !iscursor ? (cvt[1] & visiblez ? vga_regi[17] ? 3'b111: cvt[3] ? 3'b110 : 3'b100 : 3'd0) : (visiblez ? curG : 3'd0);
assign blue  = !iscursor ? (cvt[0] & visiblez ? vga_regi[16] ? 3'b111: cvt[3] ? 3'b110 : 3'b100 : 3'd0) : (visiblez ? curB : 3'd0);
//---------------------------------------------------------------------------------------------------------//

endmodule
