module prienc_32_5
(
    input  logic [31:0] req,
    output logic [4:0]  lsb_priority
);
    
logic [7:0] seg_or;
logic [2:0] row_sel;
logic [1:0] col_sel;
logic [3:0] stage1_mux [3:0];
logic [3:0] stage2_mux [1:0];
logic [3:0] stage3_mux;
    
always_comb begin
    for (int i = 0; i < 8; i = i + 1) begin
        seg_or[i] = |(req[i*4 +: 4]);
    end
end
    
prienc_8_3 prienc_8_3_0
(
    .req(seg_or),
    .lsb_priority(row_sel)
);
    
assign stage1_mux[0] = (seg_or[0]) ? req[3:0]   : req[7:4];
assign stage1_mux[1] = (seg_or[2]) ? req[11:8]  : req[15:12];
assign stage1_mux[2] = (seg_or[4]) ? req[19:16] : req[23:20];
assign stage1_mux[3] = (seg_or[6]) ? req[27:24] : req[31:28];

assign stage2_mux[0] = (|(seg_or[1:0])) ? stage1_mux[0] : stage1_mux[1];
assign stage2_mux[1] = (|(seg_or[5:4])) ? stage1_mux[2] : stage1_mux[3];

assign stage3_mux    = (|(seg_or[3:0])) ? stage2_mux[0] : stage2_mux[1];

prienc_4_2 prienc_4_2_0
(
    .req(stage3_mux),
    .lsb_priority(col_sel)
);
    
// x * 4 + y
assign lsb_priority = (row_sel << 2) | col_sel;
    
endmodule