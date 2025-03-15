module mkcolorg(
    addr,
    o177016,
    o177020,
    o177022,
    o177026,
    ADB,

    data_reg_out_plan_out,
    io_dqm_out
);
input  addr;
input  [ 2:0]o177016;
input  [15:0]o177020;
input  [15:0]o177022;
input  [ 2:0]o177026;
input  [ 7:0]ADB;

output [31:0]data_reg_out_plan_out;
output [ 3:0]io_dqm_out;
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// Registers color/pixel/fon
//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
wire [31:0] data_reg_out_plan;

assign data_reg_out_plan[ 7: 0] = {o177022[12],o177022[ 8],o177022[ 4],o177022[ 0],
                                   o177020[12],o177020[ 8],o177020[ 4],o177020[ 0]} & ~ADB[7:0];

assign data_reg_out_plan[15: 8] = {o177022[12],o177022[ 8],o177022[ 4],o177022[ 0],
                                   o177020[12],o177020[ 8],o177020[ 4],o177020[ 0]} & ~ADB[7:0];

assign data_reg_out_plan[23:16] = {o177022[13],o177022[ 9],o177022[ 5],o177022[ 1],
                                   o177020[13],o177020[ 9],o177020[ 5],o177020[ 1]} & ~ADB[7:0];

assign data_reg_out_plan[31:24] = {o177022[14],o177022[10],o177022[ 6],o177022[ 2],
                                   o177020[14],o177020[10],o177020[ 6],o177020[ 2]} & ~ADB[7:0];

/*
assign data_reg_out_plan_out[ 0] = ADB[ 0]?o177016[0]:data_reg_out_plan[ 0];
assign data_reg_out_plan_out[ 1] = ADB[ 1]?o177016[0]:data_reg_out_plan[ 1];
assign data_reg_out_plan_out[ 2] = ADB[ 2]?o177016[0]:data_reg_out_plan[ 2];
assign data_reg_out_plan_out[ 3] = ADB[ 3]?o177016[0]:data_reg_out_plan[ 3];
assign data_reg_out_plan_out[ 4] = ADB[ 4]?o177016[0]:data_reg_out_plan[ 4];
assign data_reg_out_plan_out[ 5] = ADB[ 5]?o177016[0]:data_reg_out_plan[ 5];
assign data_reg_out_plan_out[ 6] = ADB[ 6]?o177016[0]:data_reg_out_plan[ 6];
assign data_reg_out_plan_out[ 7] = ADB[ 7]?o177016[0]:data_reg_out_plan[ 7];
assign data_reg_out_plan_out[ 8] = ADB[ 0]?o177016[0]:data_reg_out_plan[ 8];
assign data_reg_out_plan_out[ 9] = ADB[ 1]?o177016[0]:data_reg_out_plan[ 9];
assign data_reg_out_plan_out[10] = ADB[ 2]?o177016[0]:data_reg_out_plan[10];
assign data_reg_out_plan_out[11] = ADB[ 3]?o177016[0]:data_reg_out_plan[11];
assign data_reg_out_plan_out[12] = ADB[ 4]?o177016[0]:data_reg_out_plan[12];
assign data_reg_out_plan_out[13] = ADB[ 5]?o177016[0]:data_reg_out_plan[13];
assign data_reg_out_plan_out[14] = ADB[ 6]?o177016[0]:data_reg_out_plan[14];
assign data_reg_out_plan_out[15] = ADB[ 7]?o177016[0]:data_reg_out_plan[15];
                                                                           
assign data_reg_out_plan_out[16] = ADB[ 0]?o177016[1]:data_reg_out_plan[16];
assign data_reg_out_plan_out[17] = ADB[ 1]?o177016[1]:data_reg_out_plan[17];
assign data_reg_out_plan_out[18] = ADB[ 2]?o177016[1]:data_reg_out_plan[18];
assign data_reg_out_plan_out[19] = ADB[ 3]?o177016[1]:data_reg_out_plan[19];
assign data_reg_out_plan_out[20] = ADB[ 4]?o177016[1]:data_reg_out_plan[20];
assign data_reg_out_plan_out[21] = ADB[ 5]?o177016[1]:data_reg_out_plan[21];
assign data_reg_out_plan_out[22] = ADB[ 6]?o177016[1]:data_reg_out_plan[22];
assign data_reg_out_plan_out[23] = ADB[ 7]?o177016[1]:data_reg_out_plan[23];
assign data_reg_out_plan_out[24] = ADB[ 0]?o177016[2]:data_reg_out_plan[24];
assign data_reg_out_plan_out[25] = ADB[ 1]?o177016[2]:data_reg_out_plan[25];
assign data_reg_out_plan_out[26] = ADB[ 2]?o177016[2]:data_reg_out_plan[26];
assign data_reg_out_plan_out[27] = ADB[ 3]?o177016[2]:data_reg_out_plan[27];
assign data_reg_out_plan_out[28] = ADB[ 4]?o177016[2]:data_reg_out_plan[28];
assign data_reg_out_plan_out[29] = ADB[ 5]?o177016[2]:data_reg_out_plan[29];
assign data_reg_out_plan_out[30] = ADB[ 6]?o177016[2]:data_reg_out_plan[30];
assign data_reg_out_plan_out[31] = ADB[ 7]?o177016[2]:data_reg_out_plan[31];
*/



