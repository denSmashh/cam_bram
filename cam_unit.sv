module cam_unit 
#(
    parameter  BRAM_DEPTH       = 512,
    parameter  BRAM_WIDTH       = 64,
    parameter  CAM_DEPTH        = 64,
    localparam CAM_ADDR_WIDTH   = $clog2(BRAM_DEPTH),
    parameter  MULTIPUMP_FACTOR = 2
)
(
    // System
    input  logic                                    clk,
    input  logic                                    sys_rstn,
    input  logic                                    rst_cmd,

    // Memory interface
    input  logic                                    cam_chip_en,
    input  logic                                    cam_wr_en,
    input  logic [CAM_ADDR_WIDTH-1:0]               cam_addr,
    output logic [CAM_DEPTH-1:0]                    cam_rdata,
    input  logic                                    cam_compare,        

    // Update memory interface
    input  logic                                    upd_rd_en,
    input  logic [MULTIPUMP_FACTOR*CAM_DEPTH-1:0]   upd_wdata,
    output logic [MULTIPUMP_FACTOR*CAM_DEPTH-1:0]   upd_rdata
);
 
logic [CAM_DEPTH-1:0]                       cam_wdata;
logic [CAM_DEPTH-1:0]                       upd_wdata_arr   [0:MULTIPUMP_FACTOR-1];           
logic [CAM_DEPTH-1:0]                       cam_rdata_out;
logic [CAM_DEPTH-1:0]                       cam_rdata_mux;
logic [CAM_DEPTH-1:0]                       and_acl;
logic [$clog2(MULTIPUMP_FACTOR)-1:0]        p_mod_rd_cnt;
logic [$clog2(MULTIPUMP_FACTOR)-1:0]        p_mod_wr_cnt;
logic [(MULTIPUMP_FACTOR-1)*CAM_DEPTH-1:0]  rdata_acl;

bram_unit #(
    .BRAM_DEPTH(BRAM_DEPTH),
    .BRAM_WIDTH(BRAM_WIDTH)
) i_bram_unit
(
    .bram_clk(clk),
    .bram_addr(cam_addr),
    .bram_chip_en(cam_chip_en),
    .bram_wr_en(cam_wr_en),
    .bram_wdata(cam_wdata),
    .bram_mask('1),
    .bram_rst('b0),
    .bram_reg_en('b0),
    .bram_rdata(cam_rdata_out)
);

//------------------------- AND accumulator for compare operation --------------------------//
always_ff @(posedge clk or negedge sys_rstn) begin
    if (~sys_rstn) p_mod_rd_cnt <= 'b0;
    else if (rst_cmd) p_mod_rd_cnt <= 'b0;
    else if (~cam_wr_en) p_mod_rd_cnt <= p_mod_rd_cnt + 'b1;
end

assign ca
m_rdata_mux = (p_mod_rd_cnt == 'b1 && cam_chip_en) ? cam_rdata_out : (and_acl & cam_rdata_out);
always_ff @(posedge clk or negedge sys_rstn) begin
    if (~sys_rstn) and_acl <= 'b0;
    else if (rst_cmd) and_acl <= 'b0;
    else if (cam_compare) and_acl <= cam_rdata_mux;
end

assign cam_rdata = cam_rdata_mux;


//----------------------------- Update table ----------------------------//
always_ff @(posedge clk or negedge sys_rstn) begin
    if (~sys_rstn) p_mod_wr_cnt <= 'b0;
    else if (rst_cmd) p_mod_wr_cnt <= 'b0;
    else if (cam_wr_en) p_mod_wr_cnt <= p_mod_wr_cnt + 'b1;
end

always_comb begin
    for (int dsel = 0; dsel < MULTIPUMP_FACTOR; dsel = dsel + 1) begin
        upd_wdata_arr[dsel] = upd_wdata[dsel*CAM_DEPTH +: CAM_DEPTH];
        cam_wdata = upd_wdata_arr[p_mod_wr_cnt];                       
    end    
end

generate
    if (MULTIPUMP_FACTOR == 2) begin
        always_ff @(posedge clk or negedge sys_rstn) begin
            if (~sys_rstn) rdata_acl <= 'b0;
            else if (rst_cmd) rdata_acl <= 'b0;
            else if (upd_rd_en) rdata_acl <= cam_rdata_out;
        end
    end

    else if (MULTIPUMP_FACTOR > 2 && MULTIPUMP_FACTOR % 2 == 0) begin
        always_ff @(posedge clk or negedge sys_rstn) begin
            if (~sys_rstn) rdata_acl <= 'b0;
            else if (rst_cmd) rdata_acl <= 'b0;
            else if (upd_rd_en) rdata_acl <= {cam_rdata_out,rdata_acl[(MULTIPUMP_FACTOR-1)*CAM_DEPTH-1:CAM_DEPTH]};
        end
    end
endgenerate

assign upd_rdata = {cam_rdata_out, rdata_acl};

endmodule