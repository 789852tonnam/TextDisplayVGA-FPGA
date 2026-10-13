`timescale 1ns/1ps
module tb_marquee;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1;
    reg [11:0] buttons = 0;
    reg [9:0] x = 16, y = 0;
    wire [5:0] rgb;
    text_screen_gen #(.SLIDE_STEP_FRAMES(2)) dut(
        .clk(clk), .reset(reset), .video_off(1'b0),
        .gamepad_in(buttons), .x(x), .y(y), .rgb(rgb)
    );
    integer i, step;
    reg [6:0] saved_boundary;

    task press;
        input [11:0] mask;
        begin
            buttons = mask;
            repeat (5) @(negedge clk);
            buttons = 0;
            repeat (3) @(negedge clk);
        end
    endtask
    task right;
        input integer count;
        integer n;
        begin for (n = 0; n < count; n = n + 1) press(12'h010); end
    endtask
    task left;
        input integer count;
        integer n;
        begin for (n = 0; n < count; n = n + 1) press(12'h020); end
    endtask
    task write_letter;
        input integer count;
        integer n;
        begin for (n = 0; n < count; n = n + 1) press(12'h800); end
    endtask
    task frame;
        begin
            x = 0; y = 480;
            @(negedge clk);
            x = 1;
            @(negedge clk);
            x = 16; y = 0;
            @(negedge clk);
        end
    endtask
    function [6:0] message_letter;
        input integer index;
        begin
            case (index % 5)
                0: message_letter = "H";
                1: message_letter = "E";
                2, 3: message_letter = "L";
                4: message_letter = "O";
            endcase
        end
    endfunction
    task check_queue;
        input integer first;
        integer n;
        begin
            for (n = 0; n < 11; n = n + 1)
                if (dut.slide_buffer[n] !== message_letter(first + n))
                    $fatal(1, "Queue[%0d], offset %0d: expected %h got %h", n, first,
                        message_letter(first + n), dut.slide_buffer[n]);
        end
    endtask
    task check_pixel;
        input [9:0] px, py;
        input [5:0] expected;
        begin
            x = px; y = py;
            repeat (3) @(negedge clk);
            if (rgb !== expected)
                $fatal(1, "Pixel (%0d,%0d): expected %h got %h", px, py, expected, rgb);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        repeat (3) @(negedge clk);
        press(12'h100);
        if (dut.mode_reg !== dut.EDIT) $fatal(1, "Start allowed unselected range");
        right(2);
        press(12'h200);
        if (dut.selection_reg !== dut.SEL_END) $fatal(1, "First Select did not place <");
        press(12'h200);
        if (dut.selection_reg !== dut.SEL_END) $fatal(1, "Accepted overlapping >");
        left(1);
        press(12'h200);
        if (dut.selection_reg !== dut.SEL_END) $fatal(1, "Accepted > before <");
        right(2);
        press(12'h200);
        if (dut.selection_reg !== dut.SEL_END) $fatal(1, "Accepted empty selection");
        press(12'h040);
        right(1);
        press(12'h200);
        if (dut.selection_reg !== dut.SEL_END) $fatal(1, "Accepted different row");
        press(12'h080);
        press(12'h200);
        if (dut.selection_reg !== dut.SEL_READY) $fatal(1, "Valid > was rejected");
        left(4);
        write_letter(2); // Underlying B must survive the bracket overlay.
        saved_boundary = dut.dp_ram.memory[0];
        press(12'h200); // Third Select starts a new range at column zero.
        if (dut.selection_reg !== dut.SEL_END || dut.select_left_reg !== 0)
            $fatal(1, "Reselection failed");
        right(1); write_letter(8); // H
        right(1); write_letter(5); // E
        right(1); write_letter(12); // L
        right(1); write_letter(12); // L
        right(1); write_letter(15); // O
        right(1);
        press(12'h200);
        if (dut.select_right_reg !== 6 || dut.selection_reg !== dut.SEL_READY)
            $fatal(1, "HELLO selection failed");
        if (dut.dp_ram.memory[0] !== saved_boundary || dut.dp_ram.memory[6] !== 0)
            $fatal(1, "Bracket overlays modified RAM");
        check_pixel(4, 0, 6'b111100); // Yellow '<', cursor is elsewhere.
        check_pixel(9, 0, 6'b111111); // H pixel, normal edit rendering.
        press(12'h100);
        if (dut.mode_reg !== dut.SLIDE || dut.slide_ready_reg !== 0)
            $fatal(1, "SLIDE entry/prefill state failed");
        frame();
        repeat (15) @(negedge clk);
        if (dut.slide_ready_reg !== 1) $fatal(1, "Queue fill did not complete");
        check_queue(0);
        // 64x128 scaling: H's first design row is 0x44.
        check_pixel(0, 176, 0);
        check_pixel(8, 176, 6'b111111);
        check_pixel(15, 191, 6'b111111);
        check_pixel(16, 176, 0);
        check_pixel(639, 175, 0);
        check_pixel(8, 304, 0);
        // 80 movement steps exercise ten queue shifts and repeated message wraps.
        for (step = 1; step <= 80; step = step + 1) begin
            frame();
            if (dut.slide_phase_reg !== ((step - 1) % 8))
                $fatal(1, "Phase changed before configured frame interval");
            frame();
            if (dut.slide_phase_reg !== (step % 8)) $fatal(1, "Eight-step phase failed");
            check_queue(step / 8);
            if (dut.slide_fetch_x_reg < 1 || dut.slide_fetch_x_reg > 5)
                $fatal(1, "Fetch escaped selected interior");
        end
        press(12'h808); // Editing is disabled during SLIDE.
        press(12'h010);
        if (dut.cur_x_reg !== 6 || dut.dp_ram.memory[6] !== 0)
            $fatal(1, "SLIDE allowed cursor movement or editing");
        press(12'h100);
        if (dut.mode_reg !== dut.EDIT || dut.cur_x_reg !== 6 || dut.selection_reg !== dut.SEL_READY)
            $fatal(1, "Return to EDIT lost cursor/selection");
        // Edit selected text and re-enter; the new queue must read fresh RAM.
        left(5);
        press(12'h008);
        press(12'h800);
        press(12'h100);
        frame();
        repeat (15) @(negedge clk);
        if (dut.slide_buffer[0] !== "A") $fatal(1, "Reentry used stale queue contents");
        reset = 1;
        repeat (3) @(negedge clk);
        reset = 0;
        repeat (3) @(negedge clk);
        if (dut.mode_reg !== dut.EDIT || dut.selection_reg !== dut.SEL_NONE)
            $fatal(1, "Reset did not clear mode/selection");
        if (dut.dp_ram.memory[1] !== "A") $fatal(1, "Reset erased text RAM");
        // A single-letter range on another row must repeat in all eleven slots.
        press(12'h040);
        press(12'h200);
        right(1); write_letter(13); // M
        right(1); press(12'h200);
        press(12'h100);
        frame();
        repeat (15) @(negedge clk);
        for (i = 0; i < 11; i = i + 1)
            if (dut.slide_buffer[i] !== "M") $fatal(1, "Single-letter/row selection failed");
        // Select is ignored in SLIDE; Start still returns to EDIT once when held.
        press(12'h200);
        if (dut.select_row_reg !== 1) $fatal(1, "SLIDE altered selection");
        press(12'h100);
        if (dut.mode_reg !== dut.EDIT) $fatal(1, "Held Start toggled repeatedly");
        right(76); // Column 78 cannot fit both brackets and a character.
        press(12'h200);
        if (dut.selection_reg !== dut.SEL_READY) $fatal(1, "Accepted impossible left endpoint");
        // Twelve characters exercise a refill not already in the initial queue.
        left(78);
        press(12'h200);
        for (i = 1; i <= 12; i = i + 1)
            dut.dp_ram.memory[128 + i] = 7'h40 + i; // A..L, on row one.
        right(13);
        press(12'h200);
        press(12'h100);
        frame();
        repeat (15) @(negedge clk);
        for (i = 0; i < 11; i = i + 1)
            if (dut.slide_buffer[i] !== 7'h41 + i) $fatal(1, "Long-message initial fill failed");
        for (i = 0; i < 7; i = i + 1) begin frame(); frame(); end
        check_pixel(592, 176, 6'b111111); // Visible portion of slot 10 (K).
        frame(); frame();
        for (i = 0; i < 11; i = i + 1)
            if (dut.slide_buffer[i] !== 7'h42 + i) $fatal(1, "Long-message refill failed");
        for (i = 0; i < 8; i = i + 1) begin frame(); frame(); end
        if (dut.slide_buffer[10] !== "A") $fatal(1, "Long-message endpoint wrap failed");
        $display("PASS: edit, bracket validation/overlay, queue fill/wrap/cadence, 64x128 pixels, slide lock, reentry, reset, single-letter row, endpoint limits");
        $finish;
    end
endmodule
