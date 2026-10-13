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
