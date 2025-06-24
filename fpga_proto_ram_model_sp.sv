module fpga_proto_ram_model_sp
#(
    parameter  ADDR_WIDTH     = 9,
    parameter  RAM_DEPTH      = 2**ADDR_WIDTH, // memory size (Words)
    parameter  DATA_WIDTH     = 72,
    parameter  MASK_WIDTH     = 72,
    parameter  MODE           = "NO_CHANGE",   // Select "WRITE_FIRST"/"READ_FIRST"/"NO_CHANGE"
    parameter  PERFORMANCE    = "LOW_LATENCY"  // Select "HIGH_PERFORMANCE" or "LOW_LATENCY"
)
(
    input                            clk,      // Clock
    input         [ADDR_WIDTH-1 : 0] addr,     // Address
    input                            chip_en,  // Chip-enable  (active-HIGH)
    input                            wr_en,    // Write-enable (active-HIGH)
    input         [DATA_WIDTH-1 : 0] wdata,    // Data inputs
    input         [MASK_WIDTH-1 : 0] mask,     // Write-mask   (active-HIGH)
    input                            rst,      // Data output reset (does not affect memory contents) (active-HIGH)
    input                            reg_en,   // Data output register enable (HIGH_PERFORMANCE) (active-HIGH)
    output logic  [DATA_WIDTH-1 : 0] rdata     // Data output
);

  localparam NUM_LANES      = MASK_WIDTH;
  localparam LANE_WIDTH     = DATA_WIDTH/NUM_LANES;


  `define FPGA_VIVADO_SYN

  `ifdef FPGA_VIVADO_SYN
      (* ram_style="block" *)
      reg [DATA_WIDTH-1:0] ram [RAM_DEPTH-1:0];

  `elsif FPGA_SYNOPSYS_SYN
      reg [DATA_WIDTH-1:0] ram [RAM_DEPTH-1:0] /* synthesis syn_ramstyle="block_ram"*/;

  `else
      reg [DATA_WIDTH-1:0] ram [RAM_DEPTH-1:0];

  `endif

  logic [DATA_WIDTH-1 : 0] ram_dout;
  logic [MASK_WIDTH-1 : 0] mask_real;

  // reset to zero for simulation
  initial begin
    for (int i = 0; i < RAM_DEPTH; i = i + 1) begin
        ram[i] <= 'b0;
    end
  end  

generate begin

    // WDATA & DOUT logic
    for (genvar lane = 0; lane < NUM_LANES; lane = lane+1) begin : FOR_EACH_LANE

        //assign mask_real[lane] = (MODE=="NO_CHANGE") ? wr_en : wr_en & mask[lane]; //duct tape    // Warning [Synth 8-6841]
        assign mask_real[lane] = wr_en;

        if (MODE == "WRITE_FIRST") begin : WRITE_FIRST_MODE_BLK

            always @(posedge clk) begin : ALWAYS_EACH_LANE
                if (chip_en) begin : CHIP_EN

                    if (mask_real[lane]) begin : WR_EN
                        ram[addr] [lane*LANE_WIDTH+:LANE_WIDTH] <= wdata[lane*LANE_WIDTH+:LANE_WIDTH];
                        ram_dout  [lane*LANE_WIDTH+:LANE_WIDTH] <= wdata[lane*LANE_WIDTH+:LANE_WIDTH];
                    end : WR_EN
                    else
                        ram_dout  [lane*LANE_WIDTH+:LANE_WIDTH] <= ram[addr][lane*LANE_WIDTH+:LANE_WIDTH];
                    
                end  : CHIP_EN        
            end : ALWAYS_EACH_LANE
        
        end : WRITE_FIRST_MODE_BLK

        if (MODE == "READ_FIRST") begin : READ_FIRST_MODE_BLK

            always @(posedge clk) begin : ALWAYS_EACH_LANE
                if (chip_en) begin : CHIP_EN
                    
                    if (mask_real[lane]) begin : WR_EN
                        ram[addr] [lane*LANE_WIDTH+:LANE_WIDTH] <= wdata[lane*LANE_WIDTH+:LANE_WIDTH];
                    end : WR_EN
                
                    ram_dout  [lane*LANE_WIDTH+:LANE_WIDTH] <= ram[addr][lane*LANE_WIDTH+:LANE_WIDTH];
                
                end  : CHIP_EN        
            end : ALWAYS_EACH_LANE

        end : READ_FIRST_MODE_BLK

        if (MODE == "NO_CHANGE") begin : NO_CHANGE_MODE_BLK

            always @(posedge clk) begin : ALWAYS_EACH_LANE
                if (chip_en) begin : CHIP_EN

                    if (mask_real[lane]) begin : WR_EN
                        ram[addr] [lane*LANE_WIDTH+:LANE_WIDTH] <= wdata[lane*LANE_WIDTH+:LANE_WIDTH];
                    end : WR_EN
                    else
                        ram_dout  [lane*LANE_WIDTH+:LANE_WIDTH] <= ram[addr][lane*LANE_WIDTH+:LANE_WIDTH];
                    
                end  : CHIP_EN
            end : ALWAYS_EACH_LANE

        end : NO_CHANGE_MODE_BLK

    end : FOR_EACH_LANE


    // RDATA logic
    if (PERFORMANCE == "LOW_LATENCY") begin : NO_OUTPUT_REGISTER

        assign rdata = ram_dout;

    end : NO_OUTPUT_REGISTER

     // The following is a 2 clock cycle read latency with improve clock-to-out timing
    else begin : OUTPUT_REGISTER

        always @(posedge clk) begin
            if      (rst   )  rdata <= '0;
            else if (reg_en)  rdata <= ram_dout;
        end

    end : OUTPUT_REGISTER

end endgenerate


endmodule // fpga_proto_ram_model_sp