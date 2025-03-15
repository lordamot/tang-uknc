module load(
    input             clk,
    input             reset,
    input      [ 3:0] is_mount,

    output reg [31:0] sector_sd,
    output reg [ 3:0] read_sd,
    input             strobe,
    input      [ 8:0] index,
    input      [ 7:0] inbyte,
    input             busy_sd,
    input             done_sd,
    output reg [ 3:0] mounted,
    input             size_0,

    output wire[19:0] dsk_addr,   // 23 bit address 
    input      [31:0] dsk_din,    // data output to disk
    output     [31:0] dsk_dout,   // data input from disk
    output reg        dsk_read,   // disk requests read
    output reg        dsk_wrte,   // disk requests write
    input             dsk_busy,   // operation is run
    input             dsk_asck    // dout is valid. Ready to accept new read/write.
);
initial begin
        dsk_read <= 0;
        dsk_wrte <= 0;
        mounted  <= 0;
    end
//----------------------------------------------------------------
// Start ram for dks image
//----------------------------------------------------------------
localparam disk1 = 20'd0;
localparam disk2 = 20'd204800;
localparam disk3 = 20'd409600;
localparam disk4 = 20'd614400;
//----------------------------------------------------------------
reg  [ 2:0] step = 0;
reg  [ 3:0] mount = 0;
reg  [10:0] read_blk = 0;
reg         buff_ld = 0;
reg         oper_sd = 0;

reg  [ 6:0] index32 = 0;

reg  [ 1:0] test_step = 0;
reg  [19:0] test_addr = 0;

wire is_mnt = |is_mount && size_0==0;
wire [19:0] addr = mount[1] ? disk2 :
                   mount[2] ? disk3 :
                   mount[3] ? disk4 : disk1;

assign dsk_addr = oper_sd ? test_addr : addr + {read_blk,index32};

always @(posedge clk)// or posedge is_mnt)
    if(is_mnt)begin
        step      <= 0;
        //mount     <= mount|is_mount;
        case(is_mount)
        'b0001 : begin mount <= 4'b0001; mounted[0] <= 1'b0; step <= 0; end
        'b0010 : begin mount <= 4'b0010; mounted[1] <= 1'b0; step <= 0; end
        'b0100 : begin mount <= 4'b0100; mounted[2] <= 1'b0; step <= 0; end
        'b1000 : begin mount <= 4'b1000; mounted[3] <= 1'b0; step <= 0; end
        endcase

        read_blk  <= 0;
        sector_sd <= 0;
        read_sd   <= 0;
        buff_ld   <= 0;
        index32   <= 0;
        dsk_wrte  <= 0;
        test_step <= 0;
        test_addr <= 0;
        oper_sd   <= 0;
    end else begin
        case(step)
//------------------------------------------------------
// sd-block is read in buferr
//------------------------------------------------------
        'd0 : begin
                sector_sd <= read_blk;
                read_sd   <= mount;
                step      <= step + 1'b1;
              end
        'd1 : if(busy_sd)begin
                read_sd <= 0;
                step    <= step + 1'b1;
              end
        'd2 : if(done_sd)step <= step + 1'b1;
//------------------------------------------------------
// sd-block is readed in buferr, flush buffer in ram
//------------------------------------------------------
        'd3 : begin
                dsk_wrte <= 1'b1;
                step     <= step + 1'b1;
              end
        'd4 : if(dsk_busy)begin
                step     <= step + 1'b1;
              end
        'd5 : if(dsk_asck)begin
                dsk_wrte <= 1'b0;
                if(&index32)begin
                    if(read_blk < 1599)begin
                        read_blk <= read_blk + 1'b1;
                        index32  <= 0;
                        step     <= 0;
                    end else begin
                        mounted  <= mounted|mount;
                        mount    <= 0;
                        step     <= step + 1'b1;
                        index32  <= 0;
                        oper_sd  <= 1'b1;
                    end
                end else begin
                    index32 <= index32 + 1'b1;
                    step    <= 3'd3;
                end
              end
//------------------------------------------------------
// test
//------------------------------------------------------
        'd6 : case(test_step)
              'd0 : begin
                        dsk_read  <= 1'b1;
                        test_step <= test_step + 1'b1;
                    end
              'd1 : if(dsk_busy)begin
                        test_step <= test_step + 1'b1;
                     end
              'd2 : if(dsk_asck)begin
                        dsk_read  <= 1'b0;
                        if(test_addr < disk2)begin 
                            test_addr <= test_addr + 1'b1;
                            test_step <= 0;
                        end else test_step <= test_step + 1'b1;
                    end
              endcase
        endcase
    end

reg  [ 6:0] adb = 0;

sdbuf_sdpb bf1(
    .clka  (strobe), //input clka
    .cea   (  1'b1), //input cea
    .reseta(is_mnt), //input reseta
    .ada   ( index), //input [8:0] ada
    .din   (inbyte), //input [7:0] din

    .clkb  (  ~clk), //input clkb
    .ceb   (  1'b1), //input ceb
    .resetb(is_mnt), //input resetb
    .oce   (  1'b0), //input oce
    .adb   (index32),  //input [6:0] adb
    .dout  (dsk_dout)  //output [31:0] dout
);

endmodule