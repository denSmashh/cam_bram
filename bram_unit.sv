module bram_unit 
#(
    parameter  BRAM_DEPTH = 512,
    parameter  BRAM_WIDTH = 64,
    localparam BRAM_ADDR_WIDTH = $clog2(BRAM_DEPTH)
)
(
    input  logic                        bram_clk,
    input  logic [BRAM_ADDR_WIDTH-1:0]  bram_addr,
    input  logic                        bram_chip_en,
    input  logic                        bram_wr_en,
    input  logic [BRAM_WIDTH-1:0]       bram_wdata,
    input  logic [BRAM_WIDTH-1:0]       bram_mask,
    input  logic                        bram_rst,        // only for "HIGH_PERFORMANCE" setup
    input  logic                        bram_reg_en,     // only for "HIGH_PERFORMANCE" setup
    output logic [BRAM_WIDTH-1:0]       bram_rdata
);

// 1 BRAM unit (Simple Port)
fpga_proto_ram_model_sp #(
    .ADDR_WIDTH(BRAM_ADDR_WIDTH),
    .RAM_DEPTH(BRAM_DEPTH), 
    .DATA_WIDTH(BRAM_WIDTH),
    .MASK_WIDTH(BRAM_WIDTH),
    .MODE("NO_CHANGE"),             // "WRITE_FIRST"/"READ_FIRST"/"NO_CHANGE"
    .PERFORMANCE("LOW_LATENCY")     // "HIGH_PERFORMANCE" or "LOW_LATENCY"
) i_ram_sp
(
    .clk(bram_clk),      
    .addr(bram_addr),
    .chip_en(bram_chip_en),  
    .wr_en(bram_wr_en),    
    .wdata(bram_wdata),    
    .mask(bram_mask),     
    .rst(bram_rst),      
    .reg_en(bram_reg_en),   
    .rdata(bram_rdata)     
);
    
endmodule