assign data_reg_out_plan_out[ 7: 0] = o177016[0] ? data_reg_out_plan[ 7: 0] | ADB[7:0] : data_reg_out_plan[ 7: 0];
assign data_reg_out_plan_out[15: 8] = o177016[0] ? data_reg_out_plan[15: 8] | ADB[7:0] : data_reg_out_plan[15: 8];
assign data_reg_out_plan_out[23:16] = o177016[1] ? data_reg_out_plan[23:16] | ADB[7:0] : data_reg_out_plan[23:16];
assign data_reg_out_plan_out[31:24] = o177016[2] ? data_reg_out_plan[31:24] | ADB[7:0] : data_reg_out_plan[31:24];
assign io_dqm_out = {o177026[2:1],~addr|o177026[0],addr|o177026[0]};

//+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
endmodule

module rd_plan(
    dinp_ram,
    addr,
    o177020_out,
    o177022_out
);
input  [31:0]dinp_ram;
input  addr;
output [15:0]o177020_out;
output [15:0]o177022_out;

assign o177020_out[ 0] = addr ? dinp_ram[ 8]:dinp_ram[0];
assign o177020_out[ 4] = addr ? dinp_ram[ 9]:dinp_ram[1];
assign o177020_out[ 8] = addr ? dinp_ram[10]:dinp_ram[2];
assign o177020_out[12] = addr ? dinp_ram[11]:dinp_ram[3];
assign o177022_out[ 0] = addr ? dinp_ram[12]:dinp_ram[4];
assign o177022_out[ 4] = addr ? dinp_ram[13]:dinp_ram[5];
assign o177022_out[ 8] = addr ? dinp_ram[14]:dinp_ram[6];
assign o177022_out[12] = addr ? dinp_ram[15]:dinp_ram[7];

assign o177020_out[ 1] = dinp_ram[16];
assign o177020_out[ 5] = dinp_ram[17];
assign o177020_out[ 9] = dinp_ram[18];
assign o177020_out[13] = dinp_ram[19];
assign o177022_out[ 1] = dinp_ram[20];
assign o177022_out[ 5] = dinp_ram[21];
assign o177022_out[ 9] = dinp_ram[22];
assign o177022_out[13] = dinp_ram[23];

assign o177020_out[ 2] = dinp_ram[24];
assign o177020_out[ 6] = dinp_ram[25];
assign o177020_out[10] = dinp_ram[26];
assign o177020_out[14] = dinp_ram[27];
assign o177022_out[ 2] = dinp_ram[28];
assign o177022_out[ 6] = dinp_ram[29];
assign o177022_out[10] = dinp_ram[30];
assign o177022_out[14] = dinp_ram[31];

assign o177020_out[ 3] = 1'b0;
assign o177022_out[ 3] = 1'b0;
assign o177020_out[ 7] = 1'b0;
assign o177022_out[ 7] = 1'b0;
assign o177020_out[11] = 1'b0;
assign o177022_out[11] = 1'b0;
assign o177020_out[15] = 1'b0;
assign o177022_out[15] = 1'b0;
endmodule
