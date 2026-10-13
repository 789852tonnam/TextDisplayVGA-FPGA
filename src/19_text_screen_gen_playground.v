`timescale 1ns / 1ps

// VGA text editor and scrolling sign. ASCII/font rendering is based on
// FPGA Prototyping by Verilog Examples by Pong P. Chu, adapted for Basys 3
// by David J. Marion, Matt, and the VGA Playground interface.
module text_screen_gen #(
    parameter MAX_X = 80,
    parameter MAX_Y = 30,
    parameter SLIDE_STEP_FRAMES = 4,
    parameter SLIDE_TOP = 176
)(
    input wire clk,
    input wire reset,
    input wire video_off,
    input wire [11:0] gamepad_in,
    input wire [9:0] x,
    input wire [9:0] y,
    output reg [5:0] rgb
);
    localparam EDIT = 1'b0;
    localparam SLIDE = 1'b1;
    localparam SEL_NONE = 2'd0;
    localparam SEL_END = 2'd1;
    localparam SEL_READY = 2'd2;
    localparam FRAME_COUNT_WIDTH = (SLIDE_STEP_FRAMES < 2) ? 1 : $clog2(SLIDE_STEP_FRAMES);

    reg mode_reg, mode_next;
    reg [11:0] buttons_prev_reg;
    wire b_press = gamepad_in[11] && ~buttons_prev_reg[11];
    wire select_press = gamepad_in[9] && ~buttons_prev_reg[9];
    wire start_press = gamepad_in[8] && ~buttons_prev_reg[8];
    wire a_press = gamepad_in[3] && ~buttons_prev_reg[3];
    // The Pmod decoder supplies synchronized, active-high button states.
    wire move_xl_tick = gamepad_in[5] && ~buttons_prev_reg[5];
    wire move_yu_tick = gamepad_in[7] && ~buttons_prev_reg[7];
    wire move_yd_tick = gamepad_in[6] && ~buttons_prev_reg[6];
    wire move_xr_tick = gamepad_in[4] && ~buttons_prev_reg[4];

    reg [6:0] cur_x_reg;
    reg [4:0] cur_y_reg;
    wire [6:0] cur_x_next;
    wire [4:0] cur_y_next;
    reg [1:0] selection_reg;
    reg [6:0] select_left_reg, select_right_reg;
    reg [4:0] select_row_reg;

    // Eleven ASCII codes: ten visible characters plus one at the right edge.
    reg [6:0] slide_buffer [0:10];
    reg [2:0] slide_phase_reg;
    reg [FRAME_COUNT_WIDTH-1:0] slide_frame_reg;
    reg [3:0] slide_fill_reg;
    reg [6:0] slide_fetch_x_reg;
    reg slide_loading_reg, slide_ready_reg;
    wire frame_tick = (x == 10'd0) && (y == 10'd480);
    wire [6:0] slide_fetch_next =
        (slide_fetch_x_reg == select_right_reg - 7'd1) ?
            select_left_reg + 7'd1 : slide_fetch_x_reg + 7'd1;
    integer buffer_index;

    wire [11:0] addr_r, addr_w;
    wire [6:0] din, dout, cursor_char;
    wire we;
    wire edit_action = (mode_reg == EDIT) && ~start_press && ~select_press;
    // During SLIDE the asynchronous cursor read fills/refills the queue.
    // The VGA read port keeps its own address throughout.
    assign addr_w = (mode_reg == SLIDE) ?
                    {select_row_reg, slide_fetch_x_reg} : {cur_y_reg, cur_x_reg};
    assign addr_r = {y[8:4], x[9:3]};
    assign we = ~reset && edit_action && (a_press || b_press);
    assign din = a_press ? 7'h20 :
                 ((cursor_char >= 7'h41 && cursor_char < 7'h5a) ?
                    cursor_char + 7'd1 : 7'h41);

    simpledpmem #(.DATA_SIZE(7), .ADDR_SIZE(12)) dp_ram(
        .clk(clk), .reset(), .dat_in(din), .wr_adr(addr_w), .wr_en(we),
        .dat_out(dout), .rd_adr(addr_r), .dat_cursor(cursor_char)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mode_reg <= EDIT;
            buttons_prev_reg <= 0;
            cur_x_reg <= 0;
            cur_y_reg <= 0;
        end else begin
            mode_reg <= mode_next;
            buttons_prev_reg <= gamepad_in;
            if (edit_action) begin
                cur_x_reg <= cur_x_next;
                cur_y_reg <= cur_y_next;
            end
        end
    end

    always @(*) begin
        mode_next = mode_reg;
        case (mode_reg)
            EDIT: if (start_press && selection_reg == SEL_READY) mode_next = SLIDE;
            SLIDE: if (start_press) mode_next = EDIT;
            default: mode_next = EDIT;
        endcase
    end

    // Brackets are display overlays. They never overwrite the text RAM.
    // Both endpoints stay on one row and exclude their own cells.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            selection_reg <= SEL_NONE;
            select_left_reg <= 0;
            select_right_reg <= 0;
            select_row_reg <= 0;
        end else if (mode_reg == EDIT && ~start_press && select_press) begin
            case (selection_reg)
                SEL_NONE, SEL_READY: begin
                    // Leave room for at least one character and a right bracket.
                    if (cur_x_reg <= MAX_X - 3) begin
                        select_left_reg <= cur_x_reg;
                        select_row_reg <= cur_y_reg;
                        selection_reg <= SEL_END;
                    end
                end
                SEL_END: begin
                    if (cur_y_reg == select_row_reg &&
                        cur_x_reg > select_left_reg + 7'd1) begin
                        select_right_reg <= cur_x_reg;
                        selection_reg <= SEL_READY;
                    end
                end
                default: selection_reg <= SEL_NONE;
            endcase
        end
    end

    // Prepare the queue during vertical blanking. Every eight movement steps
    // a full 64-pixel character leaves the screen and the queue advances.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            slide_phase_reg <= 0;
            slide_frame_reg <= 0;
            slide_fill_reg <= 0;
            slide_fetch_x_reg <= 0;
            slide_loading_reg <= 0;
            slide_ready_reg <= 0;
            for (buffer_index = 0; buffer_index < 11; buffer_index = buffer_index + 1)
                slide_buffer[buffer_index] <= 7'h20;
        end else if (mode_reg == EDIT) begin
            slide_phase_reg <= 0;
            slide_frame_reg <= 0;
            slide_fill_reg <= 0;
            slide_fetch_x_reg <= select_left_reg + 7'd1;
            slide_loading_reg <= 0;
            slide_ready_reg <= 0;
        end else if (~slide_ready_reg) begin
            if (frame_tick)
                slide_loading_reg <= 1;
            if (slide_loading_reg) begin
                slide_buffer[slide_fill_reg] <= cursor_char;
                slide_fetch_x_reg <= slide_fetch_next;
                if (slide_fill_reg == 4'd10) begin
                    slide_loading_reg <= 0;
                    slide_ready_reg <= 1;
                end else begin
                    slide_fill_reg <= slide_fill_reg + 4'd1;
                end
            end
        end else if (frame_tick) begin
            if (slide_frame_reg == SLIDE_STEP_FRAMES - 1) begin
                slide_frame_reg <= 0;
                slide_phase_reg <= slide_phase_reg + 3'd1;
                if (slide_phase_reg == 3'd7) begin
                    for (buffer_index = 0; buffer_index < 10; buffer_index = buffer_index + 1)
                        slide_buffer[buffer_index] <= slide_buffer[buffer_index + 1];
                    slide_buffer[10] <= cursor_char;
                    slide_fetch_x_reg <= slide_fetch_next;
                end
            end else begin
                slide_frame_reg <= slide_frame_reg + 1'b1;
            end
        end
    end

    assign cur_x_next =
        (move_xr_tick && cur_x_reg == MAX_X - 1) || (move_xl_tick && cur_x_reg == 0) ? 0 :
        move_xr_tick ? cur_x_reg + 7'd1 : move_xl_tick ? cur_x_reg - 7'd1 : cur_x_reg;
    assign cur_y_next =
        (move_yu_tick && cur_y_reg == 0) || (move_yd_tick && cur_y_reg == MAX_Y - 1) ? 0 :
        move_yu_tick ? cur_y_reg - 5'd1 : move_yd_tick ? cur_y_reg + 5'd1 : cur_y_reg;

    // Both modes use two clocks: character lookup, then font lookup.
    reg [9:0] pix_x1_reg, pix_y1_reg, pix_x2_reg, pix_y2_reg;
    reg [9:0] slide_x1_reg, slide_x2_reg, slide_y1_reg;
    reg [6:0] slide_char_reg;
    reg mode1_reg, mode2_reg, ready1_reg, ready2_reg;
    wire [9:0] slide_x = x + {4'b0, slide_phase_reg, 3'b0};
    wire [9:0] slide_y = y - SLIDE_TOP;
    wire [3:0] slide_slot = slide_x[9:6];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pix_x1_reg <= 0;
            pix_y1_reg <= 0;
            pix_x2_reg <= 0;
            pix_y2_reg <= 0;
            slide_x1_reg <= 0;
            slide_x2_reg <= 0;
            slide_y1_reg <= 0;
            slide_char_reg <= 7'h20;
            mode1_reg <= EDIT;
            mode2_reg <= EDIT;
            ready1_reg <= 0;
            ready2_reg <= 0;
        end else begin
            pix_x1_reg <= x;
            pix_y1_reg <= y;
            pix_x2_reg <= pix_x1_reg;
            pix_y2_reg <= pix_y1_reg;
            slide_x1_reg <= slide_x;
            slide_x2_reg <= slide_x1_reg;
            slide_y1_reg <= slide_y;
            slide_char_reg <= (slide_slot <= 4'd10) ? slide_buffer[slide_slot] : 7'h20;
            mode1_reg <= mode_reg;
            mode2_reg <= mode1_reg;
            ready1_reg <= slide_ready_reg;
            ready2_reg <= ready1_reg;
        end
    end

    wire left_marker1 = (selection_reg != SEL_NONE) &&
        (pix_y1_reg[8:4] == select_row_reg) && (pix_x1_reg[9:3] == select_left_reg);
    wire right_marker1 = (selection_reg == SEL_READY) &&
        (pix_y1_reg[8:4] == select_row_reg) && (pix_x1_reg[9:3] == select_right_reg);
    wire marker_on = (selection_reg != SEL_NONE) &&
        (pix_y2_reg[8:4] == select_row_reg) &&
        ((pix_x2_reg[9:3] == select_left_reg) ||
         (selection_reg == SEL_READY && pix_x2_reg[9:3] == select_right_reg));
    wire cursor_on = (mode_reg == EDIT) && (mode2_reg == EDIT) &&
        (pix_y2_reg[8:4] == cur_y_reg) && (pix_x2_reg[9:3] == cur_x_reg);
    wire [6:0] char_addr = (mode1_reg == SLIDE) ? slide_char_reg :
        left_marker1 ? 7'h3c : right_marker1 ? 7'h3e : dout;
    // Match the ROM row to the character's one-clock RAM/buffer latency.
    wire [3:0] row_addr = (mode1_reg == SLIDE) ? slide_y1_reg[6:3] : pix_y1_reg[3:0];
    wire [10:0] rom_addr = {char_addr, row_addr};
    wire [7:0] font_word;
    wire [2:0] bit_addr = (mode2_reg == SLIDE) ? slide_x2_reg[5:3] : pix_x2_reg[2:0];
    wire ascii_bit = font_word[~bit_addr];
    ascii_rom a_rom(.clk(clk), .addr(rom_addr), .data(font_word));

    always @(*) begin
        rgb = 6'b0;
        if (~video_off && mode_reg == mode2_reg) begin
            if (mode2_reg == SLIDE) begin
                if (ready2_reg && pix_y2_reg >= SLIDE_TOP && pix_y2_reg < SLIDE_TOP + 128)
                    rgb = ascii_bit ? 6'b111111 : 6'b0;
            end else if (cursor_on) begin
                rgb = ascii_bit ? 6'b0 : (marker_on ? 6'b111100 : 6'b111111);
            end else begin
                rgb = ascii_bit ? (marker_on ? 6'b111100 : 6'b111111) : 6'b0;
            end
        end
    end
endmodule
