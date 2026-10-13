// Paste into project.v at https://vga-playground.com/?preset=gamepad
// Keep the preset gamepad_pmod.v and hvsync_generator.v tabs.
// EDIT: D-pad moves, B increments, A erases, Select places < then >.
// Start toggles EDIT/SLIDE after selecting a nonempty single-row range.
// SLIDE: eleven ASCII codes, 64x128 font, eight-pixel movement steps.

// ===== Source: 19_top_SwitchTextDisplay_playground.v =====
`default_nettype none

module tt_um_vga_example(
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
    );
    
    // VGA signals
    wire hsync;
    wire vsync;
    wire [1:0] R;
    wire [1:0] G;
    wire [1:0] B;
    wire video_active;
    wire [9:0] pix_x;
    wire [9:0] pix_y;

    
    // Unused outputs assigned to 0.
    assign uio_out = 0;
    assign uio_oe  = 0;

    // Suppress unused signals warning
    wire _unused_ok = &{ena, ui_in[7], ui_in[3:0], uio_in};

    hvsync_generator vga_sync_gen (
      .clk(clk),
      .reset(~rst_n),
      .hsync(hsync),
      .vsync(vsync),
      .display_on(video_active),
      .hpos(pix_x),
      .vpos(pix_y)
    );

    // Gamepad Pmod
    wire inp_b, inp_y, inp_select, inp_start, inp_up, inp_down, inp_left, inp_right, inp_a, inp_x, inp_l, inp_r;
    wire [11:0] gamepad_in = {inp_b, inp_y, inp_select, inp_start, inp_up, inp_down, inp_left, inp_right, inp_a, inp_x, inp_l, inp_r};

    gamepad_pmod_single driver (
      // Inputs:
      .rst_n(rst_n),
      .clk(clk),
      .pmod_data(ui_in[6]),
      .pmod_clk(ui_in[5]),
      .pmod_latch(ui_in[4]),
      // Outputs:
      .b(inp_b),
      .y(inp_y),
      .select(inp_select),
      .start(inp_start),
      .up(inp_up),
      .down(inp_down),
      .left(inp_left),
      .right(inp_right),
      .a(inp_a),
      .x(inp_x),
      .l(inp_l),
      .r(inp_r)
    );

    wire [5:0] color;

    // instantiate text generation circuit
    wire [9:0] predicted_pix_x;
    wire [9:0] predicted_pix_y;
    assign predicted_pix_x = (pix_x + 2) % 800;
    assign predicted_pix_y = (pix_x + 2 > 799) ? (pix_y + 1) % 525: pix_y;
    text_screen_gen tsg(.clk(clk), .reset(~rst_n), .video_off(~video_active), 
                        .gamepad_in(gamepad_in), .x(predicted_pix_x), .y(predicted_pix_y), .rgb(color));

    assign R = (video_active)? color[5:4]:0;
    assign G = (video_active)? color[3:2]:0;
    assign B = (video_active)? color[1:0]:0;

    assign uo_out  = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

endmodule

`default_nettype wire

// ===== Source: 19_text_screen_gen_playground.v =====
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

