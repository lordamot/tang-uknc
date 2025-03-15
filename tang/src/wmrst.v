module vm_reset
(
   clk,
   reset,
   dclo,
   aclo
);
input  clk;
input  reset;
output dclo;
output aclo;


assign dclo = ~powerup[4];
assign aclo = ~(&powerup[4:3]);

reg [4:0]powerup = 0;
always @(posedge clk or posedge reset)
   if(reset)powerup <= 0;
   else powerup <= !aclo ? powerup : powerup + 1'b1;

endmodule