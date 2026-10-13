`timescale 1ns/1ps
// Capture RGB from the real top-level VGA pipeline, including its +2 prediction.
module tb_marquee_render;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1;
    reg [11:0] buttons = 0;
    reg manual_frame_tick = 0;
    wire [7:0] uo_out;
    wire [5:0] rgb = {uo_out[0], uo_out[4], uo_out[1], uo_out[5], uo_out[2], uo_out[6]};
    reg [103:0] message = "HELLO FPGA123";
    integer i;
    tt_um_vga_example dut(.clk(clk), .rst_n(~reset), .ena(1'b1),
        .ui_in(8'd0), .uio_in(8'd0), .uo_out(uo_out), .uio_out(), .uio_oe());
    defparam dut.tsg.SLIDE_STEP_FRAMES = 1;
    task press;
        input [11:0] mask;
        begin
            buttons = mask;
            repeat (3) @(negedge clk);
            buttons = 0;
            repeat (3) @(negedge clk);
        end
    endtask
    task frame;
        begin
            manual_frame_tick = 1;
            @(negedge clk);
            manual_frame_tick = 0;
            repeat (3) @(negedge clk);
        end
    endtask
    task capture;
        input [255:0] name;
        integer fd, pixels;
        begin
            @(negedge clk);
            while (!(dut.pix_x == 0 && dut.pix_y == 0)) @(negedge clk);
            fd = $fopen(name, "w");
            if (!fd) $fatal(1, "Cannot open RGB capture");
            pixels = 0;
            while (pixels < 640 * 480) begin
                if (dut.pix_x < 640 && dut.pix_y < 480) begin
                    if (dut.pix_y * 640 + dut.pix_x != pixels)
                        $fatal(1, "VGA capture position skipped a pixel");
                    $fdisplay(fd, "%02x", rgb);
                    pixels = pixels + 1;
                end
                @(negedge clk);
            end
            $fclose(fd);
        end
    endtask
    initial begin
        // Exercise real RGB/timing output; use deterministic button/phase stimuli.
        force dut.gamepad_in = buttons;
        force dut.tsg.frame_tick = manual_frame_tick;
        repeat (3) @(negedge clk);
        reset = 0;
        repeat (3) @(negedge clk);
        for (i = 0; i < 13; i = i + 1)
            dut.tsg.dp_ram.memory[i + 1] = message[103 - i * 8 -: 8];
        press(12'h200);
        for (i = 0; i < 14; i = i + 1) press(12'h010);
        press(12'h200);
        press(12'h100);
        frame();
        repeat (15) @(negedge clk);
        if (!dut.tsg.slide_ready_reg) $fatal(1, "Render queue was not ready");
        capture("marquee_phase0.hex");
        for (i = 0; i < 7; i = i + 1) frame();
        capture("marquee_phase7.hex");
        frame();
        capture("marquee_shifted.hex");
        $display("PASS: full top-level RGB captures at phase 0, phase 7, and after queue shift");
        $finish;
    end
endmodule
