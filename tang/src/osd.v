module osd(
    clk,
    nrst,
    osd_en,
    hsync_i,
    vsync_i,
    visible_i,
    red_i,
    green_i,
    blue_i,
    
    red_o,
    green_o,
    blue_o,

    osd_on,
    
    press_btn,
    keycode,
    read_kbd,
    
    osd_addr,
    osd_data,
    
    disk_a,
    disk_b,
    disk_c,
    disk_d,
    
    num_files,

    reset_cpu
);
input         clk      ;
input         nrst     ;
input         osd_en   ;
input         hsync_i  ;
input         vsync_i  ;
input         visible_i;
input  [ 2:0] red_i    ;
input  [ 2:0] green_i  ;
input  [ 2:0] blue_i   ;

output [ 2:0] red_o    ;
output [ 2:0] green_o  ;
output [ 2:0] blue_o   ;

output        osd_on   ;

input         press_btn;
input  [ 7:0] keycode  ;
output reg    read_kbd ;

output [  6:0] osd_addr;
input  [127:0] osd_data;

output [  6:0] disk_a;
output [  6:0] disk_b;
output [  6:0] disk_c;
output [  6:0] disk_d;

input  [  6:0] num_files;

output         reset_cpu;

initial read_kbd = 0;

reg osd_on = 0;
reg rgb_bgr = 0;

reg  [ 2:0] red   = 0;
reg  [ 2:0] green = 0;
reg  [ 2:0] blue  = 0;

wire [ 2:0] red_green = osd_visible ? red   : red_i;
wire [ 2:0] green_red = osd_visible ? green : green_i;

assign red_o   = rgb_bgr ? green_red : red_green;
assign green_o =!rgb_bgr ? green_red : red_green;
assign blue_o  = osd_visible ? blue  : blue_i;

assign osd_addr = hmenu;

reg [9:0] x = 0;
reg [9:0] y = 0;
reg       osd_en_old  = 0;
reg       vsync_i_old = 0;
reg       hsync_i_old = 0;
reg       osd_visible = 0;

wire [7:0]xx = osd_visible ? x - 8'd224 : 8'd0;
wire [7:0]yy = osd_visible ? y - 8'd112 : 8'd0;

always @(posedge clk)begin
        osd_en_old <= osd_en;
        if(!osd_en_old && osd_en)osd_on <= ~osd_on;

        vsync_i_old <= vsync_i;
        hsync_i_old <= hsync_i;

        if(osd_on)begin
            if(!vsync_i_old && vsync_i)begin x <= 10'd0; y<= 10'd0; end
            else if(!hsync_i_old && hsync_i) begin x <= 10'd0; y<= y + 1'b1; end
            else x <= x + visible_i;
            
            if(visible_i)begin
                if(x >= 224 && x < 480 &&  y >= 112 && y < 368) begin 
                   red   <= font[~xx[3:1]] ? 3'b111 : 3'b110;
                   green <= font[~xx[3:1]] ? 3'b111 : 3'b001;
                   blue  <= font[~xx[3:1]] ? 3'b111 : 3'b001;
                osd_visible <= 1'b1; 
                end else begin red <= 3'b000; green <= 3'b000; blue  <= 3'b000; osd_visible <= 1'b0; end
            end else begin
                red <= 3'b000; osd_visible <= 1'b0;
                green <= 3'b000;
                blue  <= 3'b000;
            end

        end else begin
            x<= 10'd0;
            y<= 10'd0;
            red <= 3'b000;
            osd_visible <= 1'b0;
        end
    end

wire [7:0]font;
wire [7:0]font_data;
wire [7:0]char;

