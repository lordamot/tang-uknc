`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    sd_initial 
//////////////////////////////////////////////////////////////////////////////////
module sd_initial(

   input rst_n,

   input SD_clk,
   output reg SD_cs,
   output reg SD_datain,
   input  SD_dataout,

   output reg [47:0]rx,
   output reg init_o,
   output reg [3:0] state,
   output reg type_card

);


reg [47:0] CMD0={8'h40,8'h00,8'h00,8'h00,8'h00,8'h95};  //CMD0命令, 需要CRC 95
reg [47:0] CMD8={8'h48,8'h00,8'h00,8'h01,8'haa,8'h87};  //CMD8命令, 需要CRC 87 

reg [47:0] CMD55={8'h77,8'h00,8'h00,8'h00,8'h00,8'hff};  //Команда CMD55, CRC не требуется
reg [47:0] ACMD41={8'h69,8'h40,8'h00,8'h00,8'h00,8'hff}; //CMD41命令, 不需要CRC

reg [47:0] CMD16={8'h50,8'h00,8'h00,8'h02,8'h00,8'hff};  //Команда CMD16, CRC не требуется
reg [47:0] CMD58={8'h7A,8'h00,8'h00,8'h00,8'h00,8'hff};  //Команда CMD58, CRC не требуется

reg [9:0] counter=10'd0;
reg reset=1'b1;

parameter idle=4'b0000;             //状态为idle
parameter send_cmd0=4'b0001;        //状态为发送CMD0
parameter wait_01=4'b0010;          //状态为等待CMD0应答
parameter waitb=4'b0011;            //Статус - ждать в течение определенного периода времени
parameter send_cmd8=4'b0100;        //Статус - отправить CMD8
parameter waita=4'b0101;            //Статус ожидает ответа CMD8
parameter send_cmd55=4'b0110;       //Статус - отправить CMD55
parameter send_acmd41=4'b0111;      //Статус - отправить ACMD41
parameter init_done=4'b1000;        //Статус - конец инициализации
parameter init_fail=4'b1001;        //Статус - ошибка инициализации

parameter send_cmd16=4'b1110;       //Статус - отправить CMD55
parameter send_cmd58=4'b1111;       //Статус - отправить CMD55

reg [9:0] cnt;

reg [5:0]aa;
reg rx_valid;
reg en;

//接收SD卡的数据
always @(posedge SD_clk)
begin
   rx[0]<=SD_dataout;
   rx[47:1]<=rx[46:0];
end

//接收SD的命令应答信号
always @(posedge SD_clk)
begin
   if(!SD_dataout&&!en) begin //Дождитесь, пока SD_dataout станет низким, SD_dataout - низким, и начните получать данные
      rx_valid<=1'b0; 
      aa<=1;
      en<=1'b1;                //en высокий, начните получать данные
   end   
   else if(en)	begin 
      if(aa<47) begin
         aa<=aa+1'b1;  
         rx_valid<=1'b0;
      end
      else begin
         aa<=0;
         en<=1'b0;
         rx_valid<=1'b1;     //После получения 48-го бита сигнал rx_valid становится действительным
      end
   end
   else begin 
      en<=1'b0;
      aa<=0;
      rx_valid<=1'b0;
   end
end

//Отсчет задержки после включения питания, отпустите сигнал сброса
always @(negedge SD_clk or negedge rst_n)
begin
   if (!rst_n) begin
      counter<=0;
      reset<=1'b1;
   end
   else begin
      if(counter<10'd1023) begin 
         counter<=counter+1'b1;
         reset<=1'b1;
      end
      else begin 	
         reset<=1'b0;
      end
   end  
end

//Программа инициализации SD-карты
always @(negedge SD_clk)
begin
	if(reset==1'b1) begin
	  if(counter<512)  begin
		  SD_cs<=1'b0;         //Выбор чипа CS низкоуровневый выбор SD карта
		  SD_datain<=1'b1;
		  init_o<=1'b0;
		  state<=idle;
	  end
	  else begin
		  SD_cs<=1'b1;         //Выбор чипа CS high level release SD карта
		  SD_datain<=1'b1;
		  init_o<=1'b0;
		  state<=idle;
	  end
	end
	else begin
			case(state)
			   idle:	begin
					init_o<=1'b0;
					CMD0<={8'h40,8'h00,8'h00,8'h00,8'h00,8'h95};    
					SD_cs<=1'b1;
					SD_datain<=1'b1;
					state<=send_cmd0;
					cnt<=0;
				end
				send_cmd0: begin              //Отправить команду CMD0 на SD-карту
					if(CMD0!=48'd0) begin
						SD_cs<=1'b0;
						SD_datain<=CMD0[47];
						CMD0<={CMD0[46:0],1'b0};
					end
						else begin
							SD_cs<=1'b0;
							SD_datain<=1'b1;
							state<=wait_01;
							type_card<=0;
						end
				 end
				 wait_01:begin                        //等待SD卡COMD0命令回应0x01
						if(rx_valid&&rx[47:40]==8'h01) begin          
							SD_cs<=1'b1;
							SD_datain<=1'b1;
							state<=waitb;
						end
						else if(rx_valid&&rx[47:40]!=8'h01)	begin
							SD_cs<=1'b1;
							SD_datain<=1'b1;
							state<=idle;
						end
						else begin
							SD_cs<=1'b0;
							SD_datain<=1'b1;
							state<=wait_01;
						end
				  end
				  waitb: begin                //等待一段时间			
						if(cnt<10'd1023)	begin
							SD_cs<=1'b1;
							SD_datain<=1'b1;
							state<=waitb;
							cnt<=cnt+1'b1;
						end
						else begin
							SD_cs<=1'b1;
							SD_datain<=1'b1;
							CMD8<={8'h48,8'h00,8'h00,8'h01,8'haa,8'h87};           
							cnt<=0;
							state<=send_cmd8;
						end
					end
					send_cmd8: begin                     //发送CMD8命令给SD卡	
						if(CMD8!=48'd0) begin
							SD_cs<=1'b0;
							SD_datain<=CMD8[47];
							CMD8<={CMD8[46:0],1'b0};
						end
						else begin
							SD_cs<=1'b0;
							SD_datain<=1'b1;
							state<=waita;
						end
					end
					waita: begin                        //Дождитесь ответа CMD8
						SD_cs<=1'b0;
					   SD_datain<=1'b1;
						if(rx_valid&&rx[19:16]==4'b0001) begin         //SD2.0 card support 2.7V-3.6V supply voltage										
						   state<=send_cmd55;
						   CMD55<={8'h77,8'h00,8'h00,8'h00,8'h00,8'hff};
							ACMD41<={8'h69,8'h40,8'h00,8'h00,8'h00,8'hff};
						end
						else if(rx_valid&&rx[19:16]!=4'b0001)	begin
							state<=init_fail;
						end
 				    end
					 send_cmd55:begin             //发送CMD55 				
						if(CMD55!=48'd0)begin
						   SD_cs<=1'b0;
							SD_datain<=CMD55[47];
							CMD55<={CMD55[46:0],1'b0};
						end
						else begin
						   SD_cs<=1'b0;
							SD_datain<=1'b1;
							if(rx_valid&&rx[47:40]==8'h01)      //Дождитесь, пока CMD55 ответит на сигнал 01
							   state<=send_acmd41;
							else begin
								if(cnt<10'd127)
								   cnt<=cnt+1'b1;
								else begin
  								   cnt<=10'd0;
									state<=init_fail;
							   end
							end
						 end
					  end
					  send_acmd41: begin          //发送ACMD41
						  if(ACMD41!=48'd0) begin						
								SD_cs<=1'b0;
								SD_datain<=ACMD41[47];
								ACMD41<={ACMD41[46:0],1'b0};
							end
							else begin
								SD_cs<=1'b0;
								SD_datain<=1'b1;
								ACMD41<=48'd0;
								if(rx_valid&&rx[47:40]==8'h00)begin     //Подождите, пока CMD55 ответит на сигнал 00
									//state<=init_done;
									//state<=send_cmd16; //// Добавить CMD58 для определения типа карты
									//CMD16={8'h50,8'h00,8'h00,8'h02,8'h00,8'hff};
									state<=send_cmd58; //// Добавить CMD58 для определения типа карты
									CMD58<={8'h7A,8'h00,8'h00,8'h00,8'h00,8'hff};
									cnt<=10'd0;
								end else begin
									if(cnt<10'd127)
									   cnt<=cnt+1'b1;
									else begin
  									   cnt<=10'd0;
										state<=init_fail;
								   end
								end	
							end
						end
						send_cmd16:begin             //CMD16 				
						if(CMD16!=48'd0)begin
						   SD_cs<=1'b0;
							SD_datain<=CMD16[47];
							CMD16<={CMD16[46:0],1'b0};
						end
						else begin
						   SD_cs<=1'b0;
							SD_datain<=1'b1;
							if(rx_valid&&rx[47:40]==8'h00)begin      //Дождитесь, пока CMD16 ответит
							   state<=init_done;
							end else begin
								if(cnt<10'd127)
								   cnt<=cnt+1'b1;
								else begin
  								   cnt<=10'd0;
									state<=init_fail;
							   end
							end
						 end
					  end
					  send_cmd58:begin             //CMD58 				
						if(CMD58!=48'd0)begin
						   SD_cs<=1'b0;
							SD_datain<=CMD58[47];
							CMD58<={CMD58[46:0],1'b0};
						end
						else begin
						   SD_cs<=1'b0;
							SD_datain<=1'b1;
							if(rx_valid)begin      //Дождитесь, пока CMD58 ответит
								type_card<=rx[38];
								CMD16<={8'h50,8'h00,8'h00,8'h02,8'h00,8'hff};
							   state<=rx[38] ? init_done : send_cmd16;
								cnt<=10'd0;
							end else begin
								if(cnt<10'd127)
								   cnt<=cnt+1'b1;
								else begin
  								   cnt<=10'd0;
									state<=init_fail;
							   end
							end
						 end
					  end
					init_done:begin init_o<=1'b1;SD_cs<=1'b1;SD_datain<=1'b1;cnt<=0;end     //初始化完成
					init_fail:begin init_o<=1'b0;SD_cs<=1'b1;SD_datain<=1'b1;cnt<=0;state<=waitb;end       //Инициализация не удалась, повторно отправьте CMD8, CMD55 и CMD41
					default: begin	state<=idle; SD_cs<=1'b1; SD_datain<=1'b1;init_o<=1'b0;end
			endcase
	 end
end

endmodule
