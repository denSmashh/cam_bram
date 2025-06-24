module cam_bram
#(
    parameter CAM_DEPTH        = 512,
    parameter CAM_WIDTH        = 32,
    parameter CAM_ADDR_WIDTH   = $clog2(CAM_DEPTH),
    parameter MULTIPUMP_FACTOR = 2
) 
(
    // System
    input  logic                      clk,            // System clk
    input  logic                      sys_rstn,       // System rstn
    input  logic                      sub_clk,        // Internal clk for search engine BRAM memory, sub_clk = MULTIPUMP_FACTOR * clk (strictly!)
    
    // Memory interface
    input  logic                      rst,
    input  logic                      chip_en,
    input  logic                      flush,
    input  logic                      write,
    input  logic                      read,   
    input  logic                      compare,
    input  logic                      valid_bit_en,
    input  logic                      dncen,
    input  logic [CAM_ADDR_WIDTH-1:0] addr,
    input  logic                      valid_bit_in,
    input  logic [CAM_WIDTH-1:0]      data_in,              
    output logic                      valid_bit_out,
    output logic [CAM_WIDTH-1:0]      data_out,
    output logic [CAM_DEPTH-1:0]      match_out,
    output logic                      rmatch_out,
    output logic                      hit,
    output logic                      multiple_hit,
    output logic [CAM_ADDR_WIDTH-1:0] hit_addr
);
    
logic                       reset_cmd; 
logic                       flush_cmd; 
logic                       wr_cmd;
logic                       rd_cmd;
logic                       cmp_cmd;
    
logic                       vb_wr;
logic                       vb_rd;
logic                       vb_rd_ff;
    
logic                       vbo_reg;
logic [CAM_DEPTH-1:0]       vb_row;
logic                       vb_curr;
    
logic                       wr_en_ram;
logic                       reg_en_ram;
logic [CAM_WIDTH-1:0]       rdata_ram;
logic [CAM_WIDTH-1:0]       wdata_ram;
logic [CAM_WIDTH-1:0]       rdata_ram_ff;
logic                       rd_cmd_ff;
    
logic [CAM_WIDTH-1:0]       key;
logic                       upd_search_table;
logic [CAM_ADDR_WIDTH-1:0]  upd_addr;
logic [CAM_WIDTH-1:0]       upd_data;
logic [CAM_WIDTH-1:0]       upd_prev_data;
logic [CAM_WIDTH-1:0]       upd_new_data;
    
logic                       hit_se;
logic                       mhit_se;
logic                       rmatch_out_se;
logic [CAM_ADDR_WIDTH-1:0]  hit_addr_se;
logic [CAM_DEPTH-1:0]       hit_out_se;

// test reg out
logic                       hit_reg_out;
logic                       mhit_reg_out;
logic [CAM_ADDR_WIDTH-1:0]  hit_addr_reg_out;

logic                       reset_cmd_1_ff;
logic [CAM_ADDR_WIDTH-1:0]  addr_ff;

    
// tcam cmd
assign reset_cmd = chip_en &   rst  & (~flush) & (~write) & (~read) & (~compare) & (~dncen) & (~valid_bit_en);
assign flush_cmd = chip_en & (~rst) &   flush  & (~write) & (~read) & (~compare);
assign wr_cmd    = chip_en & (~rst) & (~flush) &   write  & (~read) & (~compare) &   dncen;
assign rd_cmd    = chip_en & (~rst) & (~flush) & (~write) &   read  & (~compare) &   dncen;
assign cmp_cmd   = chip_en & (~rst) & (~flush) & (~write) & (~read) &   compare;
    
// valid bit cmd
assign vb_wr     = chip_en & (~rst) & (~flush) &   write  & (~read) & (~compare) & valid_bit_en;
assign vb_rd     = chip_en & (~rst) & (~flush) & (~write) &   read  & (~compare) & valid_bit_en;

//---------------------------- Valid Bit read-write -------------------------//
always_ff @(posedge clk or negedge sys_rstn) begin
    if (~sys_rstn) vb_row <= 'b0;
    else if (reset_cmd | flush_cmd) vb_row <= 'b0;
    else if (vb_wr) vb_row[addr] <= valid_bit_in;
end