osdfont font1(
        .dout (font_data), //output [7:0] dout
        .clk  (     ~clk), //input clk
        .oce  (     1'b0), //input oce
        .ce   (     1'b1), //input ce
        .reset(     1'b0), //input reset
        .ad   ({char[7:0],y[3:1]}) //input [10:0] ad
    );

assign font = is_cur ? ~font_data : font_data;

initial $readmemh("../rom/osd.txt",osdram);

reg [7:0]osdram[0:256];

assign char=osdram[{yy[7:4],xx[7:4]}];


reg press_btn_old = 0;
reg [1:0] vmenu = 0;
reg [6:0] hmenu = 7'd1;
reg       sel_f = 0;
reg       reset_cp = 0;

reg [6:0] disk_mount[0:3]='{{7'd1},{7'd1},{7'd1},{7'd1}};

assign disk_a = disk_mount[0];
assign disk_b = disk_mount[1];
assign disk_c = disk_mount[2];
assign disk_d = disk_mount[3];

assign reset_cpu = reset_cp;

wire is_cur =(sel_f ?
              vmenu == 0 && yy[7:4] == 3 ||
              vmenu == 1 && yy[7:4] == 6 ||
              vmenu == 2 && yy[7:4] == 9 ||
              vmenu == 3 && yy[7:4] == 12 :
              vmenu == 0 && yy[7:4] == 2 ||
              vmenu == 1 && yy[7:4] == 5 ||
              vmenu == 2 && yy[7:4] == 8 ||
              vmenu == 3 && yy[7:4] == 11)&&
              xx[7:4]> 0 && xx[7:4] < 15;

always @(negedge clk)
   if(nrst)begin
      press_btn_old<=press_btn;
      read_kbd <= 1'b0;
      reset_cp <= 1'b0;
      if(!press_btn_old && press_btn)
         case(keycode)
         'o154: // row up
                begin
                  vmenu = sel_f ? vmenu : vmenu - 1'b1;
                  hmenu = disk_mount[vmenu];
                  read_kbd <= 1'b1;
                end
         'o134: // row down
                begin
                  vmenu = sel_f ? vmenu : vmenu + 1'b1;
                  hmenu = disk_mount[vmenu];
                  read_kbd <= 1'b1;
                end
         'o116: // row left
                begin
                  if(sel_f)hmenu <= hmenu > 1 ? hmenu - 1'b1 : num_files;
                  read_kbd <= 1'b1;
                end
         'o133: // row right
                begin
                  if(sel_f)hmenu <= hmenu < num_files ? hmenu + 1'b1 : 7'd1 ;
                  read_kbd <= 1'b1;
                end
         'o153: // enter
                begin
                  if(sel_f)disk_mount[vmenu] <= hmenu;
                  sel_f <= ~sel_f;
                  read_kbd <= 1'b1;
                end
         'o6  : // ESC
                begin
                  sel_f <= 1'b0;
                  read_kbd <= 1'b1;
                  hmenu <= disk_mount[vmenu];
                end
         'o26 : // TAB (RGB/GRB)
                begin
                  rgb_bgr <= ~rgb_bgr;
                  read_kbd <= 1'b1;
                end
         'o4  : begin
                reset_cp <= 1'b1;
                read_kbd <= 1'b1;
                end
         default:
                begin
                  read_kbd <= 1'b1;
                  //sel_f    <= 1'b0;
                end
         endcase
   end else begin
      disk_mount[0:3]<='{{7'd1},{7'd1},{7'd1},{7'd1}};
      hmenu <= 7'd1;
      vmenu <= 2'd0;
      read_kbd <= 1'b1;
      reset_cp <= 1'b0;
   end

reg [ 3:0]y_set = 0;
reg set_name = 1'b0;
always @(negedge clk)
   if(sel_f||read_kbd) begin
      set_name <= 1'b0;
      case(vmenu)
      'd0: begin y_set <= 4'd3 ; set_name <= 1'b1; end
      'd1: begin y_set <= 4'd6 ; set_name <= 1'b1; end
      'd2: begin y_set <= 4'd9 ; set_name <= 1'b1; end
      'd3: begin y_set <= 4'd12; set_name <= 1'b1; end
      endcase
   end else set_name <= 1'b0;

reg  [3:0]draw_char = 4'd1;
reg  [1:0]step_draw = 0;

always @(negedge clk)
   case(step_draw)
   'd0: if(set_name)step_draw <= step_draw + 1'b1;
   'd1: begin
            step_draw <= step_draw + 1'b1;
            draw_char <= draw_char + 1'b1;
        end
   'd2: begin
         if(draw_char==15)begin step_draw <= 'd0; draw_char <= 4'd1; end
         else step_draw <= 'd1;
        end
   endcase
   
always @(posedge clk)
   case(draw_char)
   //'d0 : osdram[{y_set,4'd0 }] <= osd_data[7  :  0];
   //'d0 : osdram[{y_set,4'd1 }] <= osd_data[15 :  8];
   //'d0:  osdram[{4'd0,4'd14 }] <= 8'd38;
   'd1 : osdram[{y_set,4'd1 }] <= osd_data[ 7 :  0];//osd_data[23 : 16];
   'd2 : osdram[{y_set,4'd2 }] <= osd_data[15 :  8];//osd_data[31 : 24];
   'd3 : osdram[{y_set,4'd3 }] <= osd_data[23 : 16];//osd_data[39 : 32];
   'd4 : osdram[{y_set,4'd4 }] <= osd_data[31 : 24];//osd_data[47 : 40];
   'd5 : osdram[{y_set,4'd5 }] <= osd_data[39 : 32];//osd_data[55 : 48];
   'd6 : osdram[{y_set,4'd6 }] <= osd_data[47 : 40];//osd_data[63 : 56];
   'd7 : osdram[{y_set,4'd7 }] <= osd_data[55 : 48];//osd_data[71 : 64];
   'd8 : osdram[{y_set,4'd8 }] <= osd_data[63 : 56];//osd_data[79 : 72];
   'd9 : osdram[{y_set,4'd9 }] <= osd_data[71 : 64];//osd_data[87 : 80];
   'd10: osdram[{y_set,4'd10}] <= osd_data[79 : 72];//osd_data[95 : 88];
   'd11: osdram[{y_set,4'd11}] <= osd_data[87 : 80];//osd_data[103: 96];
   'd12: osdram[{y_set,4'd12}] <= osd_data[95 : 88];//osd_data[111:104];
   'd13: osdram[{y_set,4'd13}] <= osd_data[103: 96];//osd_data[119:112];
   'd14: osdram[{y_set,4'd14}] <= osd_data[111:104];//osd_data[127:120];
   default: ;
   endcase

endmodule