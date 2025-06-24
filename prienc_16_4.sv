module prienc_16_4
(
    input  logic [15:0] req,
    output logic [3:0]  lsb_priority
);
    
logic [3:0] seg_or;
logic [1:0] row_sel;
logic [1:0] col_sel;
logic [3:0] stage1_mux [1:0];
logic [3:0] stage2_mux;
    
always_comb begin
    for (int i = 0; i < 4; i = i + 1) begin
        seg_or[i] = |(req[i*4 +: 4]);
    end
end
    
prienc_4_2 prienc_4_2_0
(
    .req(seg_or),
    .lsb_priority(row_sel)
);
    
// with look-ahead signal (more fast realization)
assign stage1_mux[0] = (seg_or[0]) ? req[3:0]  : req[7:4];
assign stage1_mux[1] = (seg_or[2]) ? req[11:8] : req[15:12];

assign stage2_mux    = (|(seg_or[1:0])) ? stage1_mux[0] : stage1_mux[1];

prienc_4_2 prienc_4_2_1
(
    .req(stage2_mux),
    .lsb_priority(col_sel)
);
    
// x * 4 + y
assign lsb_priority = (row_sel << 2) | col_sel;
    
endmodule