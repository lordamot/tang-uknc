// The keyboard byte queue in xm2-01.v (Sep 2026).
//
// The MCU sends a burst of key bytes at SPI speed - a few microseconds
// apart, each held only until the next - while the PPU reads R177700 and
// R177702 slowly, tens of microseconds per look.  Every byte must reach
// the PPU, in order, and none may be reported twice.  Before the queue
// the second byte of a burst replaced the first unread.
`timescale 1ns/1ps
module tb_kbd;
reg clk25 = 0; always #20  clk25 = ~clk25;   // 25 MHz, the timer prescaler
reg clkp  = 0; always #160 clkp  = ~clkp;    // 3.125 MHz, the PPU clock
reg init  = 1;

reg  [16:0] adr = 0;
reg  [15:0] dat_i = 0;
wire [15:0] dat_o;
reg         wre = 0, stb = 0;
wire        ack;
wire [15:0] wbi_dat;
wire        wbi_ack, virq, dclo, aclo, halt, wbi_stb_o, snd;
reg  [ 7:0] but = 8'hff;                     // what hid.v presents after reset

xm2_01 dut(
    .pin_vm_clk25(clk25), .pin_vm_clk_p(clkp), .pin_vm_init_i(init),
    .pin_vm_virq_o(virq),
    .pin_wbm_adr_i(adr), .pin_wbm_dat_i(dat_i), .pin_wbm_dat_o(dat_o),
    .pin_wbm_wre_i(wre), .pin_wbm_stb_i(stb), .pin_wbm_ack_o(ack),
    .pin_wbi_dat_o(wbi_dat), .pin_wbi_ack_o(wbi_ack), .pin_wbi_stb_i(1'b0),
    .pin_vm_dclo_o(dclo), .pin_vm_aclo_o(aclo), .pin_vm_halt_o(halt),
    .pin_wbi_stb_o(wbi_stb_o),
    .but_data(but), .sound(snd));

task bus_read(input [16:0] a, output [15:0] d);
begin
    @(posedge clkp); adr <= a; wre <= 0; stb <= 1;
    @(posedge clkp); while(!ack) @(posedge clkp);
    d = dat_o;
    stb <= 0; @(posedge clkp); @(posedge clkp);
end
endtask

// the PPU: look at the status word every `poll` ns, take the byte if there is one
integer  poll = 40000;
reg [7:0] got [0:63];
integer  ngot = 0;
reg      rom_on = 1;
reg [15:0] w;
initial begin
    @(negedge init);
    while(rom_on) begin
        #(poll);
        bus_read(17'o177700, w);
        if(w[7]) begin
            bus_read(17'o177702, w);
            got[ngot] = w[7:0]; ngot = ngot + 1;
        end
    end
end

// the MCU: a byte, then a gap
task mcu(input [7:0] b, input integer gap);
begin
    but = b; #(gap);
end
endtask

reg [7:0] sent [0:63];
integer  nsent = 0, i, errors = 0;
task send(input [7:0] b, input integer gap);
begin
    sent[nsent] = b; nsent = nsent + 1;
    mcu(b, gap);
end
endtask

initial begin
    #2000 init = 0;
    #100000;
    // 1. one key, slow: press and release a second apart
    send(8'o072, 200000);  send(8'o212, 200000);
    // 2. a burst at SPI speed: Shift and a letter in one report, then the
    //    rollover release-and-press the firmware makes, 1.5 us apart
    send(8'o105, 1500);  send(8'o030, 1500);  send(8'o210, 1500);  send(8'o205, 300000);
    // 3. a burst with the PPU very slow
    poll = 400000;
    send(8'o072, 1500);  send(8'o212, 1500);  send(8'o132, 1500);  send(8'o212, 1500);  send(8'o076, 1500);  send(8'o206, 2000000);
    poll = 40000;
    // 4. the same byte twice in a row is one change: that is what hid.v
    //    gives us, and the firmware never sends it - but it must not hang
    send(8'o072, 200000);  mcu(8'o072, 200000);  send(8'o212, 300000);
    rom_on = 0;
    #500000;
    if(ngot != nsent) begin $display("FAIL: sent %0d bytes, PPU read %0d", nsent, ngot); errors = errors + 1; end
    for(i = 0; i < nsent && i < ngot; i = i + 1)
        if(got[i] !== sent[i]) begin $display("FAIL: byte %0d sent %03o read %03o", i, sent[i], got[i]); errors = errors + 1; end
    if(errors == 0) $display("PASS: %0d key bytes through xm2-01 in order, bursts included", nsent);
    $finish;
end
endmodule
