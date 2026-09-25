// tb_mixer.v - mixer.v on its own (make mixer-test), Sep 2026.
//
// Checks what the mixer claims to model, against numbers worked out from
// the Aberrant module's schematic and from the filter coefficients, not
// against the RTL's own arithmetic:
//
//   - ABC panning: A alone reaches L at 33/48 of the peak and R not at all,
//     B reaches both at 15/48, C mirrors A; mono puts 8x the sum on both
//   - the DC blocker: a step comes through at full height and decays with
//     a time constant of 2^19 clocks (167 ms), and goes negative on the
//     way back down
//   - the low-pass: a sine at 4.87 kHz comes out 3 dB under its level at
//     500 Hz, at 10 kHz about 8 dB under, and Off is flat but for the
//     64-sample mean's 0.6 dB at 10 kHz
//   - the volume steps and mute, and saturation at full scale
//   - "old freaks": a 50 Hz sine comes out 12 dB up (the shelf's 6 and the
//     gain's 6), 5 kHz 6 dB up, and past half scale the limiter's quarter
//     slope; saturation both ways without a wrap
//   - the 64-sample mean: the output word changes only every 16 clocks
`timescale 1ns / 1ps
module tb_mixer;

reg clk = 1'b0;
always #159.5 clk = ~clk;                   // 3.1339 MHz, the PPU clock

reg  [9:0] a = 0, b = 0, c = 0;
reg        beep = 0;
reg  [7:0] cov = 0, lpt = 0;
reg        stereo = 1, lowpass = 0, oldf = 0;
reg  [1:0] volume = 2'd3;
wire [15:0] l, r;

mixer dut(.clk(clk), .ay_a(a), .ay_b(b), .ay_c(c), .beep(beep),
          .covox(cov), .lpt(lpt), .stereo(stereo), .lowpass(lowpass),
          .oldfreaks(oldf), .volume(volume), .out_l(l), .out_r(r));

integer errors = 0;
task check(input cond, input [8*72-1:0] what);
    if (!cond) begin $display("  FAIL: %0s", what); errors = errors + 1; end
endtask

function integer sl(input [15:0] v); sl = $signed(v); endfunction
function integer iabs(input integer v); iabs = v < 0 ? -v : v; endfunction

// wait n clocks
task clocks(input integer n); integer i; begin for (i = 0; i < n; i = i + 1) @(posedge clk); end endtask

// a step from silence, measured 200 clocks later (the mean and the
// pipeline have settled, the blocker has taken 0.04% off)
task step(input [9:0] sa, input [9:0] sb, input [9:0] sc,
          output integer ol, output integer or_);
    begin
        a = 0; b = 0; c = 0; clocks(3000000);   // let the blocker settle to zero (~6 time constants)
        a = sa; b = sb; c = sc; clocks(200);
        ol = sl(l); or_ = sl(r);
    end
endtask

// peak output amplitude of a sine of frequency f on A (mono, so both
// sides carry it), measured over the second half of `cyc` cycles
task sine_amp(input real f, input integer cyc, output integer amp);
    integer i, n, v, mx, mn;
    real ph;
    begin
        n = $rtoi(3.1339e6 / f * cyc);
        mx = -99999; mn = 99999;
        for (i = 0; i < n; i = i + 1) begin
            ph = 6.283185307 * f * i / 3.1339e6;
            a = $rtoi(382.0 + 380.0 * $sin(ph));
            @(posedge clk);
            if (i > n / 2) begin
                v = sl(l);
                if (v > mx) mx = v;
                if (v < mn) mn = v;
            end
        end
        amp = (mx - mn) / 2;
    end
endtask

integer ol, orr, x, y, t, k, amp500, amp4k, amp10k, prev, changes;
real db;
initial begin
    clocks(10);

    // ---- panning, low-pass off ----
    lowpass = 0; stereo = 1;
    step(765, 0, 0, ol, orr);
    $display("[mixer] ABC, A=765: L=%0d R=%0d (expect %0d, 0)", ol, orr, 33*765/2);
    check(iabs(ol - 33*765/2) < 30 && iabs(orr) < 10, "A alone must pan left at 33/48");
    step(0, 765, 0, ol, orr);
    $display("[mixer] ABC, B=765: L=%0d R=%0d (expect %0d both)", ol, orr, 15*765/2);
    check(iabs(ol - 15*765/2) < 30 && iabs(orr - 15*765/2) < 30, "B must reach both sides at 15/48");
    step(0, 0, 765, ol, orr);
    $display("[mixer] ABC, C=765: L=%0d R=%0d", ol, orr);
    check(iabs(orr - 33*765/2) < 30 && iabs(ol) < 10, "C alone must pan right at 33/48");
    stereo = 0;
    step(765, 0, 0, ol, orr);
    $display("[mixer] mono, A=765: L=%0d R=%0d (expect %0d both)", ol, orr, 765*8);
    check(iabs(ol - 6120) < 20 && iabs(orr - 6120) < 20, "mono must put 8x the sum on both sides");
    stereo = 1;

    // ---- the DC blocker: time constant and undershoot ----
    step(765, 765, 0, ol, orr);                  // 18360 on the left
    clocks(524288);                              // one time constant, 2^19 clocks
    x = sl(l);
    $display("[mixer] DC blocker: %0d after one time constant (expect 18360/e = %0d)", x, 18360 * 368 / 1000);
    check(iabs(x - 6754) < 250, "the blocker's time constant is not 2^19 clocks");
    a = 0; b = 0; clocks(200);
    y = sl(l);
    $display("[mixer] DC blocker: %0d on the step back to silence", y);
    check(y < -11000 && y > -12000, "the step down must come out negative, by the level that had built up");

    // ---- the low-pass ----
    a = 0; b = 0; c = 0;
    stereo = 0;
    a = 382; clocks(3000000);                    // the sines' own mean, settled through the blocker
    lowpass = 1;
    sine_amp(500.0,   8, amp500);
    sine_amp(4870.0, 40, amp4k);
    sine_amp(10000.0, 60, amp10k);
    db = 20.0 * $log10(1.0 * amp4k / amp500);
    $display("[mixer] low-pass on: 500 Hz %0d, 4.87 kHz %0d (%.1f dB), 10 kHz %0d (%.1f dB)",
             amp500, amp4k, db, amp10k, 20.0 * $log10(1.0 * amp10k / amp500));
    check(db < -2.5 && db > -3.5, "the pole must sit at 4.87 kHz");
    db = 20.0 * $log10(1.0 * amp10k / amp500);
    // one pole: -7.2 dB at 10 kHz; the 64-sample mean adds 0.6 there and
    // the peak search on a 196 kHz word about 0.1
    check(db < -7.3 && db > -8.6, "10 kHz must be about 8 dB down");
    lowpass = 0;
    sine_amp(500.0,   8, amp500);
    sine_amp(10000.0, 60, amp10k);
    db = 20.0 * $log10(1.0 * amp10k / amp500);
    $display("[mixer] low-pass off: 10 kHz %.1f dB against 500 Hz", db);
    check(db > -1.0, "Off must be flat to 10 kHz but for the mean's 0.6 dB");

    // ---- old freaks: the shelf and the gain, under the limiter's knee ----
    begin : oldfreaks_gain
        integer o50, o5k, f50, f5k;
        sine_amp(50.0,   6, o50);
        sine_amp(5000.0, 40, o5k);
        oldf = 1;
        sine_amp(50.0,   6, f50);
        sine_amp(5000.0, 40, f5k);
        oldf = 0;
        $display("[mixer] old freaks: 50 Hz %0d -> %0d (%.1f dB), 5 kHz %0d -> %0d (%.1f dB)",
                 o50, f50, 20.0 * $log10(1.0 * f50 / o50), o5k, f5k, 20.0 * $log10(1.0 * f5k / o5k));
        // the shelf gives +5.9 dB at 50 Hz and +0.03 at 5 kHz, the gain 6.02
        db = 20.0 * $log10(1.0 * f50 / o50);
        check(db > 11.4 && db < 12.4, "old freaks must lift 50 Hz by 12 dB");
        db = 20.0 * $log10(1.0 * f5k / o5k);
        check(db > 5.7 && db < 6.4, "old freaks must lift 5 kHz by 6 dB");
    end
    stereo = 1;

    // ---- volume, mute, saturation ----
    step(765, 765, 0, ol, orr);
    volume = 2'd2; clocks(100); x = sl(l);
    volume = 2'd1; clocks(100); y = sl(l);
    volume = 2'd0; clocks(100); t = sl(l);
    $display("[mixer] volume: full %0d, half %0d, quarter %0d, mute %0d", ol, x, y, t);
    check(iabs(x - ol / 2) < 30 && iabs(y - ol / 4) < 30 && t == 0, "volume must halve, quarter and mute");
    volume = 2'd3;
    a = 0; b = 0; clocks(3000000);
    a = 765; b = 765; beep = 1; cov = 8'hFF; lpt = 8'hFF;      // 42872 of step
    clocks(200); x = sl(l);
    $display("[mixer] everything at full: %0d (saturates at 32767, never wraps)", x);
    check(x == 32767, "the sum past full scale must saturate");
    clocks(1000000);                              // the blocker's mean passes 32767
    a = 0; b = 0; beep = 0; cov = 0; lpt = 0; clocks(200); x = sl(l);
    $display("[mixer] and back to silence: %0d", x);
    check(x == -32767, "the step back must saturate negative, not wrap");

    // ---- old freaks: the limiter ----
    oldf = 1;
    a = 0; b = 0; clocks(3000000);
    a = 765; b = 765; clocks(200); x = sl(l);
    // y 18360 plus a shelf that has charged 200/2048 of the way, doubled,
    // is about 40140; the limiter makes that 16384 + (40140 - 16384) / 4
    $display("[mixer] old freaks, 18360 in: %0d out (expect about 22320)", x);
    check(x > 21800 && x < 22800, "the limiter must take a quarter of the slope past 16384");
    beep = 1; cov = 8'hFF; lpt = 8'hFF; clocks(200000); x = sl(l);
    $display("[mixer] old freaks, everything at full: %0d", x);
    check(x == 32767, "old freaks must saturate, not wrap");
    clocks(1000000);
    a = 0; b = 0; beep = 0; cov = 0; lpt = 0; clocks(3000); x = sl(l);
    $display("[mixer] old freaks, and back to silence: %0d", x);
    check(x == -32767, "old freaks must saturate negative, not wrap");
    oldf = 0;

    // ---- the output word changes every 16 clocks at most ----
    a = 0; clocks(3000000);
    changes = 0; prev = l;
    for (k = 0; k < 1600; k = k + 1) begin
        a = (k % 7) * 100;                        // input changing every clock
        @(posedge clk); #1;
        if (l !== prev) changes = changes + 1;
        prev = l;
    end
    $display("[mixer] output changed %0d times in 1600 clocks (at most 100)", changes);
    check(changes <= 100, "out_l must change only once every 16 clocks");

    $display("[tb_mixer] %0d error(s)", errors);
    if (errors == 0) $display("PASS: mixer - ABC panning, DC blocker, 4.87 kHz low-pass, volume, saturation, old freaks, the 16-clock output");
    $finish;
end
endmodule
