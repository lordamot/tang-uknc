//Данные коды ошибок формирует драйвер дисковода в ПЗУ УКНЦ.
//1 - ошибка контрольной суммы зоны данных
//2 - ошибка контрольной суммы заголовка сектора
//4 - не найден маркер данных
//6 - дискета защищена от записи
//7 - нулевая дорожка не обнаружена
//10 - дорожка не обнаружена (её номер равен или больше 128)
//11- ошибочный массив параметров
//13 - неверный формат сектора при форматировании
//14 - ошибка линии ИНДЕКС при форматировании
//100 - ошибка поиска маркера, считываются одни нули
//101 - ошибка поиска маркера, не найдена синхрозона
//102 - не обнаружен адресный маркер заголовка сектора или не обнаружен сектор с заданным номером 

module vp1_128fdd(
   ppu_vm_clk_p,
   clk_25,

   ppu_vm_init_i,

   ppu_wbm_adr_i,
   ppu_wbm_dat_i,
   ppu_wbm_dat_o,
   ppu_wbm_cyc_i,
   ppu_wbm_wre_i,
   ppu_wbm_stb_i,
   ppu_wbm_ack_o,

   data_in,
   data_out,

   drive,
   motor,
   step,
   dir,
   head,
   valid,
   sync,
   crc_ok,
   rdy,
   tr0,
   ind
);
input        ppu_vm_clk_p;
input        clk_25;

input        ppu_vm_init_i;

input  [16:0]ppu_wbm_adr_i;
input  [15:0]ppu_wbm_dat_i;
output [15:0]ppu_wbm_dat_o;
input        ppu_wbm_cyc_i;
input        ppu_wbm_wre_i;
input        ppu_wbm_stb_i;
output       ppu_wbm_ack_o;

input   [15:0]data_in;
output  [15:0]data_out;

output reg [ 2:0]drive;
output reg       motor;
output           step;
output reg       dir;
output reg       head;
input            valid;
input            sync;
input            crc_ok;
input            rdy;
input            tr0;
input            ind;
//---------------------------------------------------------------------------------
// 177130 registr, if write to cmd-registr, if read then status-registr
//---------------------------------------------------------------------------------
wire r177132 = ~(|((ppu_wbm_adr_i[15:1] ^ 15'o77455))) & ppu_wbm_stb_i;
wire r177130 = ~(|((ppu_wbm_adr_i[15:1] ^ 15'o77454))) & ppu_wbm_stb_i;
wire r177130_wr = r177130 & ppu_wbm_wre_i;

assign ppu_wbm_dat_o = find_sync ? 16'h0000:
                       r177130 ? {ind,crc_ok,6'b000000,tr,4'b0000,wpr,rdy,tr0}:data_in;
assign ppu_wbm_ack_o = r177130|r177132;

assign step = r177130_wr & ppu_wbm_dat_i[7];

assign data_out = 16'd0;

reg  gor_en = 1'b0;
reg  wpr    = 1'b0;

always @(posedge r177130_wr or posedge ppu_vm_init_i)
    if(ppu_vm_init_i)begin
        drive <= 3'b000;
        motor <=   1'b0;
        head  <=   1'b0;
        dir   <=   1'b0;
        gor_en<=   1'b0;
    end else begin
        drive <= ppu_wbm_dat_i[10] ? {1'b0,~ppu_wbm_dat_i[1:0]} : 3'b000;
        motor <= ppu_wbm_dat_i[4];
        head  <= ppu_wbm_dat_i[5];
        dir   <= ppu_wbm_dat_i[6];
        gor_en<= ppu_wbm_dat_i[8];
    end
//---------------------------------------------------------------------------------
// Find syncro
//---------------------------------------------------------------------------------
reg  find_sync = 1'b0;
always @(posedge sync or posedge gor_en)find_sync <= sync ? 1'b0 : 1'b1;
//---------------------------------------------------------------------------------
// TR
//---------------------------------------------------------------------------------
reg  tr = 1'b0;
always @(posedge valid or posedge r177132)tr <= valid ? 1'b1 : 1'b0;

//---------------------------------------------------------------------------------
endmodule