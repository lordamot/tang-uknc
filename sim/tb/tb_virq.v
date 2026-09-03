// The PPU's interrupt-vector chain: xm2-01.v (timer 304, keyboard 300)
// in front of vp1_120.v (the channels, 314..340), wired as top.v wires
// them.  The ROM halts with "ЗАВИСАНИЕ ПРИ ПРИЕМЕ А.В.П." when a vector
// fetch is answered by nobody, and that is what happened (3 Sep 2026,
// MKLAD) whenever a channel interrupt was taken while a timer or key
// request was set but disabled - vector already taken, register not yet
// read - because xm2-01 stopped the strobe on "set" alone.
//
// Three fetches: the timer's (304), then a channel byte's with the
// timer flag still up (320: the case that hung), then a key's (300)
// followed by a channel-1 byte with the key unread (330).
`timescale 1ns/1ps
module tb_virq;
reg clk25 = 0; always #20  clk25 = ~clk25;   // 25 MHz: vp1_120, the timer prescaler
reg clkp  = 0; always #160 clkp  = ~clkp;    // 3.125 MHz: the PPU clock, xm2-01
reg init  = 1;

// the PPU bus, as ppu.v drives it
reg  [16:0] padr = 0;
reg  [15:0] pdat = 0;
reg         pwre = 0, pstb = 0;
wire [15:0] pdat_xm2, pdat_vp;
wire        pack_xm2, pack_vp;
wire        pack = pack_xm2 | pack_vp;
// the CPU bus, as cpu.v drives it
reg  [16:0] cadr = 0;
reg  [15:0] cdat = 0;
reg  [ 1:0] csel = 2'b11;
reg         cwre = 0, cstb = 0;
wire [15:0] cdat_o;
wire        cack, cvirq, cwbi_ack, cwbi_stb_chain;
wire [15:0] cwbi_dat;
// the vector chain
reg         iako = 0;                        // the core's wbi_stb_o
reg         cwbi = 0;                        // the CPU core's wbi_stb_o
wire        stb_chain;                       // xm2 -> vp1_120
wire        virq_xm2, virq_vp;
wire        virq = virq_xm2 | virq_vp;       // top.v: ppu_vm_virq_i
wire [15:0] vec_xm2, vec_vp;
wire        vack_xm2, vack_vp;
wire        vack = vack_xm2 | vack_vp;
wire [15:0] vec = vack_xm2 ? vec_xm2 : vack_vp ? vec_vp : 16'o0;   // top.v's mux
wire        dclo, aclo, halt, snd, chain_out;
reg  [ 7:0] but = 8'hff;

xm2_01 xm2(
    .pin_vm_clk25(clk25), .pin_vm_clk_p(clkp), .pin_vm_init_i(init),
    .pin_vm_virq_o(virq_xm2),
    .pin_wbm_adr_i(padr), .pin_wbm_dat_i(pdat), .pin_wbm_dat_o(pdat_xm2),
    .pin_wbm_wre_i(pwre), .pin_wbm_stb_i(pstb), .pin_wbm_ack_o(pack_xm2),
    .pin_wbi_dat_o(vec_xm2), .pin_wbi_ack_o(vack_xm2), .pin_wbi_stb_i(iako),
    .pin_vm_dclo_o(dclo), .pin_vm_aclo_o(aclo), .pin_vm_halt_o(halt),
    .pin_wbi_stb_o(stb_chain),
    .but_data(but), .sound(snd));

vp1_120 vp(
    .clk(clk25),
    .cpu_vm_init_i(1'b0), .cpu_vm_virq_o(cvirq),
    .cpu_wbm_adr_i(cadr), .cpu_wbm_dat_i(cdat), .cpu_wbm_dat_o(cdat_o),
    .cpu_wbm_cyc_i(cstb), .cpu_wbm_wre_i(cwre), .cpu_wbm_sel_i(csel),
    .cpu_wbm_stb_i(cstb), .cpu_wbm_ack_o(cack),
    .cpu_wbi_dat_o(cwbi_dat), .cpu_wbi_ack_o(cwbi_ack), .cpu_wbi_stb_i(cwbi),
    .cpu_wbi_stb_o(cwbi_stb_chain),
    .ppu_vm_init_i(init), .ppu_vm_virq_o(virq_vp),
    .ppu_wbm_adr_i(padr), .ppu_wbm_dat_i(pdat), .ppu_wbm_dat_o(pdat_vp),
    .ppu_wbm_cyc_i(pstb), .ppu_wbm_wre_i(pwre), .ppu_wbm_sel_i(2'b11),
    .ppu_wbm_stb_i(pstb), .ppu_wbm_ack_o(pack_vp),
    .ppu_wbi_dat_o(vec_vp), .ppu_wbi_ack_o(vack_vp), .ppu_wbi_stb_i(stb_chain),
    .ppu_wbi_stb_o(chain_out));

task ppu_write(input [16:0] a, input [15:0] d);
begin
    @(posedge clkp); padr <= a; pdat <= d; pwre <= 1; pstb <= 1;
    @(posedge clkp); while(!pack) @(posedge clkp);
    pstb <= 0; pwre <= 0; @(posedge clkp); @(posedge clkp);
end
endtask

task ppu_read(input [16:0] a, output [15:0] d);
begin
    @(posedge clkp); padr <= a; pwre <= 0; pstb <= 1;
    @(posedge clkp); while(!pack) @(posedge clkp);
    d = pack_xm2 ? pdat_xm2 : pdat_vp;
    pstb <= 0; @(posedge clkp); @(posedge clkp);
end
endtask

// a CPU byte write, the way the core does it: strobe until acknowledged
task cpu_writeb(input [16:0] a, input [7:0] d);
begin
    @(posedge clk25); cadr <= a; cdat <= {8'd0, d}; csel <= 2'b01; cwre <= 1; cstb <= 1;
    @(posedge clk25); while(!cack) @(posedge clk25);
    cstb <= 0; cwre <= 0; @(posedge clk25); @(posedge clk25);
end
endtask

// the core's vector fetch: strobe, wait up to `limit` PPU clocks for an
// acknowledge, report the vector or the timeout
integer errors = 0;
task fetch(input [15:0] want, input [511:0] what);
integer n; reg got; reg [15:0] v; reg chain0;
begin
    got = 0; v = 0;
    @(posedge clkp); iako <= 1;
    @(posedge clkp); chain0 = stb_chain;     // what the chain says at the strobe's first clock
    for(n = 0; n < 40 && !got; n = n + 1) begin
        @(posedge clkp);
        // the chain is decided before the strobe and must not move
        // during it: a rise here is a second chip seeing a fresh fetch
        if(stb_chain !== chain0) begin
            $display("FAIL: %0s: the chain strobe to vp1_120 changed to %b in the middle of the fetch", what, stb_chain);
            errors = errors + 1; chain0 = stb_chain;
        end
        if(vack) begin got = 1; v = vec; end
    end
    iako <= 0; @(posedge clkp); @(posedge clkp); @(posedge clkp);
    if(!got) begin
        $display("FAIL: %0s: no vector - the fetch times out, the ROM says ЗАВИСАНИЕ ПРИ ПРИЕМЕ А.В.П.", what);
        errors = errors + 1;
    end else if(v !== want) begin
        $display("FAIL: %0s: vector %o, wanted %o", what, v, want);
        errors = errors + 1;
    end else
        $display("ok:   %0s: vector %o", what, v);
end
endtask

// the CPU core's vector fetch through vp1_120, whose chain output goes on
// to vp65: the vector, and the chain must stay put once the synchronised
// strobe is up
task cpu_fetch(input [15:0] want, input [511:0] what);
integer n; reg got; reg [15:0] v; reg chain0;
begin
    got = 0; v = 0;
    @(posedge clk25); cwbi <= 1;
    @(posedge clk25); @(posedge clk25); @(posedge clk25); chain0 = cwbi_stb_chain;
    for(n = 0; n < 40 && !got; n = n + 1) begin
        @(posedge clk25);
        if(cwbi_stb_chain !== chain0) begin
            $display("FAIL: %0s: the chain strobe to vp65 changed to %b in the middle of the fetch", what, cwbi_stb_chain);
            errors = errors + 1; chain0 = cwbi_stb_chain;
        end
        if(cwbi_ack) begin got = 1; v = cwbi_dat; end
    end
    if(got && chain0) begin $display("FAIL: %0s: vp1_120 answered and passed the strobe on as well", what); errors = errors + 1; end
    cwbi <= 0; @(posedge clk25); @(posedge clk25); @(posedge clk25); @(posedge clk25);
    if(!got) begin
        $display("FAIL: %0s: no vector", what);
        errors = errors + 1;
    end else if(v !== want) begin
        $display("FAIL: %0s: vector %o, wanted %o", what, v, want);
        errors = errors + 1;
    end else
        $display("ok:   %0s: vector %o", what, v);
end
endtask

task wait_virq(input [511:0] what);
integer n;
begin
    for(n = 0; n < 100000 && !virq; n = n + 1) @(posedge clkp);
    if(!virq) begin $display("FAIL: %0s: no interrupt request", what); errors = errors + 1; end
end
endtask

reg [15:0] w;
integer n2;
initial begin
    #2000 init = 0;
    #10000;

    // channel 0 and 1 receive interrupts on, as the ROM's channel driver leaves them
    ppu_write(17'o177066, 16'o3);

    // 1. the timer: reload 3, run, interrupt enabled; it overflows in a few us
    ppu_write(17'o177712, 16'd3);
    ppu_write(17'o177710, 16'o101);
    wait_virq("timer");
    fetch(16'o304, "timer interrupt");
    // the handler has not read 177714 yet: flag up, request disabled
    if(virq_xm2) begin $display("FAIL: timer still requesting after its vector"); errors = errors + 1; end

    // 2. the CPU sends a byte down channel 0 meanwhile
    cpu_writeb(17'o177566, 8'o101);
    wait_virq("channel 0 byte");
    fetch(16'o320, "channel 0 with the timer flag still up");
    ppu_read(17'o177060, w);              // the channel handler takes the byte
    if(w[7:0] !== 8'o101) begin $display("FAIL: channel 0 byte %o", w); errors = errors + 1; end

    // the next overflow is a new request even though nobody has read
    // 177714 - MKLAD's handler never does, and got one tick only until
    // 3 Sep 2026
    wait_virq("timer, second tick, counter unread");
    fetch(16'o304, "timer, second tick, counter unread");

    // the timer handler finally reads the counter, which clears the flag
    ppu_read(17'o177714, w);
    ppu_write(17'o177710, 16'o0);
    #2000;
    if(virq) begin $display("FAIL: a request left over after both handlers"); errors = errors + 1; end

    // 3. a key, then a channel-1 byte with the key unread
    ppu_write(17'o177700, 16'o100);
    but = 8'o072;
    wait_virq("key");
    fetch(16'o300, "key interrupt");
    cpu_writeb(17'o176666, 8'o102);
    wait_virq("channel 1 byte");
    fetch(16'o330, "channel 1 with the key unread");
    ppu_read(17'o177702, w);
    if(w[7:0] !== 8'o072) begin $display("FAIL: key %o", w); errors = errors + 1; end
    ppu_read(17'o177062, w);
    if(w[7:0] !== 8'o102) begin $display("FAIL: channel 1 byte %o", w); errors = errors + 1; end
    #2000;
    if(virq) begin $display("FAIL: a request left over at the end"); errors = errors + 1; end

    // 4. two requests at one fetch: a channel-2 byte (340) waiting and the
    // timer overflowing, so that both chips have an enabled request when
    // the strobe rises.  xm2-01 answers 304 and its request drops one
    // clock later; the chain strobe used to be that request inverted, so
    // vp1_120 saw a fresh rising edge in the middle of the same fetch,
    // answered 340 to nobody and cleared its enable - the channel-2
    // interrupt was lost with the byte unread, the PPU never took it and
    // the CPU waited on the ready bit forever (MKLAD, 3 Sep 2026: part
    // of a tile row, then silence).  The second fetch must still see 340.
    ppu_write(17'o177066, 16'o7);
    cpu_writeb(17'o176676, 8'o103);
    wait_virq("channel 2 byte");
    ppu_write(17'o177712, 16'd3);
    ppu_write(17'o177710, 16'o101);
    wait_virq("timer with channel 2 pending");
    for(n2 = 0; n2 < 100000 && !virq_xm2; n2 = n2 + 1) @(posedge clkp);
    if(!virq_xm2) begin $display("FAIL: timer never requested"); errors = errors + 1; end
    fetch(16'o304, "timer, with a channel-2 byte pending");
    ppu_write(17'o177710, 16'o0);
    ppu_read(17'o177714, w);
    if(!virq_vp) begin $display("FAIL: the channel-2 request is gone - its enable was cleared by the timer's fetch"); errors = errors + 1; end
    wait_virq("channel 2 byte still pending");
    fetch(16'o340, "channel 2 after the timer");
    ppu_read(17'o177064, w);
    if(w[7:0] !== 8'o103) begin $display("FAIL: channel 2 byte %o", w); errors = errors + 1; end
    #2000;
    if(virq) begin $display("FAIL: a request left over after the pair"); errors = errors + 1; end

    // 5. the CPU side of the same chip: a channel-0 byte from the PPU with
    // the CPU's receive interrupt on, fetched by the CPU; the strobe on to
    // vp65 stays low throughout
    cpu_writeb(17'o177560, 8'o100);
    ppu_write(17'o177070, 16'o104);
    for(n2 = 0; n2 < 1000 && !cvirq; n2 = n2 + 1) @(posedge clk25);
    if(!cvirq) begin $display("FAIL: no CPU request for the channel-0 byte"); errors = errors + 1; end
    cpu_fetch(16'o60, "CPU: channel 0 byte from the PPU");
    if(cvirq) begin $display("FAIL: CPU request still up after its vector"); errors = errors + 1; end
    // and with nothing pending the strobe goes straight through to vp65
    @(posedge clk25); cwbi <= 1;
    repeat(4) @(posedge clk25);
    if(!cwbi_stb_chain) begin $display("FAIL: an idle vp1_120 does not pass the CPU's strobe on to vp65"); errors = errors + 1; end
    else $display("ok:   CPU: idle chip passes the strobe on to vp65");
    cwbi <= 0; repeat(4) @(posedge clk25);

    if(errors) $display("tb_virq: %0d FAILED", errors);
    else       $display("tb_virq: PASS");
    $finish;
end
endmodule