// ===== Source: 13_simpledualportMem.v =====
module simpledpmem
	#(
        parameter DATA_SIZE = 16,
        parameter ADDR_SIZE = 16
    )
	(input wire clk,
	input wire reset,
	input wire [DATA_SIZE-1:0] dat_in,
	input wire [ADDR_SIZE-1:0] wr_adr,
	input wire wr_en,
	output reg [DATA_SIZE-1:0] dat_out,
	input wire [ADDR_SIZE-1:0] rd_adr,
	output wire [DATA_SIZE-1:0] dat_cursor
	);

	reg [DATA_SIZE-1:0] memory[2**ADDR_SIZE-1:0];
	integer init_addr;
	initial begin
		for (init_addr = 0; init_addr < 2**ADDR_SIZE; init_addr = init_addr + 1)
			memory[init_addr] = {DATA_SIZE{1'b0}};
	end

	// Read the cursor cell independently of the VGA scan address.
	assign dat_cursor = memory[wr_adr];

	always @( posedge clk ) begin
		if (wr_en)
			memory[wr_adr] <= dat_in;
		dat_out <= memory[rd_adr];
	end
	

endmodule

// ===== Source: 10_debounce.v =====
`timescale 1ns / 1ps


module debouncer(
    input clk,
    input PB,  // "PB" is the glitchy, asynchronous to clk, active low push-button signal

    // from which we make three outputs, all synchronous to the clock
    output reg PB_state,  // 1 as long as the push-button is active (down)
    output PB_down,  // 1 for one clock cycle when the push-button goes down (i.e. just pushed)
    output PB_up   // 1 for one clock cycle when the push-button goes up (i.e. just released)
);

	// First use two flip-flops to synchronize the PB signal the "clk" clock domain
	// Synchronize the switch input to the clock
	reg PB_sync_0;  
	always @(posedge clk) PB_sync_0 <= ~PB;  // invert PB to make PB_sync_0 active high
	
	reg PB_sync_1;  
	always @(posedge clk) PB_sync_1 <= PB_sync_0;

	// Next declare a 16-bits counter
	reg [15:0] PB_cnt;

	// When the push-button is pushed or released, we increment the counter
	// The counter has to be maxed out before we decide that the push-button state has changed

	wire PB_idle = (PB_state==PB_sync_1);
	wire PB_cnt_max = &PB_cnt;	// true when all bits of PB_cnt are 1's

	always @(posedge clk)
		if(PB_idle)
			PB_cnt <= 0;  // nothing's going on
		else
		begin
			PB_cnt <= PB_cnt + 16'd1;  // something's going on, increment the counter
			if(PB_cnt_max) PB_state <= ~PB_state;  // if the counter is maxed out, PB changed!
		end

	// high for one clk
	assign PB_down = ~PB_idle & PB_cnt_max & ~PB_state;
	assign PB_up   = ~PB_idle & PB_cnt_max &  PB_state;
endmodule

// ===== Source: 19_ascii_rom_playground.v =====
// Complete 7-bit ASCII character ROM: hand-drawn pixel font.
// Five-pixel-wide strokes with blank side bearings in each 8x16 cell.
// Seven design rows plus a descender row; each row repeats twice.
// Printable characters 0x20-0x7e have 8x16 glyphs.
// Control characters 0x00-0x1f and DEL (0x7f) are blank.

module ascii_rom(
    input wire clk,
    input wire [10:0] addr,
    output reg [7:0] data
    );

    reg [10:0] addr_reg;
    reg [127:0] glyph;

    // Keep the original one-clock synchronous ROM-address latency.
    always @(posedge clk)
        addr_reg <= addr;

    always @* begin
        // Each constant contains 16 rows, from top to bottom.
        // The leftmost pixel in a row is bit 7.
        case (addr_reg[10:4])
            7'h20: glyph = 128'h00000000000000000000000000000000; // space
            7'h21: glyph = 128'h10101010101010101010000010100000; // !
            7'h22: glyph = 128'h28282828282800000000000000000000; // "
            7'h23: glyph = 128'h282828287c7c28287c7c282828280000; // #
            7'h24: glyph = 128'h10103c3c505038381414787810100000; // $
            7'h25: glyph = 128'h606064640808101020204c4c0c0c0000; // %
            7'h26: glyph = 128'h30304848505030305454484834340000; // &
            7'h27: glyph = 128'h10101010202000000000000000000000; // '
            7'h28: glyph = 128'h08081010202020202020101008080000; // (
            7'h29: glyph = 128'h20201010080808080808101020200000; // )
            7'h2a: glyph = 128'h00001010545438385454101000000000; // *
            7'h2b: glyph = 128'h0000101010107c7c1010101000000000; // +
            7'h2c: glyph = 128'h00000000000000000000101020200000; // ,
            7'h2d: glyph = 128'h0000000000007c7c0000000000000000; // -
            7'h2e: glyph = 128'h00000000000000000000000010100000; // .
            7'h2f: glyph = 128'h04040404080810102020404040400000; // /
            7'h30: glyph = 128'h383844444c4c54546464444438380000; // 0
            7'h31: glyph = 128'h10103030101010101010101038380000; // 1
            7'h32: glyph = 128'h3838444404040808101020207c7c0000; // 2
            7'h33: glyph = 128'h7c7c0808101018180404444438380000; // 3
            7'h34: glyph = 128'h08081818282848487c7c080808080000; // 4
            7'h35: glyph = 128'h7c7c4040787804040404444438380000; // 5
            7'h36: glyph = 128'h18182020404078784444444438380000; // 6
            7'h37: glyph = 128'h7c7c0404080810102020202020200000; // 7
            7'h38: glyph = 128'h38384444444438384444444438380000; // 8
            7'h39: glyph = 128'h3838444444443c3c0404080830300000; // 9
            7'h3a: glyph = 128'h00000000101000000000101000000000; // :
            7'h3b: glyph = 128'h00000000101000000000101020200000; // ;
            7'h3c: glyph = 128'h08081010202040402020101008080000; // <
            7'h3d: glyph = 128'h000000007c7c00007c7c000000000000; // =
            7'h3e: glyph = 128'h20201010080804040808101020200000; // >
            7'h3f: glyph = 128'h38384444040408081010000010100000; // ?
            7'h40: glyph = 128'h383844445c5c6c6c5c5c404038380000; // @
            7'h41: glyph = 128'h38384444444444447c7c444444440000; // A
            7'h42: glyph = 128'h78784444444478784444444478780000; // B
            7'h43: glyph = 128'h38384444404040404040444438380000; // C
            7'h44: glyph = 128'h70704848444444444444484870700000; // D
            7'h45: glyph = 128'h7c7c404040407878404040407c7c0000; // E
            7'h46: glyph = 128'h7c7c4040404078784040404040400000; // F
            7'h47: glyph = 128'h3838444440405c5c444444443c3c0000; // G
            7'h48: glyph = 128'h4444444444447c7c4444444444440000; // H
            7'h49: glyph = 128'h38381010101010101010101038380000; // I
            7'h4a: glyph = 128'h1c1c0808080808080808484830300000; // J
            7'h4b: glyph = 128'h44444848505060605050484844440000; // K
            7'h4c: glyph = 128'h4040404040404040404040407c7c0000; // L
            7'h4d: glyph = 128'h44446c6c545454544444444444440000; // M
            7'h4e: glyph = 128'h44444444646454544c4c444444440000; // N
            7'h4f: glyph = 128'h38384444444444444444444438380000; // O
            7'h50: glyph = 128'h78784444444478784040404040400000; // P
            7'h51: glyph = 128'h38384444444444445454484834340000; // Q
            7'h52: glyph = 128'h78784444444478785050484844440000; // R
            7'h53: glyph = 128'h3c3c4040404038380404040478780000; // S
            7'h54: glyph = 128'h7c7c1010101010101010101010100000; // T
            7'h55: glyph = 128'h44444444444444444444444438380000; // U
            7'h56: glyph = 128'h44444444444444444444282810100000; // V
            7'h57: glyph = 128'h44444444444454545454545428280000; // W
            7'h58: glyph = 128'h44444444282810102828444444440000; // X
            7'h59: glyph = 128'h44444444282810101010101010100000; // Y
            7'h5a: glyph = 128'h7c7c040408081010202040407c7c0000; // Z
            7'h5b: glyph = 128'h38382020202020202020202038380000; // [
            7'h5c: glyph = 128'h40404040202010100808040404040000; // backslash
            7'h5d: glyph = 128'h38380808080808080808080838380000; // ]
            7'h5e: glyph = 128'h10102828444400000000000000000000; // ^
            7'h5f: glyph = 128'h00000000000000000000000000007c7c; // _
            7'h60: glyph = 128'h20201010080800000000000000000000; // `
            7'h61: glyph = 128'h00000000383804043c3c44443c3c0000; // a
            7'h62: glyph = 128'h40404040787844444444444478780000; // b
            7'h63: glyph = 128'h00000000383844444040444438380000; // c
            7'h64: glyph = 128'h040404043c3c4444444444443c3c0000; // d
            7'h65: glyph = 128'h00000000383844447c7c404038380000; // e
            7'h66: glyph = 128'h18182424202070702020202020200000; // f
            7'h67: glyph = 128'h000000003c3c444444443c3c04043838; // g
            7'h68: glyph = 128'h40404040787844444444444444440000; // h
            7'h69: glyph = 128'h10100000303010101010101038380000; // i
            7'h6a: glyph = 128'h08080000181808080808080848483030; // j
            7'h6b: glyph = 128'h40404040484850506060505048480000; // k
            7'h6c: glyph = 128'h30301010101010101010101038380000; // l
            7'h6d: glyph = 128'h00000000686854545454545454540000; // m
            7'h6e: glyph = 128'h00000000787844444444444444440000; // n
            7'h6f: glyph = 128'h00000000383844444444444438380000; // o
            7'h70: glyph = 128'h00000000787844444444787840404040; // p
            7'h71: glyph = 128'h000000003c3c444444443c3c04040404; // q
            7'h72: glyph = 128'h00000000585864644040404040400000; // r
            7'h73: glyph = 128'h000000003c3c40403838040478780000; // s
            7'h74: glyph = 128'h20202020707020202020242418180000; // t
            7'h75: glyph = 128'h0000000044444444444444443c3c0000; // u
            7'h76: glyph = 128'h00000000444444444444282810100000; // v
            7'h77: glyph = 128'h00000000444444445454545428280000; // w
            7'h78: glyph = 128'h00000000444428281010282844440000; // x
            7'h79: glyph = 128'h000000004444444444443c3c04043838; // y
            7'h7a: glyph = 128'h000000007c7c0808101020207c7c0000; // z
            7'h7b: glyph = 128'h08081010101020201010101008080000; // {
            7'h7c: glyph = 128'h10101010101010101010101010100000; // |
            7'h7d: glyph = 128'h20201010101008081010101020200000; // }
            7'h7e: glyph = 128'h00000000202054540808000000000000; // ~
            default: glyph = 128'b0;
        endcase

        case (addr_reg[3:0])
            4'h0: data = glyph[127:120];
            4'h1: data = glyph[119:112];
            4'h2: data = glyph[111:104];
            4'h3: data = glyph[103:96];
            4'h4: data = glyph[95:88];
            4'h5: data = glyph[87:80];
            4'h6: data = glyph[79:72];
            4'h7: data = glyph[71:64];
            4'h8: data = glyph[63:56];
            4'h9: data = glyph[55:48];
            4'ha: data = glyph[47:40];
            4'hb: data = glyph[39:32];
            4'hc: data = glyph[31:24];
            4'hd: data = glyph[23:16];
            4'he: data = glyph[15:8];
            4'hf: data = glyph[7:0];
        endcase
    end

endmodule

`default_nettype wire
