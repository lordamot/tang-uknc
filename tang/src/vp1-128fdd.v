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
   write,

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
   ind,
   wrprt_dsk
);
input        ppu_vm_clk_p;

input        ppu_vm_init_i;

input  [16:0]ppu_wbm_adr_i;
input  [15:0]ppu_wbm_dat_i;
output [15:0]ppu_wbm_dat_o;
input        ppu_wbm_cyc_i;
input        ppu_wbm_wre_i;
input        ppu_wbm_stb_i;
output       ppu_wbm_ack_o;

input      [15:0]data_in;
output reg [15:0]data_out;
output reg       write;

output reg [ 1:0]drive;
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
input     [ 3:0] wrprt_dsk;
//---------------------------------------------------------------------------------
assign ppu_wbm_dat_o =  dout;
assign ppu_wbm_ack_o =   ask;
assign step          =   stp;

initial begin data_out = 16'd0; write = 1'b0; end

wire r17713x = ~(|((ppu_wbm_adr_i[15:2] ^ 14'o37626)));

reg  [15:0] dout = 16'd0;
reg         ask  =  1'b0;
reg         tr   =  1'b0;
reg         stp  =  1'b0;
wire        wpr  =  wrprt_dsk[drive];
reg  old_valid   =  1'b0;
reg  find_sync   =  1'b0;

always @(posedge ppu_vm_clk_p)begin
         if(ppu_vm_init_i)begin
            drive     <= 2'b00;
            motor     <=  1'b0;
            head      <=  1'b0;
            dir       <=  1'b0;
            ask       <=  1'b0;
            stp       <=  1'b0;
            old_valid <=  1'b0;
            find_sync <=  1'b0;
            write     <=  1'b0;
        end else begin
            old_valid <= valid;
            if(!old_valid && valid)tr <= 1'b1;
            if(sync)find_sync <= 1'b0;

            if(ppu_wbm_stb_i && r17713x)begin
                if(ppu_wbm_adr_i[1])begin   //177132
                    if(ppu_wbm_wre_i)begin
                        data_out <= ppu_wbm_dat_i;
                        write <=    1'b1;
                        tr    <=    1'b0;
                        ask   <=    1'b1;
                    end else begin
                        dout  <= data_in;
                        write <=    1'b0;
                        tr    <=    1'b0;
                        ask   <=    1'b1;
                    end
                end else begin              //177130
                    if(ppu_wbm_wre_i)begin
                        drive <= ppu_wbm_dat_i[10] ? ~ppu_wbm_dat_i[1:0] : 2'b00;
                        motor <= ppu_wbm_dat_i[4];
                        head  <= ppu_wbm_dat_i[5];
                        dir   <= ppu_wbm_dat_i[6];
                        stp   <= ppu_wbm_dat_i[7];
                        if(ppu_wbm_dat_i[8])find_sync <= ~sync;
                        write <=  1'b0;
                        ask   <=  1'b1;
                    end else begin
                        dout  <= find_sync ? 16'h0000: {ind,crc_ok,6'b000000,tr,4'b0000,wpr,rdy,tr0};
                        ask   <=  1'b1;
                        write <=  1'b0;
                    end
                end
            end else begin
                write <=  1'b0;
                ask   <=  1'b0;
                stp   <=  1'b0;
            end
        end
    end
endmodule