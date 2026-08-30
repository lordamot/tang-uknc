//========================================================================
// Top-level testbench: the whole machine, with the SDRAM modelled and a
// minimal stand-in for the BL616.
//========================================================================
// Plusargs:
//   +VCD          dump sim/out/tb_top.vcd (large - a frame is ~1 Mcycle)
//   +VIDEO_PPM    write each decoded frame as a .ppm
//   +RUN_MS=<n>   how long to run, in simulated milliseconds (default 40)
//   +NOFASTBOOT   do not shortcut the 0.34 s power-on reset counter
//   +PPUTRACE     every acked PPU wishbone cycle - the I/O window
//   +RAMTRACE     every PPU SDRAM access - where the code actually is
//   +TRACE_MS=<n> hold both traces off until n ms, to look at the machine
//                 somewhere other than at boot without a gigabyte of log
//   +SPITRACE     every byte the MCU stand-in gets into sysctrl
//   +AUDIODBG     the audio mix and the two FIFOs, every 50 us
//   +AUDIOTEST    force two different constants onto the AY's panned
//                 outputs, so the I2S monitor can prove the path is stereo
//   +PPM_MAX=<n>  cap how many .ppm frames are written (default 4)
//   +PPM_FROM=<n> skip the frames before n ms
//   +NOMEMCHECK   turn off the read-after-write check on both SDRAM ports
//   +HDMIDBG      print every data island packet the decoder sees
//
// Both processors fetch code over their SDRAM port and use the wishbone
// only for I/O, so +PPUTRACE shows what the PPU touches and +RAMTRACE
// shows where it is executing.  The memory-op counts printed at the end
// are the cheap version of the same question: a core with zero of them
// never ran.
//
// Two things this testbench has to do that are worth knowing about:
//
//  * top.v holds the MisterNano blocks in reset until count_rst[23] sets,
//    which is 2^23 cycles of clk_25 - about 340 ms.  Simulating that is
//    tens of millions of edges before anything happens at all, so by
//    default the counter is forced near its terminal value.  Pass
//    +NOFASTBOOT to sit through it honestly.
//
//  * sysctrl.v does not give system_reset a reset value, so in simulation
//    it is X, and pp_rst - the PPU's reset - is X with it.  On hardware
//    the flop powers up at zero and the machine runs.  In simulation
//    nothing runs until an MCU sets it, which is what the SPI master
//    below does.  That is not a workaround, it is what the real firmware
//    does too: main.c sends 'R' before anything else.
//========================================================================
`timescale 1ns / 1ps

module tb_top;

    //--------------------------------------------------------------------
    // Clock and board inputs
    //--------------------------------------------------------------------
    reg clk27 = 1'b0;
    always #18.518 clk27 = ~clk27;      // 27 MHz

    // top.v: n_all_rst = init & ~buts[0], so buts[0] HIGH holds the
    // whole MisterNano side in power-on reset for ever.  Low is the
    // running state, whatever the silkscreen says about the buttons.
    reg  [1:0] buts = 2'b00;
    wire [5:0] leds;

    wire uart_tx;
    reg  uart_rx = 1'b1;

    wire sdclk;
    wire sdcmd, sddat0, sddat1, sddat2, sddat3;
    pullup (sdcmd); pullup (sddat0); pullup (sddat1);
    pullup (sddat2); pullup (sddat3);

    wire       O_tmds_clk_p, O_tmds_clk_n;
    wire [2:0] O_tmds_data_p, O_tmds_data_n;

    wire HP_BCK, HP_WS, HP_DIN, PA_EN;

    wire        O_sdram_clk, O_sdram_cke, O_sdram_cs_n;
    wire        O_sdram_cas_n, O_sdram_ras_n, O_sdram_wen_n;
    wire [3:0]  O_sdram_dqm;
    wire [10:0] O_sdram_addr;
    wire [1:0]  O_sdram_ba;
    wire [31:0] IO_sdram_dq;

    reg  spi_io_ss  = 1'b1;
    reg  spi_io_clk = 1'b0;
    reg  spi_io_din = 1'b0;

    // This testbench plays an external BL616 / M0S Dock, so it hangs off
    // the m0s bus and not off the on-board BL616's pins.  Only the three
    // input bits are driven here; m0s[0] and m0s[4] are the FPGA's own
    // outputs.  Pulling m0s[2] low is also what makes top.v switch its
    // inputs away from the internal BL616, so the first transaction may be
    // lost - the retry loop below is the same one main.c runs, and covers
    // it exactly as it does on hardware.
    wire [4:0] m0s;
    assign m0s[1] = spi_io_din ;
    assign m0s[2] = spi_io_ss  ;
    assign m0s[3] = spi_io_clk ;
    wire spi_io_dout = m0s[0];
    wire mcu_intn    = m0s[4];

    // The Tang's own BL616 is not present in simulation; its chip select
    // is held idle so it never wins the mux.
    wire spi_dir, spi_irqn;

    //--------------------------------------------------------------------
    // The design
    //--------------------------------------------------------------------
    top uut (
        .clk27(clk27), .buts(buts), .leds(leds),
        .uart_tx(uart_tx), .uart_rx(uart_rx),
        .sdclk(sdclk), .sdcmd(sdcmd),
        .sddat0(sddat0), .sddat1(sddat1), .sddat2(sddat2), .sddat3(sddat3),
        .O_tmds_clk_p(O_tmds_clk_p),   .O_tmds_clk_n(O_tmds_clk_n),
        .O_tmds_data_p(O_tmds_data_p), .O_tmds_data_n(O_tmds_data_n),
        .HP_BCK(HP_BCK), .HP_WS(HP_WS), .HP_DIN(HP_DIN), .PA_EN(PA_EN),
        .O_sdram_clk(O_sdram_clk),     .O_sdram_cke(O_sdram_cke),
        .O_sdram_cs_n(O_sdram_cs_n),   .O_sdram_cas_n(O_sdram_cas_n),
        .O_sdram_ras_n(O_sdram_ras_n), .O_sdram_wen_n(O_sdram_wen_n),
        .O_sdram_dqm(O_sdram_dqm),     .O_sdram_addr(O_sdram_addr),
        .O_sdram_ba(O_sdram_ba),       .IO_sdram_dq(IO_sdram_dq),
        .m0s(m0s),
        .spi_csn(1'b1), .spi_sclk(1'b0), .spi_dat(1'b0),
        .spi_dir(spi_dir), .spi_irqn(spi_irqn)
    );

    //--------------------------------------------------------------------
    // Memory.  top.v only wires the low 16 bits of the bus.
    //--------------------------------------------------------------------
    sdram_model ram (
        .clk(O_sdram_clk), .cke(O_sdram_cke),
        .cs_n(O_sdram_cs_n), .ras_n(O_sdram_ras_n),
        .cas_n(O_sdram_cas_n), .we_n(O_sdram_wen_n),
        .ba(O_sdram_ba), .a(O_sdram_addr),
        .dqm_l(O_sdram_dqm[0]), .dqm_h(O_sdram_dqm[1]),
        .dq(IO_sdram_dq[15:0])
    );

    //--------------------------------------------------------------------
    // A minimal BL616: SPI master, mode 1, MSB first.
    //--------------------------------------------------------------------
    localparam SPI_HALF = 25;           // ns; 20 MHz like the real firmware
    // Hold time on MOSI after the falling edge.  mcu_spi.v samples din on
    // `always @(negedge spi_io_clk)`, and without this the next bit was
    // assigned at the same timestamp as that edge - a delta-cycle race the
    // slave lost every time, so every byte arrived shifted one bit left.
    // 0x04 became 0x08 and "R" (0x52) became 0xA4, which meant no config
    // value ever matched and the machine ran only because Verilator
    // zero-initialises system_reset.  Reads were unaffected, and the
    // status command is 0x00, which shifts to 0x00 - so it all looked fine.
    localparam SPI_HOLD = 5;

    reg [7:0] spi_rx;

    task spi_byte(input [7:0] tx);
        integer b;
        begin
            for (b = 7; b >= 0; b = b - 1) begin
                spi_io_din  = tx[b];
                #SPI_HALF spi_io_clk = 1'b1;    // master sets up on rising
                #SPI_HALF spi_io_clk = 1'b0;    // slave samples on falling
                #SPI_HOLD;                      // hold din past that edge
                spi_rx = {spi_rx[6:0], spi_io_dout};
            end
            // An inter-byte gap is NOT optional.  sysctrl.v updates
            // data_out in the 25 MHz domain, one strobe behind the byte
            // that asked for it; with bytes sent back to back the reply's
            // top bits are shifted out before that update lands and come
            // back stale.  The real firmware gets this gap for free - it
            // is a function call per byte on the BL616 - so the hardware
            // never shows it.  Sending faster than this breaks the reply.
            #(SPI_HALF * 20);
        end
    endtask

    task spi_begin; begin spi_io_ss = 1'b0; #SPI_HALF; end endtask
    task spi_end;   begin #SPI_HALF spi_io_ss = 1'b1; #(SPI_HALF*4); end endtask

    // SYS command 4: set a configuration value
    task sys_set_val(input [7:0] id, input [7:0] val);
        begin
            spi_begin;
            spi_byte(8'd0);     // target SYS
            spi_byte(8'd4);     // command "set value"
            spi_byte(id);
            spi_byte(val);
            spi_end;
        end
    endtask

    reg [7:0] st0, st1, st2, st3;

    // Exactly what sys_status_is_valid() in mnano/sysctrl.c does.  Note
    // the dummy byte after the command: sysctrl.v registers data_out, so
    // the first byte the master clocks back is the value from before the
    // command took effect.  Drop it, or the whole reply looks shifted.
    task sys_status;
        begin
            spi_begin;
            spi_byte(8'd0);     // target SYS
            spi_byte(8'd0);     // command "status"
            spi_byte(8'h00);                    // dummy
            spi_byte(8'h00);  st0 = spi_rx;     // expect 5c
            spi_byte(8'h00);  st1 = spi_rx;     // expect 42
            spi_byte(8'h00);  st2 = spi_rx;     // core id
            spi_byte(8'h00);  st3 = spi_rx;     // coldboot status
            spi_end;
        end
    endtask

    //--------------------------------------------------------------------
    // Run
    //--------------------------------------------------------------------
    integer run_ms;
    integer tries;
    reg     fastboot;

    initial begin
        if (!$value$plusargs("RUN_MS=%d", run_ms)) run_ms = 40;
        fastboot = !$test$plusargs("NOFASTBOOT");

        if ($test$plusargs("VCD")) begin
            $dumpfile("sim/out/tb_top.vcd");
            $dumpvars(0, tb_top);
        end

        // Skip the 340 ms power-on reset counter unless told not to.
        if (fastboot) begin
            #200000;                                 // 200 us, PLL settles
            force uut.count_rst = 24'h7FFFF0;
            #20000;
            release uut.count_rst;
            $display("[tb] %0t fastboot: count_rst forced", $time);
        end

        // Wait for the core to answer, the way main.c does.
        tries = 0;
        st0 = 0; st1 = 0; st2 = 0;
        while (tries < 200 && !(st0 == 8'h5c && st1 == 8'h42)) begin
            #100000;
            sys_status;
            tries = tries + 1;
        end

        if (st0 == 8'h5c && st1 == 8'h42)
            $display("[tb] %0t FPGA ready, core id 0x%02x (expect 05 = UKNC)",
                     $time, st2);
        else
            $display("[tb] %0t FPGA never answered (got %02x %02x %02x)",
                     $time, st0, st1, st2);

        sys_set_val("R", 8'd3);     // cold boot, as main.c does
        #50000;
        sys_set_val("A", 8'd1);     // volume 33%
        sys_set_val("P", 8'd0);     // no write protection
        sys_set_val("R", 8'd0);     // and run
        $display("[tb] %0t released reset", $time);

        // +AUDIOTEST: put two different constants on the AY's panned
        // outputs and let the I2S monitor below say whether they come out
        // of the pin as two different words.  Nothing in the machine plays
        // anything on its own during a short run, so without this the
        // audio path reports silence and proves nothing either way.
        if ($test$plusargs("AUDIOTEST")) begin
            force uut.left_channel  = 11'o1234;
            force uut.right_channel = 11'o0765;
            $display("[tb] %0t audio test: L=%o R=%o forced onto the AY mix",
                     $time, 11'o1234, 11'o0765);
        end

        #(run_ms * 1000000);
        $display("[tb] %0t done: %0d video frames, leds=%b",
                 $time, rx_frames, leds);
        // Both processors fetch code over their SDRAM port, not the
        // wishbone - the wishbone is the I/O window only - so these two
        // counts, not the bus trace, are what says whether a core is
        // executing at all.
        $display("[tb] memory ops: ppu %0d, cpu %0d", ppu_ops, cpu_ops);
        if (!$test$plusargs("NOMEMCHECK"))
            $display("[tb] read-after-write: %0d checked, %0d wrong",
                     mem_checks, mem_errs);
        $display("[tb] i2s: %0d frames, %0d with sound, %0d with L != R",
                 i2s_frames, i2s_nonzero, i2s_stereo);
        $display("[tb] hdmi: %0d packets, %0d ecc errors  (acr %0d, avi %0d, ai %0d, audio %0d, null %0d)",
                 rx_packets, rx_ecc_errs, rx_acr, rx_avi, rx_ai, rx_audio,
                 rx_null);
        $display("[tb] hdmi audio: %0d samples, %0d with sound, %0d with L != R, overflow=%b",
                 rx_audio, rx_aud_nonzero, rx_aud_stereo, uut.hdmi_audio_ovf);
        $display("[tb] hdmi audio subframes: %0d with bad parity, %0d flagged not-PCM",
                 rx_aud_badpar, rx_aud_invalid);
        $finish;
    end

    //--------------------------------------------------------------------
    // Watch the interesting lines
    //--------------------------------------------------------------------
    initial begin
        @(negedge uut.cpu_vm_dclo_i);
        $display("[tb] %0t CPU DCLO released by the PPU", $time);
    end

    initial begin
        @(negedge uut.cpu_vm_aclo_i);
        $display("[tb] %0t CPU ACLO released", $time);
    end

    // First instruction fetch on each bus - proof the cores are alive.
    reg cpu_seen = 1'b0, ppu_seen = 1'b0;
    always @(posedge uut.cpuclk_p)
        if (!cpu_seen && uut.cpu_wbm_stb_o) begin
            cpu_seen <= 1'b1;
            $display("[tb] %0t CPU first bus cycle, addr %o",
                     $time, uut.cpu_wbm_adr_o);
        end
    always @(posedge uut.ppuclk_p)
        if (!ppu_seen && uut.ppu_wbm_stb_o) begin
            ppu_seen <= 1'b1;
            $display("[tb] %0t PPU first bus cycle, addr %o",
                     $time, uut.ppu_wbm_adr_o);
        end

    // +DQCHECK: the SDRAM data bus is a real inout, driven by sdram2's
    // `assign SDRAM_DQr = SDRAM_DQ` on one side and by the model on the
    // other.  This says whether what the model drives is what the
    // controller sees - i.e. whether the tri-state resolution works at
    // all - which is not a thing to take on trust in Verilator.
    always @(posedge O_sdram_clk)
        if ($test$plusargs("DQCHECK") && ram.dq_oe && ram.dq_out !== 16'h0000)
            $display("[dq] %0t model drives %04x, sdram2 sees %04x %s",
                     $time, ram.dq_out, uut.ram1.SDRAM_DQr,
                     (ram.dq_out === uut.ram1.SDRAM_DQr) ? "" : "<-- LOST");

    // SDRAM-port traffic, counted on the falling edge of the ack so a
    // held-low ack is not counted twice.
    integer ppu_ops = 0, cpu_ops = 0;
    always @(posedge uut.askn_ppu_i) ppu_ops = ppu_ops + 1;
    always @(posedge uut.askn_cpu_i) cpu_ops = cpu_ops + 1;

    //--------------------------------------------------------------------
    // I2S monitor
    //--------------------------------------------------------------------
    // Decodes the audio the design actually emits, which is the only way
    // to tell a stereo path from a mono one without a pair of headphones.
    // HP_WS low is the left slot; data is MSB first on HP_BCK, so the
    // shifter holds a finished word at each edge of HP_WS.
    reg [15:0] i2s_sr = 16'd0;
    reg [15:0] i2s_l  = 16'd0, i2s_r = 16'd0;
    reg        ws_d   = 1'b0;
    integer    i2s_frames = 0, i2s_stereo = 0, i2s_nonzero = 0;

    // +SPITRACE: every byte the MCU stand-in gets into sysctrl, with the
    // command and id it lands against.  This is what caught the master's
    // bit-alignment race described above - the bytes were arriving as
    // 08/a4 for 04/52 - so it is worth keeping pointed at the wall.
    always @(posedge uut.mist_clk)
        if ($test$plusargs("SPITRACE") && uut.mcu_sys_strobe)
            $display("[spi] %0t sys byte %02x start=%b state=%0d cmd=%02x id=%02x",
                     $time, uut.mcu_dout, uut.mcu_start,
                     uut.sctl1.state, uut.sctl1.command, uut.sctl1.id);

    // +AUDIODBG: the audio path, from the volume mix through the two
    // FIFOs, sampled every 50 us once the machine is configured.
    initial if ($test$plusargs("AUDIODBG")) begin
        #450000;   // just after the reset release at 391 us
        forever begin
            #50000;
            $display("[aud] %0t vol=%b sys_rst=%b l=%h r=%h fifo_l=%h fifo_r=%h emptyl=%b",
                     $time, uut.system_volume, uut.sys_rst,
                     uut.volume_data_l, uut.volume_data_r,
                     uut.data_aud_l, uut.data_aud_r, uut.Empty_aud_l);
        end
    end

    always @(posedge HP_BCK) begin
        i2s_sr <= {i2s_sr[14:0], HP_DIN};
        ws_d   <= HP_WS;
        if (HP_WS && !ws_d) i2s_l <= i2s_sr;        // left slot just ended
        if (!HP_WS && ws_d) begin                   // right slot just ended
            i2s_r      <= i2s_sr;
            i2s_frames  = i2s_frames + 1;
            if (i2s_l !== 16'd0 || i2s_sr !== 16'd0)
                i2s_nonzero = i2s_nonzero + 1;
            if (i2s_l !== i2s_sr) i2s_stereo = i2s_stereo + 1;
        end
    end

    //--------------------------------------------------------------------
    // Read-after-write check on both SDRAM ports.
    //--------------------------------------------------------------------
    // On by default, because the one bug this testbench has actually
    // found was memory quietly returning zero, and that cost a day.  A
    // shadow copy of every word either processor writes, compared against
    // what it reads back: silence means the memory path is honest.
    //
    // The port is 32 bits with a four-byte mask where a SET bit MASKS the
    // byte, so mask 1100 is a write of the low half and 0011 of the high
    // one.  Only the half the mask selects is shadowed.  Video reads are
    // not covered - they never go through these ports.
    // Two shadows, keyed by BANK and shared between the ports - which is
    // what sdram2.v actually does.  Every processor access fetches from
    // both banks in the same slot: bank 0 is the PPU's own RAM and bank 1
    // is the CPU's, and the four-byte mask picks which half of the 32-bit
    // port word means anything.  A set mask bit masks the byte, so mask
    // 1100 is the low half and bank 0, and 0011 is the high half and bank
    // 1.  Bank 1 is reachable from both ports - it is how the PPU loads
    // the CPU's memory, and it is where the video reads the screen from -
    // so keying these by port instead of by bank reports cross-writes as
    // faults.  That was the first two attempts.
    reg [15:0] shadow_b0  [0:65535];
    reg        shadowed_b0[0:65535];
    reg [15:0] shadow_b1  [0:65535];
    reg        shadowed_b1[0:65535];
    integer    mem_errs = 0, mem_checks = 0;
    integer    si;
    initial begin
        for (si = 0; si < 65536; si = si + 1) begin
            shadowed_b0[si] = 1'b0;
            shadowed_b1[si] = 1'b0;
        end
    end

    task mem_watch(input is_cpu, input [15:0] adr, input wr, input [3:0] msk,
                   input [31:0] dat);
        reg [15:0] val;
        reg [15:0] was;
        reg        known;
        reg        bank1;
        begin
            if (msk == 4'b1100 || msk == 4'b0011) begin
                bank1 = (msk == 4'b0011);
                val   = bank1 ? dat[31:16]      : dat[15:0];
                was   = bank1 ? shadow_b1[adr]  : shadow_b0[adr];
                known = bank1 ? shadowed_b1[adr]: shadowed_b0[adr];
                if (wr) begin
                    if (bank1) begin
                        shadow_b1[adr]   = val;
                        shadowed_b1[adr] = 1'b1;
                    end else begin
                        shadow_b0[adr]   = val;
                        shadowed_b0[adr] = 1'b1;
                    end
                end else if (known) begin
                    mem_checks = mem_checks + 1;
                    if (val !== was) begin
                        mem_errs = mem_errs + 1;
                        if (mem_errs <= 10)
                            $display("[mem] %0t %0s bank%0d read %o at %o, wrote %o",
                                     $time, is_cpu ? "cpu" : "ppu", bank1,
                                     val, adr, was);
                    end
                end
            end
        end
    endtask

    always @(posedge uut.askn_ppu_i)
        if (!$test$plusargs("NOMEMCHECK"))
            mem_watch(1'b0, uut.addr_ppu_o, uut.wrte_ppu_o, uut.mask_ppu_o,
                      uut.wrte_ppu_o ? uut.data_ppu_o : uut.data_ppu_i);
    always @(posedge uut.askn_cpu_i)
        if (!$test$plusargs("NOMEMCHECK"))
            mem_watch(1'b1, uut.addr_cpu_o, uut.wrte_cpu_o, uut.mask_cpu_o,
                      uut.wrte_cpu_o ? uut.data_cpu_o : uut.data_cpu_i);

    // +RAMTRACE: every PPU memory access.  Where the wishbone trace shows
    // I/O, this shows execution - `sort | uniq -c` over it says whether
    // the processor is looping in ROM or wandering through zeros.
    // +TRACE_MS=<n> holds both traces off until n ms of simulated time,
    // which is how you look at the machine somewhere other than at boot
    // without writing a gigabyte of log to get there.
    integer trace_ms;
    reg     tracing = 1'b0;
    initial begin
        if (!$value$plusargs("TRACE_MS=%d", trace_ms)) trace_ms = 0;
        if (trace_ms > 0) #(trace_ms * 1000000);
        tracing = 1'b1;
    end

    always @(posedge uut.askn_ppu_i)
        if ($test$plusargs("RAMTRACE") && tracing)
            // The PPU port is 32 bits wide with a four-byte mask, but
            // the SDRAM behind it is 16: mask 0011 is the low half and
            // 1100 the high one, so print both halves and let the mask
            // say which one meant anything.
            $display("[ram] %0t %o %s %o.%o mask %b", $time, uut.addr_ppu_o,
                     uut.wrte_ppu_o ? "wr" : "rd",
                     uut.wrte_ppu_o ? uut.data_ppu_o[31:16]
                                    : uut.data_ppu_i[31:16],
                     uut.wrte_ppu_o ? uut.data_ppu_o[15:0]
                                    : uut.data_ppu_i[15:0],
                     uut.mask_ppu_o);

    // R177716 in xm2-01.v is what starts the CPU: it resets to 16'o40,
    // and bit 5 is the CPU's DCLO.  Until the PPU clears that bit the
    // second processor is held in power-on reset, so every "the CPU never
    // ran" question begins here.  Bit 4 is HALT, bit 15 inverted is ACLO.
    reg [15:0] r716_last = 16'o40;
    always @(posedge uut.ppuclk_p)
        if (uut.dd1.R177716 !== r716_last) begin
            $display("[tb] %0t R177716 %o -> %o  (dclo=%b halt=%b aclo=%b)",
                     $time, r716_last, uut.dd1.R177716,
                     uut.dd1.R177716[5], uut.dd1.R177716[4],
                     ~uut.dd1.R177716[15]);
            r716_last <= uut.dd1.R177716;
        end

    // +PPUTRACE: every PPU bus cycle, which is the only way to see where
    // the peripheral processor has got stuck.  Enormously verbose - a
    // millisecond is thousands of lines - so keep RUN_MS small with it.
    always @(posedge uut.ppuclk_p)
        if ($test$plusargs("PPUTRACE") && tracing && uut.ppu_wbm_stb_o &&
            uut.ppu_wbm_ack_i)
            $display("[ppu] %0t %o %s %o", $time, uut.ppu_wbm_adr_o,
                     uut.ppu_wbm_wre_o ? "wr" : "rd",
                     uut.ppu_wbm_wre_o ? uut.ppu_wbm_dat_o
                                      : uut.ppu_wbm_dat_i);

    //--------------------------------------------------------------------
    // The HDMI receiver.
    //
    // hdmi_serdes is stubbed, so what leaves the design in simulation is
    // three ten-bit TMDS words a pixel clock.  This decodes them the way
    // a sink does - follow the preambles and guard bands into a video or
    // data island period, and decode what is inside - which is the only
    // check available on hdmi_tx.v short of a television.
    //
    // It does two jobs: it rebuilds the picture, so `make frames` still
    // works and now proves the encoder round-trips; and it pulls the data
    // island packets apart, checks their ECC and counts them by type, so
    // "the audio packets are going out" is a measurement.
    //--------------------------------------------------------------------
    wire        px_clk = uut.clkpix;
    wire [9:0]  t0 = uut.tmds_ch0;
    wire [9:0]  t1 = uut.tmds_ch1;
    wire [9:0]  t2 = uut.tmds_ch2;

    localparam [9:0] CTL00 = 10'b1101010100, CTL01 = 10'b0010101011,
                     CTL10 = 10'b0101010100, CTL11 = 10'b1010101011;
    localparam [9:0] VGB_02 = 10'b1011001100, VGB_1 = 10'b0100110011;

    function is_ctl(input [9:0] w);
        is_ctl = (w == CTL00) || (w == CTL01) || (w == CTL10) || (w == CTL11);
    endfunction

    function [1:0] ctl_of(input [9:0] w);
        ctl_of = (w == CTL00) ? 2'b00 : (w == CTL01) ? 2'b01 :
                 (w == CTL10) ? 2'b10 : 2'b11;
    endfunction

    // The inverse of the encoder in src/hdmi/tmds_channel.v.
    function [7:0] tmds_dec(input [9:0] w);
        reg [7:0] qm, d;
        integer   i;
        begin
            qm = w[9] ? ~w[7:0] : w[7:0];
            d[0] = qm[0];
            for (i = 1; i < 8; i = i + 1)
                d[i] = w[8] ? (qm[i] ^ qm[i-1]) : (qm[i] ~^ qm[i-1]);
            tmds_dec = d;
        end
    endfunction

    function [4:0] terc4_dec(input [9:0] w);   // bit 4 set = not a TERC4 word
        case (w)
            10'b1010011100: terc4_dec = 5'h00;
            10'b1001100011: terc4_dec = 5'h01;
            10'b1011100100: terc4_dec = 5'h02;
            10'b1011100010: terc4_dec = 5'h03;
            10'b0101110001: terc4_dec = 5'h04;
            10'b0100011110: terc4_dec = 5'h05;
            10'b0110001110: terc4_dec = 5'h06;
            10'b0100111100: terc4_dec = 5'h07;
            10'b1011001100: terc4_dec = 5'h08;
            10'b0100111001: terc4_dec = 5'h09;
            10'b0110011100: terc4_dec = 5'h0a;
            10'b1011000110: terc4_dec = 5'h0b;
            10'b1010001110: terc4_dec = 5'h0c;
            10'b1001110001: terc4_dec = 5'h0d;
            10'b0101100011: terc4_dec = 5'h0e;
            10'b1011000011: terc4_dec = 5'h0f;
            default:        terc4_dec = 5'h10;
        endcase
    endfunction

    function [7:0] ecc_step(input [7:0] ecc, input b);
        ecc_step = (ecc >> 1) ^ ((ecc[0] ^ b) ? 8'b10000011 : 8'd0);
    endfunction

    localparam RX_CTL = 0, RX_VGB = 1, RX_VID = 2,
               RX_DGB = 3, RX_DI  = 4, RX_DGBT = 5;

    integer rx_state   = RX_CTL;
    integer rx_gb      = 0;      // guard band clocks seen
    integer rx_frames  = 0;
    integer rx_packets = 0, rx_ecc_errs = 0;
    integer rx_acr = 0, rx_avi = 0, rx_ai = 0, rx_audio = 0, rx_null = 0;
    integer rx_aud_nonzero = 0, rx_aud_stereo = 0;
    integer rx_aud_badpar = 0, rx_aud_invalid = 0;
    integer rx_bad_gb = 0, rx_bad_terc4 = 0;

    reg        rx_vs = 1'b0, rx_vs_d = 1'b0;
    integer    rx_x = 0, rx_y = 0, rx_w = 0;

    parameter MAXW = 1440;
    parameter MAXH = 800;
    reg [23:0] fb [0:MAXW*MAXH-1];

    // Packet under construction
    reg [4:0]  pk_cnt = 5'd0;
    reg [23:0] pk_hdr;
    reg [55:0] pk_sub [0:3];
    reg [7:0]  pk_par [0:4];
    reg [7:0]  pk_ecc [0:4];

    integer    gi;

    // .ppm writing, kept from the old dvi_tx model.
    integer fh, fi, fj, fh_h;
    integer written = 0, ppm_max;
    reg     want_ppm = 0;
    reg [255:0] fname;
    integer ppm_from;
    reg     ppm_armed = 1'b0;
    initial begin
        want_ppm = $test$plusargs("VIDEO_PPM");
        if (!$value$plusargs("PPM_MAX=%d", ppm_max)) ppm_max = 4;
        if (!$value$plusargs("PPM_FROM=%d", ppm_from)) ppm_from = 0;
        if (ppm_from > 0) #(ppm_from * 1000000);
        ppm_armed = 1'b1;
    end

    task write_ppm;
        begin
            written = written + 1;
            fh_h = (rx_y > MAXH) ? MAXH : rx_y;
            $sformat(fname, "sim/out/frame_%04d.ppm", rx_frames);
            fh = $fopen(fname, "wb");
            if (fh) begin
                $fwrite(fh, "P6\n%0d %0d\n255\n", rx_w, fh_h);
                for (fj = 0; fj < fh_h; fj = fj + 1)
                    for (fi = 0; fi < rx_w; fi = fi + 1)
                        $fwrite(fh, "%c%c%c",
                                fb[fj*MAXW+fi][23:16],
                                fb[fj*MAXW+fi][15:8],
                                fb[fj*MAXW+fi][7:0]);
                $fclose(fh);
                $display("[hdmi] %0t wrote %0s (%0dx%0d)",
                         $time, fname, rx_w, fh_h);
            end
        end
    endtask

    task finish_packet;
        reg [7:0] ptype;
        reg [23:0] l, r;
        reg [27:0] sf_l, sf_r;
        begin
            rx_packets = rx_packets + 1;
            for (gi = 0; gi < 5; gi = gi + 1)
                if (pk_par[gi] !== pk_ecc[gi]) rx_ecc_errs = rx_ecc_errs + 1;
            ptype = pk_hdr[7:0];
            case (ptype)
                8'h00: rx_null  = rx_null  + 1;
                8'h01: rx_acr   = rx_acr   + 1;
                8'h02: begin
                           // IEC 60958 subframes, 28 bits each: 24 sample
                           // bits then V, U, C, P.  Decoded here the way a
                           // sink decodes it and NOT the way hdmi_tx.v
                           // packs it - the two agreeing on a layout of
                           // their own is exactly how the right channel
                           // went out as noise while this said stereo.
                           rx_audio = rx_audio + 1;
                           sf_l = pk_sub[0][27: 0];
                           sf_r = pk_sub[0][55:28];
                           l = sf_l[23:0];
                           r = sf_r[23:0];
                           if (l !== 24'd0 || r !== 24'd0)
                               rx_aud_nonzero = rx_aud_nonzero + 1;
                           if (l !== r) rx_aud_stereo = rx_aud_stereo + 1;
                           // P makes each subframe even; V set means the
                           // sink is told the sample is not linear PCM.
                           if ((^sf_l) !== 1'b0 || (^sf_r) !== 1'b0)
                               rx_aud_badpar = rx_aud_badpar + 1;
                           if (sf_l[24] !== 1'b0 || sf_r[24] !== 1'b0)
                               rx_aud_invalid = rx_aud_invalid + 1;
                       end
                8'h82: rx_avi   = rx_avi   + 1;
                8'h84: rx_ai    = rx_ai    + 1;
                default: ;
            endcase
            if ($test$plusargs("HDMIDBG"))
                $display("[hdmi] %0t packet type %02x hdr %06x sub0 %014x",
                         $time, ptype, pk_hdr, pk_sub[0]);
        end
    endtask

    always @(posedge px_clk) begin : rx
        reg [1:0] c0, c1, c2;
        reg [4:0] n0, n1, n2;
        reg [7:0] dr, dg, db;
        c0 = ctl_of(t0); c1 = ctl_of(t1); c2 = ctl_of(t2);

        case (rx_state)
        RX_CTL: begin
            if (is_ctl(t0)) begin
                rx_vs_d = rx_vs;
                rx_vs   = c0[1];
                if (rx_vs && !rx_vs_d) begin      // a frame just ended
                    if (rx_frames > 0 && want_ppm && ppm_armed &&
                        written < ppm_max) write_ppm;
                    rx_frames = rx_frames + 1;
                    rx_x = 0; rx_y = 0;
                end
            end
            // A preamble is CTL0 on channel 1; channel 2 says which kind.
            if (is_ctl(t1) && c1 == 2'b01) begin
                if (is_ctl(t2) && c2 == 2'b01) rx_state = RX_DGB;
                else                           rx_state = RX_VGB;
                rx_gb = 0;
            end
        end

        // Two guard-band words, then the period itself.
        RX_VGB: begin
            if (is_ctl(t1) && ctl_of(t1) == 2'b01) begin
                // still in the preamble
            end else begin
                if (t0 !== VGB_02 || t1 !== VGB_1 || t2 !== VGB_02)
                    rx_bad_gb = rx_bad_gb + 1;
                rx_gb = rx_gb + 1;
                if (rx_gb == 2) begin rx_state = RX_VID; rx_x = 0; end
            end
        end

        RX_VID: begin
            if (is_ctl(t0)) begin                 // line over
                if (rx_x > rx_w) rx_w = rx_x;
                rx_x = 0;
                rx_y = rx_y + 1;
                rx_state = RX_CTL;
            end else begin
                db = tmds_dec(t0); dg = tmds_dec(t1); dr = tmds_dec(t2);
                if (rx_x < MAXW && rx_y < MAXH)
                    fb[rx_y*MAXW+rx_x] = {dr, dg, db};
                rx_x = rx_x + 1;
            end
        end

        RX_DGB: begin
            if (is_ctl(t1) && ctl_of(t1) == 2'b01 &&
                is_ctl(t2) && ctl_of(t2) == 2'b01) begin
                // still in the preamble
            end else begin
                if (t1 !== VGB_1 || t2 !== VGB_1) rx_bad_gb = rx_bad_gb + 1;
                rx_gb = rx_gb + 1;
                if (rx_gb == 2) begin
                    rx_state = RX_DI;
                    pk_cnt = 5'd0;
                    for (gi = 0; gi < 5; gi = gi + 1) pk_par[gi] = 8'd0;
                end
            end
        end

        RX_DI: begin
            n0 = terc4_dec(t0); n1 = terc4_dec(t1); n2 = terc4_dec(t2);
            if (n0[4] || n1[4] || n2[4]) begin
                // Not TERC4 any more: this is the trailing guard band.
                rx_gb = 0;
                rx_state = RX_DGBT;
            end else begin
                if (pk_cnt < 5'd24) pk_hdr[pk_cnt] = n0[2];
                for (gi = 0; gi < 4; gi = gi + 1) begin
                    pk_sub[gi][{pk_cnt, 1'b0}] = n1[gi];
                    pk_sub[gi][{pk_cnt, 1'b1}] = n2[gi];
                end
                // The parity bytes arrive in the last four clocks of each
                // block; everything before them feeds the check.
                if (pk_cnt >= 5'd28) begin
                    for (gi = 0; gi < 4; gi = gi + 1) begin
                        pk_ecc[gi][{pk_cnt[1:0], 1'b0}] = n1[gi];
                        pk_ecc[gi][{pk_cnt[1:0], 1'b1}] = n2[gi];
                    end
                end
                if (pk_cnt >= 5'd24) pk_ecc[4][pk_cnt[2:0]] = n0[2];
                if (pk_cnt < 5'd28) begin
                    for (gi = 0; gi < 4; gi = gi + 1) begin
                        pk_par[gi] = ecc_step(pk_par[gi], n1[gi]);
                        pk_par[gi] = ecc_step(pk_par[gi], n2[gi]);
                    end
                    if (pk_cnt < 5'd24)
                        pk_par[4] = ecc_step(pk_par[4], n0[2]);
                end
                if (pk_cnt == 5'd31) begin
                    finish_packet;
                    for (gi = 0; gi < 5; gi = gi + 1) pk_par[gi] = 8'd0;
                end
                pk_cnt = pk_cnt + 5'd1;
            end
        end

        RX_DGBT: begin
            rx_gb = rx_gb + 1;
            if (rx_gb == 2) rx_state = RX_CTL;
        end
        endcase
    end

endmodule
