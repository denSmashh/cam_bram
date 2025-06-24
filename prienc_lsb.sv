// Parameterized Priority Encoder
// Highest priority - LSB
// Priority encoder support input vector width up to 128 bit

module prienc_lsb
#(
    parameter  IN_WIDTH  = 32,
    localparam OUT_WIDTH = $clog2(IN_WIDTH)
)    
(
    input  logic [IN_WIDTH-1:0]  req,
    output logic [OUT_WIDTH-1:0] prior_out
);

localparam PRIENC_4_2_NOT_USED = 4 - IN_WIDTH;

// Conversion input vector in matrix COLUMN x ROW
// 
// SIZE   COLUMN   ROW
//  2        -      -
//  4        -      -
//  8        -      -
//  16       4      4
//  32       8      4
//  64       8      8
//  128     16      8
//

generate

    if (IN_WIDTH == 2) begin
        assign prior_out = (req[0]) ? 1'b0 : 
                           (req[1]) ? 1'b1 : 1'b0;
    end

    else if (IN_WIDTH <= 4) begin
        prienc_4_2 i_prienc_4_2 (.req({{(4-IN_WIDTH){1'b0}},req}), .lsb_priority(prior_out));
    end

    else if (IN_WIDTH <= 8) begin
        prienc_8_3 i_prienc_8_3 (.req({{(8-IN_WIDTH){1'b0}},req}), .lsb_priority(prior_out));
    end

    else if (IN_WIDTH <= 16) begin
        prienc_16_4 i_prienc_16_4 (.req({{(16-IN_WIDTH){1'b0}},req}), .lsb_priority(prior_out));
    end

    else if (IN_WIDTH <= 32) begin
        prienc_32_5 i_prienc_32_5 (.req({{(32-IN_WIDTH){1'b0}},req}), .lsb_priority(prior_out));
    end

    else if (IN_WIDTH <= 64) begin
        prienc_64_6 i_prienc_64_6 (.req({{(64-IN_WIDTH){1'b0}},req}), .lsb_priority(prior_out));
    end

    else if (IN_WIDTH <= 128) begin
        prienc_128_7 i_prienc_128_7 (.req({{(128-IN_WIDTH){1'b0}},req}), .lsb_priority(prior_out));
    end

    // else : TODO: generate error 

endgenerate
    
endmodule