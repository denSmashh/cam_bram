`timescale 1ns / 1ps

module prienc_tb();

localparam IN_WIDTH = 128;
localparam OUT_WIDTH = $clog2(IN_WIDTH);

logic [IN_WIDTH-1:0]  req;
logic [OUT_WIDTH-1:0] prior_out;


prienc_lsb #(.IN_WIDTH(IN_WIDTH)) prienc_dut
(
    .req(req),
    .prior_out(prior_out)
);

initial begin
    
    req <= 'b0;
    #10;
    
    for(int i = 0; i < IN_WIDTH; i = i + 1) begin
        req <= (1 << i);
        #10;
    end
    
    for(int i = 0; i < 100; i = i+1) begin
        req <= $urandom();
        #10;
    end
end


endmodule
