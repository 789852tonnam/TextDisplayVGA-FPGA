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
