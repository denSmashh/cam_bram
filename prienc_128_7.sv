module prienc_128_7
(
    input  logic [127:0] req,
    output logic [6:0]   lsb_priority
);

logic [15:0] seg_or;
logic [3:0] row_sel;
logic [2:0] col_sel;
logic [7:0] stage1_mux [7:0];
logic [7:0] stage2_mux [3:0];
logic [7:0] stage3_mux [1:0];
logic [7:0] stage4_mux;

always_comb begin
    for (int i = 0; i < 16; i = i + 1) begin
        seg_or[i] = |(req[i*8 +: 8]);
    end
end

prienc_16_4 prienc_16_4_0
(
    .req(seg_or),
    .lsb_priority(row_sel)
);

assign stage1_mux[0] = (seg_or[0])  ? req[7:0]     : req[15:8];
assign stage1_mux[1] = (seg_or[2])  ? req[23:16]   : req[31:24];
assign stage1_mux[2] = (seg_or[4])  ? req[39:32]   : req[47:40];
assign stage1_mux[3] = (seg_or[6])  ? req[55:48]   : req[63:56];
assign stage1_mux[4] = (seg_or[8])  ? req[71:64]   : req[79:72];
assign stage1_mux[5] = (seg_or[10]) ? req[87:80]   : req[95:88];
assign stage1_mux[6] = (seg_or[12]) ? req[103:96]  : req[111:104];
assign stage1_mux[7] = (seg_or[14]) ? req[119:112] : req[127:120];

assign stage2_mux[0] = (|(seg_or[1:0]))   ? stage1_mux[0] : stage1_mux[1];
assign stage2_mux[1] = (|(seg_or[5:4]))   ? stage1_mux[2] : stage1_mux[3];
assign stage2_mux[2] = (|(seg_or[9:8]))   ? stage1_mux[4] : stage1_mux[5];
assign stage2_mux[3] = (|(seg_or[13:12])) ? stage1_mux[6] : stage1_mux[7];

assign stage3_mux[0] = (|(seg_or[3:0]))  ? stage2_mux[0] : stage2_mux[1];
assign stage3_mux[1] = (|(seg_or[11:8])) ? stage2_mux[2] : stage2_mux[3];

assign stage4_mux    = (|(seg_or[7:0])) ? stage3_mux[0] : stage3_mux[1];

prienc_8_3 prienc_8_3_0
(
    .req(stage4_mux),
    .lsb_priority(col_sel)
);

// x * 8 + y
assign lsb_priority = (row_sel << 3) | col_sel;
    
endmodule