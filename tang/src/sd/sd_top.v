module sd_top(
	clk,
	n_rst,
	
	cardinit,
	
	read, sec,
	readok,
	
	//----------------
	// write to ram cache
	mydata_o,
	addrwrite,
	wren,
	//----------------
	
	SD_cd, SD_clk, SD_cs,
	SD_datain, SD_dataout
);
parameter max_sectrs = 1;
input clk;
input n_rst;

output cardinit=inito;

input  read;
input  [31:0]sec;
output readok = datareaded;

//-----------------------------
output [ 7:0]mydata_o;
output [13:0]addrwrite;
output wren = myvalid_o;
//-----------------------------

input  SD_cd;
output SD_clk;
output SD_cs;
output SD_datain;
input  SD_dataout;
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//	sd_card
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
wire inito;
wire reado;
//wire [7:0]mydata_o;
wire myvalid_o;

sd_card sdcrd1(
	.clk(clk),
	.rst_n(n_rst & ~SD_cd),
	.sec(sec+sectrs), .read(readsd),
	
	.init_o(inito),
	.read_o(reado),
	
	.mydata_o(mydata_o), 
	.myvalid_o(myvalid_o),
					
	.SD_clk(SD_clk),
	.SD_cs(SD_cs),
	.SD_datain(SD_datain),
	.SD_dataout(SD_dataout)
);
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// sd buffer
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
reg [13:0]addrwrite = 0;
	
always @(negedge myvalid_o or posedge datareaded)
	if(datareaded)addrwrite <= 0;
	else addrwrite <= addrwrite + 1'b1;
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
reg [ 2:0]step = 0;
reg readsd = 0;
reg [ 4:0]sectrs = 0;
reg datareaded = 0;

always @(posedge clk)
	if(!n_rst || read)begin
		step   <= n_rst ? 3'd1 : 3'd0;
		readsd <= 1'b0;
		sectrs <= 0;
		datareaded <= 1'b0;
	end else begin
		case(step)
		'd0:if( inito)step <= 3'd6;
		'd1:if( reado)begin readsd <= 1'b1; step <= 3'd2; end
		'd2:if(!reado)step <= 3'd3;
		'd3:if( reado)begin step <= 3'd4; readsd <= 1'b0; end
		'd4:begin sectrs <= sectrs + 1'b1; step <= 3'd5; end
		'd5:step <= sectrs < max_sectrs ? 3'd1 : 3'd6;
		default: datareaded <= 1'b1;
		endcase
	end

endmodule