always_ff @(posedge clk or negedge sys_rstn) begin
    if (~sys_rstn) vb_rd_ff <= 'b0;
    else if (reset_cmd_1_ff) vb_rd_ff <= 'b0;
    else vb_rd_ff <= vb_rd;
end

always_ff @(posedge clk or negedge sys_rstn) begin
    if (~sys_rstn) addr_ff <= 'b0;
    else if (reset_cmd_1_ff) addr_ff <= 'b0;
    else addr_ff <= addr;
end

always_ff @(posedge clk or negedge sys_rstn) begin
    if (~sys_rstn) vbo_reg <= 'b0;
    else if (reset_cmd_1_ff) vbo_reg <= 'b0;
    else if (vb_rd_ff) vbo_reg <= vb_row[addr_ff];
end

assign valid_bit_out = vbo_reg;
    
//---------------------------- Data read-write -------------------------//
assign wdata_ram = data_in;
assign wr_en_ram = wr_cmd;

fpga_proto_ram_model_sp #(
    .ADDR_WIDTH(CAM_ADDR_WIDTH),
    .RAM_DEPTH(CAM_DEPTH),
    .DATA_WIDTH(CAM_WIDTH),
    .MASK_WIDTH(CAM_WIDTH),
    .MODE("READ_FIRST"),
    .PERFORMANCE("LOW_LATENCY")
) data_ram_sp
(
    .clk(clk),
    .addr(addr),
    .chip_en('b1),
    .wr_en(wr_en_ram),
    .wdata(wdata_ram),
    .mask('1),
    .rst('b0),
    .reg_en('b0),
    .rdata(rdata_ram)
);

always_ff @(posedge clk or negedge sys_rstn) begin
    if (~sys_rstn) rd_cmd_ff <= 'b0;
    else if (reset_cmd_1_ff) rd_cmd_ff <= 'b0;
    else rd_cmd_ff <= rd_cmd;
end
   
always_ff @(posedge clk or negedge sys_rstn) begin
    if (~sys_rstn) rdata_ram_ff <= 'b0;
    else if (reset_cmd_1_ff) rdata_ram_ff <= 'b0;
    else if (rd_cmd_ff) rdata_ram_ff <= rdata_ram;
end

assign data_out = rdata_ram_ff;

//---------------------------- Search and Update -------------------------//
assign upd_search_table = wr_cmd;
assign upd_addr = addr;
assign upd_prev_data = rdata_ram;
assign upd_new_data = data_in;
assign key = data_in;
     
search_engine #(
    .CAM_DEPTH(CAM_DEPTH),
    .CAM_WIDTH(CAM_WIDTH),
    .CAM_ADDR_WIDTH(CAM_ADDR_WIDTH),
    .MULTIPUMP_FACTOR(2)
) i_search_engine
(
    .sys_clk(clk),
    .sys_rstn(sys_rstn),
    .sub_clk(sub_clk),
    .rst_cmd(reset_cmd),
    .upd_tbl(upd_search_table),
    .upd_addr(upd_addr),
    .upd_prev_data(upd_prev_data),
    .upd_new_data(upd_new_data),
    .valid_bit_row(vb_row),
    .compare(cmp_cmd),
    .key(key),
    .hit(hit_se),
    .mhit(mhit_se),
    .hit_addr(hit_addr_se),
    .adj_hit(rmatch_out_se),
    .hit_out(hit_out_se)
);

always_ff @(posedge clk or negedge sys_rstn) begin
    if (~sys_rstn) reset_cmd_1_ff <= 'b0;
    else reset_cmd_1_ff <= reset_cmd;
end

always_ff @(posedge clk or negedge sys_rstn) begin
    if (~sys_rstn) begin
        hit_reg_out      <= 'b0;
        mhit_reg_out     <= 'b0;
        hit_addr_reg_out <= 'b0;
    end else begin
        hit_reg_out      <= hit_se;
        mhit_reg_out     <= mhit_se;
        hit_addr_reg_out <= hit_addr_se;
    end
end

assign hit = hit_reg_out;
assign multiple_hit = mhit_reg_out;
assign hit_addr = hit_addr_reg_out;

assign match_out = hit_out_se;

assign rmatch_out = rmatch_out_se;

endmodule