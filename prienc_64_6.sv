module prienc_64_6
(
    input  logic [63:0] req,
    output logic [5:0]  lsb_priority
);

logic [7:0] seg_or;
logic [2:0] row_sel;
logic [2:0] col_sel;
logic [7:0] stage1_mux [3:0];
logic [7:0] stage2_mux [1:0];
logic [7:0] stage3_mux;

always_comb begin
    for (int i = 0; i < 8; i = i + 1) begin
        seg_or[i] = |(req[i*8 +: 8]);
    end
end

prienc_8_3 prienc_8_3_0
(
    .req(seg_or),
    .lsb_priority(row_sel)
);

assign stage1_mux[0] = (seg_or[0]) ? req[7:0]   : req[15:8];
assign stage1_mux[1] = (seg_or[2]) ? req[23:16] : req[31:24];
assign stage1_mux[2] = (seg_or[4]) ? req[39:32] : req[47:40];
assign stage1_mux[3] = (seg_or[6]) ? req[55:48] : req[63:56];

assign stage2_mux[0] = (|(seg_or[1:0])) ? stage1_mux[0] : stage1_mux[1];
assign stage2_mux[1] = (|(seg_or[5:4])) ? stage1_mux[2] : stage1_mux[3];

assign stage3_mux    = (|(seg_or[3:0])) ? stage2_mux[0] : stage2_mux[1];

prienc_8_3 prienc_8_3_1
(
    .req(stage3_mux),
    .lsb_priority(col_sel)
);

// x * 8 + y
assign lsb_priority = (row_sel << 3) | col_sel;
    
endmodule