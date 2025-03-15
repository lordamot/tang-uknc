module sd_card(
	clk,
	rst_n,
	
	sec, read,
	
	init_o,
	read_o,
	
	mydata_o, myvalid_o,
					
	SD_clk,
	SD_cs,
	SD_datain,
	SD_dataout
);
input  clk;
input rst_n;

input [31:0]sec;
input read;

output init_o/* synthesis keep */;             //SD 初始化完成标识
output read_o;                                 //SD blcok读完成标识

output [7:0]mydata_o/* synthesis keep */;
output myvalid_o/* synthesis keep */;

output SD_clk;
output SD_cs;
output SD_datain;
input  SD_dataout;
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
wire SD_datain_i;
wire SD_datain_r;
reg SD_datain_o;

wire SD_cs_i;
wire SD_cs_r;
reg SD_cs_o;


reg [31:0]read_sec;
reg read_req;

//wire [7:0]mydata_o/* synthesis keep */;
//wire myvalid_o/* synthesis keep */;

//wire init_o/* synthesis keep */;             //SD 初始化完成标识
//wire read_o;                                 //SD blcok读完成标识

reg [3:0] sd_state;

wire [3:0] initial_state;
wire [3:0] read_state;

wire rx_valid;
wire data_come;

wire type_card;

parameter STATUS_INITIAL=4'd0;
parameter STATUS_WRITE=4'd1;
parameter STATUS_READ=4'd2;
parameter STATUS_IDLE=4'd3;

assign SD_cs=SD_cs_o;
assign SD_datain=SD_datain_o;
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//	SD_clk = 25 MHz
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
reg SD_clk = 0;
reg [3:0]count_clk = 4'b0101;
always @(posedge clk)count_clk <= {count_clk[2:0],count_clk[3]};
always @(posedge count_clk[3])SD_clk <= ~SD_clk;
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//	Инициализация SD-карты, блок чтения
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
always @ ( posedge SD_clk or negedge rst_n )
    if( !rst_n ) begin
			sd_state <= STATUS_INITIAL;
			read_req <= 1'b0;
			read_sec <= 32'd0;
	 end
	 else 
	     case( sd_state )

	      STATUS_INITIAL:      // 等待sd卡初始化结束
			if( init_o ) sd_state <= STATUS_IDLE;
			else begin sd_state <= STATUS_INITIAL; end	
		  
			STATUS_READ:        //等待sd卡block读结束
			if( read_o ) begin sd_state <= STATUS_IDLE; end
			else begin read_req<=1'b0; sd_state <= STATUS_READ;  end
			
	      STATUS_IDLE:        //空闲状态
				if(read)begin read_sec <= type_card ? sec : sec<<9; read_req<=1'b1; sd_state <= STATUS_READ; end
				else begin sd_state <= STATUS_IDLE; read_req<=1'b0; end
			
			default: sd_state <= STATUS_IDLE;
	     endcase

//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// Инициализация SD-карты
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
sd_initial	sd_initial_inst(					
						.rst_n(rst_n),
						.SD_clk(SD_clk),
						.SD_cs(SD_cs_i),
						.SD_datain(SD_datain_i),
						.SD_dataout(SD_dataout),
						.rx(),
						.init_o(init_o),
						.state(initial_state),
						.type_card(type_card)

);
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// блок чтения SD-карты
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
sd_read	sd_read_inst(   
						.SD_clk(SD_clk),
						.SD_cs(SD_cs_r),
						.SD_datain(SD_datain_r),
						.SD_dataout(SD_dataout),
						
						.init(init_o),
						.sec(read_sec),
						.read_req(read_req),
						
						.mydata_o(mydata_o),
						.myvalid_o(myvalid_o),
		
						.data_come(data_come),
						.mystate(read_state),
						
						.read_o(read_o)
						
    );

//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//	Выбор сигнала SPI SD-карты
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
always @(*)
	begin
		 case( sd_state )
		 STATUS_INITIAL: begin SD_cs_o<=SD_cs_i;SD_datain_o<=SD_datain_i; end
		 STATUS_READ: begin SD_cs_o<=SD_cs_r;SD_datain_o<=SD_datain_r; end
		 default: begin SD_cs_o<=1'b1;SD_datain_o<=1'b1; end	 
		 endcase
	end
endmodule
