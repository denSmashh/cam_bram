// Module perform search in one clock cycle and update values in rows.
// Implement multipumping multiported BRAM technique.
//
// Search engine consists of BRAM units (36K). Units are combined into matrix. 
// 1 BRAM unit (D x W) ----> TCAM (W x P*log2(D/P))
// 1 BRAM unit  512x64 ----> TCAM 64x16
//
// sub_clk = MULTIPUMP_FACTOR * sys_clk (strictly!)

module search_engine
#(
    parameter       CAM_DEPTH        = 512,
    parameter       CAM_WIDTH        = 32,
    parameter       CAM_ADDR_WIDTH   = $clog2(CAM_DEPTH),
    parameter int   MULTIPUMP_FACTOR = 2
)
(  
    // System
    input  logic                        sys_clk,
    input  logic                        sys_rstn,
    input  logic                        sub_clk,

    // Update interface
    input  logic                        upd_tbl,
    input  logic [CAM_ADDR_WIDTH-1:0]   upd_addr,
    input  logic [CAM_WIDTH-1:0]        upd_prev_data,
    input  logic [CAM_WIDTH-1:0]        upd_new_data,
    
    // Search interface
    input  logic                        rst_cmd,
    input  logic [CAM_DEPTH-1:0]        valid_bit_row,
    input  logic                        compare,
    input  logic [CAM_WIDTH-1:0]        key,
    output logic                        hit,
    output logic                        mhit,
    output logic [CAM_ADDR_WIDTH-1:0]   hit_addr,
    output logic [CAM_DEPTH-1:0]        hit_out
);
 
// Parameters 1 BRAM unit
localparam BRAM_DEPTH = 512;
localparam BRAM_WIDTH = 64;
localparam BRAM_ADDR  = $clog2(BRAM_DEPTH);

// Parameters 1 CAM unit based on BRAM
localparam EMULATE_CAM_DEPTH         = BRAM_WIDTH;
localparam EMULATE_CAM_WIDTH         = MULTIPUMP_FACTOR * $clog2(BRAM_DEPTH / MULTIPUMP_FACTOR);
localparam EMULATE_CAM_ADDR_WIDTH    = $clog2(EMULATE_CAM_DEPTH);
localparam EMULATE_CAM_SHIFT_ADDR    = $clog2(BRAM_DEPTH / MULTIPUMP_FACTOR);
localparam EMULATE_CAM_SET_ADDR_BITS = $clog2(EMULATE_CAM_DEPTH);

// Partition parameters
localparam ROWS    = (CAM_DEPTH / EMULATE_CAM_DEPTH) + ((CAM_DEPTH % EMULATE_CAM_DEPTH != 0) ? 1 : 0);
localparam COLUMNS = (CAM_WIDTH / EMULATE_CAM_WIDTH) + ((CAM_WIDTH % EMULATE_CAM_WIDTH != 0) ? 1 : 0);

// Explicit width parameter
localparam EMULATE_CAM_WIDTH_NOT_USED_BITS = EMULATE_CAM_WIDTH*COLUMNS - CAM_WIDTH;

// Width mhit_inter_row_sum signals
localparam MHIT_INTER_ROW_SUM_1_WIDTH = (ROWS / 2)   + ((ROWS % 2 != 0)   ? 1 : 0);
localparam MHIT_INTER_ROW_SUM_2_WIDTH = (ROWS / 4)   + ((ROWS % 4 != 0)   ? 1 : 0);
localparam MHIT_INTER_ROW_SUM_3_WIDTH = (ROWS / 8)   + ((ROWS % 8 != 0)   ? 1 : 0);
localparam MHIT_INTER_ROW_SUM_4_WIDTH = (ROWS / 16)  + ((ROWS % 16 != 0)  ? 1 : 0);
localparam MHIT_INTER_ROW_SUM_5_WIDTH = (ROWS / 32)  + ((ROWS % 32 != 0)  ? 1 : 0);
localparam MHIT_INTER_ROW_SUM_6_WIDTH = (ROWS / 64)  + ((ROWS % 64 != 0)  ? 1 : 0);
localparam MHIT_INTER_ROW_SUM_7_WIDTH = (ROWS / 128) + ((ROWS % 128 != 0) ? 1 : 0);

logic [ROWS-1:0]                                cam_chip_en;
logic [ROWS-1:0]                                cam_wr_en;
logic [ROWS-1:0]                                cam_upd_rd_en;
logic [BRAM_ADDR-1:0]                           cam_addr            [0:COLUMNS-1];
logic [EMULATE_CAM_WIDTH*COLUMNS-1:0]           cam_addr_mux;
logic [BRAM_WIDTH-1:0]                          cam_rdata           [0:ROWS-1][0:COLUMNS-1];
logic [MULTIPUMP_FACTOR*BRAM_WIDTH-1:0]         upd_cam_wdata       [0:COLUMNS-1];

logic [$clog2(MULTIPUMP_FACTOR)-1:0]            multipump_cnt;
logic [EMULATE_CAM_ADDR_WIDTH-1:0]              cam_key             [0:COLUMNS-1];
logic [EMULATE_CAM_WIDTH-1:0]                   shift_reg_column    [0:COLUMNS-1];
logic [EMULATE_CAM_WIDTH-1:0]                   first_shift_column  [0:COLUMNS-1];
logic [EMULATE_CAM_WIDTH-1:0]                   cam_addr_lsb        [0:COLUMNS-1];

logic                                           compare_ff;
logic                                           rst_cmd_ff;
logic [CAM_ADDR_WIDTH-1:0]                      upd_addr_ff;
logic [EMULATE_CAM_WIDTH*COLUMNS-1:0]           upd_new_data_ff;
logic [EMULATE_CAM_WIDTH*COLUMNS-1:0]           upd_prev_data_ff;
logic [COLUMNS*MULTIPUMP_FACTOR-1:0]            upd_equal_data;
logic [MULTIPUMP_FACTOR-1:0]                    upd_equal_data_unp  [0:COLUMNS-1];

logic [ROWS-1:0]                                upd_sel_row;
logic [ROWS-1:0]                                upd_wr_en_row;
logic [ROWS-1:0]                                upd_rd_en_row;
logic [$clog2(ROWS)-1:0]                        cam_row_rd_sel;

logic [BRAM_WIDTH*MULTIPUMP_FACTOR-1:0]         upd_cam_rdata       [0:ROWS-1][0:COLUMNS-1];
logic [EMULATE_CAM_DEPTH*MULTIPUMP_FACTOR-1:0]  upd_new_rd_data     [0:COLUMNS-1];
logic [EMULATE_CAM_DEPTH*MULTIPUMP_FACTOR-1:0]  upd_prev_rd_data    [0:COLUMNS-1];
logic [EMULATE_CAM_DEPTH*MULTIPUMP_FACTOR-1:0]  upd_new_wr_data     [0:COLUMNS-1];
logic [EMULATE_CAM_DEPTH*MULTIPUMP_FACTOR-1:0]  upd_prev_wr_data    [0:COLUMNS-1];
logic [EMULATE_CAM_DEPTH*MULTIPUMP_FACTOR-1:0]  cam_sel_rd_data     [0:COLUMNS-1];

logic [EMULATE_CAM_DEPTH-1:0]                   and_row_no_vld      [0:ROWS-1];
logic [EMULATE_CAM_DEPTH-1:0]                   and_row             [0:ROWS-1];
logic [EMULATE_CAM_ADDR_WIDTH-1:0]              prienc_row          [0:ROWS-1];
logic [ROWS-1:0]                                match_row_oh;
logic [$clog2(ROWS)-1:0]                        match_row_bin;
logic [EMULATE_CAM_ADDR_WIDTH-1:0]              match_addr_mux;

logic [1:0]                                     mhit_sum1           [0:ROWS-1][EMULATE_CAM_DEPTH/2-1:0];
logic [2:0]                                     mhit_sum2           [0:ROWS-1][EMULATE_CAM_DEPTH/4-1:0];
logic [3:0]                                     mhit_sum3           [0:ROWS-1][EMULATE_CAM_DEPTH/8-1:0];
logic [4:0]                                     mhit_sum4           [0:ROWS-1][EMULATE_CAM_DEPTH/16-1:0];
logic [5:0]                                     mhit_sum5           [0:ROWS-1][EMULATE_CAM_DEPTH/32-1:0];
logic [6:0]                                     mhit_sum6           [0:ROWS-1];
logic [0:ROWS-1]                                mhit_row;

logic [1:0]                                     mhit_inter_row_sum1 [MHIT_INTER_ROW_SUM_1_WIDTH-1:0];
logic [2:0]                                     mhit_inter_row_sum2 [MHIT_INTER_ROW_SUM_2_WIDTH-1:0];
logic [3:0]                                     mhit_inter_row_sum3 [MHIT_INTER_ROW_SUM_3_WIDTH-1:0];
logic [4:0]                                     mhit_inter_row_sum4 [MHIT_INTER_ROW_SUM_4_WIDTH-1:0];
logic [5:0]                                     mhit_inter_row_sum5 [MHIT_INTER_ROW_SUM_5_WIDTH-1:0];
logic [6:0]                                     mhit_inter_row_sum6 [MHIT_INTER_ROW_SUM_6_WIDTH-1:0];
logic [7:0]                                     mhit_inter_row_sum7 [MHIT_INTER_ROW_SUM_7_WIDTH-1:0];
logic                                           mhit_inter_row;

logic                                           hit_comb_out;
logic                                           mhit_comb_out;
logic [CAM_ADDR_WIDTH-1:0]                      hit_addr_comb_out;
logic [CAM_DEPTH-1:0]                           hit_out_comb_out;
logic                                           hit_ff;
logic                                           mhit_ff;
logic [CAM_ADDR_WIDTH-1:0]                      hit_addr_ff;
logic [CAM_DEPTH-1:0]                           hit_out_ff;


//---------------------------- Update search table state machine -------------------------//
typedef enum logic [2:0] {  IDLE,
                            READ_NEW_ADDR,
                            WRITE_NEW_ADDR,
                            READ_PREV_ADDR,
                            WRITE_PREV_ADDR } state_t;

state_t state;
state_t next_state;

always_ff @(posedge sys_clk or negedge sys_rstn) begin
    if (~sys_rstn) state <= IDLE;
    else if (rst_cmd) state <= IDLE;
    else state <= next_state;
end

always_comb begin
    case (state)
        IDLE : begin
            upd_wr_en_row = 'b0;
            upd_rd_en_row = 'b0;          
            for (int col = 0; col < COLUMNS; col = col + 1) begin
                upd_prev_wr_data[col] = 'b0;
                upd_new_wr_data[col] = 'b0;    
            end      
            if (upd_tbl) next_state = READ_NEW_ADDR;
            else         next_state = IDLE;
        end
        
        READ_NEW_ADDR : begin
            upd_wr_en_row = 'b0;
            upd_rd_en_row = upd_sel_row;
            for (int col = 0; col < COLUMNS; col = col + 1) begin
                upd_prev_wr_data[col] = 'b0;
                upd_new_wr_data[col] = 'b0;
            end
            next_state = WRITE_NEW_ADDR;
        end
        
        WRITE_NEW_ADDR : begin
            upd_wr_en_row = upd_sel_row;
            upd_rd_en_row = 'b0;
            for (int col = 0; col < COLUMNS; col = col + 1) begin
                upd_new_rd_data[col] = cam_sel_rd_data[col];
                upd_prev_wr_data[col] = 'b0;
            end  
            for (int col = 0; col < COLUMNS; col = col + 1) begin
                for (int mem_req = 0; mem_req < MULTIPUMP_FACTOR; mem_req = mem_req + 1) begin
                    upd_new_wr_data[col][mem_req*EMULATE_CAM_DEPTH +: EMULATE_CAM_DEPTH] =
                        upd_new_rd_data[col][mem_req*EMULATE_CAM_DEPTH +: EMULATE_CAM_DEPTH] | (1 << upd_addr_ff[EMULATE_CAM_SET_ADDR_BITS-1:0]);
                end
            end
            next_state = READ_PREV_ADDR;
        end
        
        READ_PREV_ADDR : begin
            upd_wr_en_row = 'b0;
            upd_rd_en_row = upd_sel_row;
            for (int col = 0; col < COLUMNS; col = col + 1) begin
                upd_prev_wr_data[col] = 'b0;
                upd_new_wr_data[col] = 'b0;
            end
            next_state = WRITE_PREV_ADDR;
        end
        
        WRITE_PREV_ADDR : begin
            upd_wr_en_row = upd_sel_row;
            upd_rd_en_row = 'b0;
            for (int col = 0; col < COLUMNS; col = col + 1) begin
                upd_prev_rd_data[col] = cam_sel_rd_data[col];
                upd_new_wr_data[col] = 'b0;
            end
            for (int col = 0; col < COLUMNS; col = col + 1) begin
                for (int mem_req = 0; mem_req < MULTIPUMP_FACTOR; mem_req = mem_req + 1) begin
                    if(upd_equal_data_unp[col][mem_req]) begin
                        upd_prev_wr_data[col][mem_req*EMULATE_CAM_DEPTH +: EMULATE_CAM_DEPTH] = 
                            upd_prev_rd_data[col][mem_req*EMULATE_CAM_DEPTH +: EMULATE_CAM_DEPTH];
                    end
                    else begin
                        upd_prev_wr_data[col][mem_req*EMULATE_CAM_DEPTH +: EMULATE_CAM_DEPTH] =
                            upd_prev_rd_data[col][mem_req*EMULATE_CAM_DEPTH +: EMULATE_CAM_DEPTH] & (~(1 << upd_addr_ff[EMULATE_CAM_SET_ADDR_BITS-1:0]));
                    end
                end
            end
            next_state = IDLE;
        end
        
        default : begin 
            next_state = IDLE;
            upd_wr_en_row = 'b0;
            upd_rd_en_row = 'b0;       
            for (int col = 0; col < COLUMNS; col = col + 1) begin
                upd_prev_wr_data[col] = 'b0;
                upd_new_wr_data[col] = 'b0;
            end
        end        
    endcase
end

always_ff @(posedge sys_clk or negedge sys_rstn) begin
    if (~sys_rstn) upd_sel_row <= 'b0;
    else if (rst_cmd) upd_sel_row <= 'b0;
    else if (state == IDLE && upd_tbl) upd_sel_row <= (1 << (upd_addr >> EMULATE_CAM_ADDR_WIDTH));
end

always_ff @(posedge sys_clk or negedge sys_rstn) begin
    if (~sys_rstn) upd_addr_ff <= 'b0;
    else if (rst_cmd) upd_addr_ff <= 'b0;
    else if (state == IDLE && upd_tbl) upd_addr_ff <= upd_addr;
end

always_ff @(posedge sys_clk or negedge sys_rstn) begin
    if (~sys_rstn) upd_new_data_ff <= 'b0;
    else if (rst_cmd) upd_new_data_ff <= 'b0;
    else if (state == IDLE && upd_tbl) upd_new_data_ff <= upd_new_data;
end

always_ff @(posedge sys_clk or negedge sys_rstn) begin
    if (~sys_rstn) upd_prev_data_ff <= 'b0;
    else if (rst_cmd) upd_prev_data_ff <= 'b0;
    else if (state == READ_NEW_ADDR) upd_prev_data_ff <= upd_prev_data;
end

always_comb begin
    for (int i = 0; i < COLUMNS * MULTIPUMP_FACTOR; i = i + 1) begin
        if ( upd_new_data_ff[i*((EMULATE_CAM_WIDTH*COLUMNS)/(COLUMNS*MULTIPUMP_FACTOR)) +: (EMULATE_CAM_WIDTH*COLUMNS)/(COLUMNS*MULTIPUMP_FACTOR)]
                                                            ==
            upd_prev_data_ff[i*((EMULATE_CAM_WIDTH*COLUMNS)/(COLUMNS*MULTIPUMP_FACTOR)) +: (EMULATE_CAM_WIDTH*COLUMNS)/(COLUMNS*MULTIPUMP_FACTOR)])
        begin
            upd_equal_data[i] = 1'b1;
        end
        else
            upd_equal_data[i] = 1'b0;
    end

    for (int col = 0; col < COLUMNS; col = col + 1) begin                                                   
        upd_equal_data_unp[col] = upd_equal_data[col*MULTIPUMP_FACTOR +: MULTIPUMP_FACTOR];
    end
end

always_ff @(posedge sys_clk or negedge sys_rstn) begin
    if (~sys_rstn) compare_ff <= 'b0;
    else if (rst_cmd) compare_ff <= 'b0;
    else compare_ff <= compare;
end

always_ff @(posedge sys_clk or negedge sys_rstn) begin
    if (~sys_rstn) rst_cmd_ff <= 'b0;
    else rst_cmd_ff <= rst_cmd;
end


//------------------------------------- Search Engine -------------------------------------//
genvar row, column, i;
generate
    
    assign cam_addr_mux = (state == IDLE && compare)                            ? {{EMULATE_CAM_WIDTH_NOT_USED_BITS{1'b0}}, key}              :
                          (state == READ_NEW_ADDR  || state == WRITE_NEW_ADDR)  ? {{EMULATE_CAM_WIDTH_NOT_USED_BITS{1'b0}}, upd_new_data_ff}  :
                          (state == READ_PREV_ADDR || state == WRITE_PREV_ADDR) ? {{EMULATE_CAM_WIDTH_NOT_USED_BITS{1'b0}}, upd_prev_data_ff} : 'b0;

    // generate lsb address value
    for (column = 0; column < COLUMNS; column = column + 1) begin
        assign first_shift_column[column] = cam_addr_mux[(column+1)*EMULATE_CAM_WIDTH-1 : column*EMULATE_CAM_WIDTH];
        
        always_ff @(posedge sub_clk or negedge sys_rstn) begin
            if (~sys_rstn) shift_reg_column[column] <= 'b0;
            else if (rst_cmd) shift_reg_column[column] <= 'b0;
            else if (multipump_cnt == 0) shift_reg_column[column] <= cam_addr_mux[(column+1)*EMULATE_CAM_WIDTH-1 : column*EMULATE_CAM_WIDTH+EMULATE_CAM_SHIFT_ADDR];
            else shift_reg_column[column] <= {{EMULATE_CAM_SHIFT_ADDR{1'b0}}, shift_reg_column[column][EMULATE_CAM_WIDTH-1 : EMULATE_CAM_SHIFT_ADDR]};
        end
        
        assign cam_addr_lsb[column] = (multipump_cnt == 0) ? first_shift_column[column] : shift_reg_column[column];
    end

    // counter mod(P), generate msb address value
    always_ff @(posedge sub_clk or negedge sys_rstn) begin
        if (~sys_rstn) multipump_cnt <= 'b0; 
        else if (rst_cmd) multipump_cnt <= 'b0;
        else multipump_cnt <= multipump_cnt + 'b1;
    end
    
    for (column = 0; column < COLUMNS; column = column + 1) begin
        assign cam_addr[column] = {multipump_cnt, cam_addr_lsb[column][EMULATE_CAM_SHIFT_ADDR-1:0]};
    end

    assign cam_chip_en = (compare_ff) ? '0 : '1;

    assign cam_wr_en = (state != IDLE) ? upd_wr_en_row : 'b0;

    assign cam_upd_rd_en = (state != IDLE) ? upd_rd_en_row : 'b0;

    for (column = 0; column < COLUMNS; column = column + 1) begin
        assign upd_cam_wdata[column] =  (state == WRITE_NEW_ADDR)  ? upd_new_wr_data[column]  :
                                        (state == WRITE_PREV_ADDR) ? upd_prev_wr_data[column] : 'b0;
    end

    // search table
    for (row = 0; row < ROWS; row = row + 1) begin
        for (column = 0; column < COLUMNS; column = column + 1) begin
            
            cam_unit #(
                .BRAM_DEPTH(BRAM_DEPTH),
                .BRAM_WIDTH(BRAM_WIDTH),
                .CAM_DEPTH(EMULATE_CAM_DEPTH),
                .MULTIPUMP_FACTOR(MULTIPUMP_FACTOR)
            ) cam_unit_gen
            (
                .clk(sub_clk),
                .sys_rstn(sys_rstn),
                .rst_cmd(rst_cmd),
                .cam_chip_en(cam_chip_en[row]),
                .cam_wr_en(cam_wr_en[row]),
                .cam_addr(cam_addr[column]),
                .cam_rdata(cam_rdata[row][column]),
                .cam_compare(compare),
                .upd_rd_en(cam_upd_rd_en[row]),
                .upd_wdata(upd_cam_wdata[column]),
                .upd_rdata(upd_cam_rdata[row][column])
            );
            
        end
    end

    // select row for update search table
    for (column = 0; column < COLUMNS; column = column + 1) begin
        assign cam_sel_rd_data[column] = upd_cam_rdata[upd_addr_ff >> EMULATE_CAM_ADDR_WIDTH][column];
    end

    // AND gate for every row
    always_comb begin
        for (int r = 0; r < ROWS; r = r + 1) begin
            and_row_no_vld[r] = '1;
            for (int c = 0; c < COLUMNS; c = c + 1) begin
                and_row_no_vld[r] = and_row_no_vld[r] & cam_rdata[r][c];
            end
        end
    end

    // Row validation
    for (row = 0; row < ROWS; row = row + 1) begin
        assign and_row[row] = and_row_no_vld[row]                                           
                              &
                              valid_bit_row[(row+1)*EMULATE_CAM_DEPTH-1:row*EMULATE_CAM_DEPTH];
    end

    // priority encoder for every row
    for (row = 0; row < ROWS; row = row + 1) begin
        prienc_lsb #(.IN_WIDTH(EMULATE_CAM_DEPTH)) i_prienc_gen (.req(and_row[row]), .prior_out(prienc_row[row]));
    end

    // overall priority encoder
    for (row = 0; row < ROWS; row = row + 1) begin
        assign match_row_oh[row] = |(and_row[row]);
    end

    prienc_lsb #(.IN_WIDTH(ROWS)) i_overall_prienc (.req(match_row_oh), .prior_out(match_row_bin));

    assign match_addr_mux = prienc_row[match_row_bin];

    // searching result
    for (row = 0; row < ROWS; row = row + 1) begin
        assign hit_out_comb_out[(row+1)*EMULATE_CAM_DEPTH-1:row*EMULATE_CAM_DEPTH] = and_row[row];
    end

    assign hit_addr_comb_out = {match_row_bin,match_addr_mux};
    assign hit_comb_out = |(match_row_oh);

    // multiple hit result
    for (row = 0; row < ROWS; row = row + 1) begin
        for (i = 0; i < EMULATE_CAM_DEPTH / 2; i = i + 1) begin
            assign mhit_sum1[row][i] = {1'b0, and_row[row][i*2]} + {1'b0, and_row[row][i*2+1]};
        end
        for (i = 0; i < EMULATE_CAM_DEPTH / 4; i = i + 1) begin
            assign mhit_sum2[row][i] = {1'b0, mhit_sum1[row][i*2]} + {1'b0, mhit_sum1[row][i*2+1]};
        end
        for (i = 0; i < EMULATE_CAM_DEPTH / 8; i = i + 1) begin
            assign mhit_sum3[row][i] = {1'b0, mhit_sum2[row][i*2]} + {1'b0, mhit_sum2[row][i*2+1]};
        end
        for (i = 0; i < EMULATE_CAM_DEPTH / 16; i = i + 1) begin
            assign mhit_sum4[row][i] = {1'b0, mhit_sum3[row][i*2]} + {1'b0, mhit_sum3[row][i*2+1]};
        end
        for (i = 0; i < EMULATE_CAM_DEPTH / 32; i = i + 1) begin
            assign mhit_sum5[row][i] = {1'b0, mhit_sum4[row][i*2]} + {1'b0, mhit_sum4[row][i*2+1]};
        end
        assign mhit_sum6[row] = {1'b0, mhit_sum5[row][0]} + {1'b0, mhit_sum5[row][1]};
        assign mhit_row[row]  = (mhit_sum6[row][6:1] != 'b0) ? 'b1 : 'b0;
    end

    if (ROWS >= 2) begin                                        // depth = 128
        for (i = 0; i < ROWS / 2; i = i + 1) begin
            assign mhit_inter_row_sum1[i] = {1'b0, match_row_oh[i*2]} + {1'b0, match_row_oh[i*2+1]};
        end
    end
    if (ROWS >= 4) begin                                        // depth = 256
        for (i = 0; i < ROWS / 4; i = i + 1) begin
            assign mhit_inter_row_sum2[i] = {1'b0, mhit_inter_row_sum1[i*2]} + {1'b0, mhit_inter_row_sum1[i*2+1]};
        end
    end
    if (ROWS >= 8) begin                                        // depth = 512
        for (i = 0; i < ROWS / 8; i = i + 1) begin
            assign mhit_inter_row_sum3[i] = {1'b0, mhit_inter_row_sum2[i*2]} + {1'b0, mhit_inter_row_sum2[i*2+1]};
        end
    end
    if (ROWS >= 16) begin                                       // depth = 1024
        for (i = 0; i < ROWS / 16; i = i + 1) begin
            assign mhit_inter_row_sum4[i] = {1'b0, mhit_inter_row_sum3[i*2]} + {1'b0, mhit_inter_row_sum3[i*2+1]};
        end
    end
    if (ROWS >= 32) begin                                       // depth = 2048
        for (i = 0; i < ROWS / 32; i = i + 1) begin
            assign mhit_inter_row_sum5[i] = {1'b0, mhit_inter_row_sum4[i*2]} + {1'b0, mhit_inter_row_sum4[i*2+1]};
        end
    end
    if (ROWS >= 64) begin                                       // depth = 4096
        for (i = 0; i < ROWS / 64; i = i + 1) begin
            assign mhit_inter_row_sum6[i] = {1'b0, mhit_inter_row_sum5[i*2]} + {1'b0, mhit_inter_row_sum5[i*2+1]};
        end
    end
    if (ROWS == 128) begin                                      // depth = 8192
        for (i = 0; i < ROWS / 128; i = i + 1) begin
            assign mhit_inter_row_sum7[i] = {1'b0, mhit_inter_row_sum6[i*2]} + {1'b0, mhit_inter_row_sum6[i*2+1]};
        end
    end
    
    if (ROWS == 128) 
        assign mhit_inter_row = (mhit_inter_row_sum7[0][7:1] != 'b0) ? 'b1 : 'b0;
    else if (ROWS >= 64)
        assign mhit_inter_row = (mhit_inter_row_sum6[0][6:1] != 'b0) ? 'b1 : 'b0;
    else if (ROWS >= 32)
        assign mhit_inter_row = (mhit_inter_row_sum5[0][5:1] != 'b0) ? 'b1 : 'b0;
    else if (ROWS >= 16)
        assign mhit_inter_row = (mhit_inter_row_sum4[0][4:1] != 'b0) ? 'b1 : 'b0;
    else if (ROWS >= 8)
        assign mhit_inter_row = (mhit_inter_row_sum3[0][3:1] != 'b0) ? 'b1 : 'b0;
    else if (ROWS >= 4)
        assign mhit_inter_row = (mhit_inter_row_sum2[0][2:1] != 'b0) ? 'b1 : 'b0;
    else if (ROWS >= 2)
        assign mhit_inter_row = (mhit_inter_row_sum1[0][1]   != 'b0) ? 'b1 : 'b0;

    assign mhit_comb_out = (|mhit_row) | mhit_inter_row;

endgenerate
    
// output registers
always_ff @(posedge sys_clk or negedge sys_rstn) begin
    if (~sys_rstn) hit_ff <= 'b0;
    else if (rst_cmd_ff) hit_ff <= 'b0;
    else if (compare_ff) hit_ff <= hit_comb_out;
end

always_ff @(posedge sys_clk or negedge sys_rstn) begin
    if (~sys_rstn) hit_addr_ff <= 'b0;
    else if (rst_cmd_ff) hit_addr_ff <= 'b0;
    else if (compare_ff) hit_addr_ff <= hit_addr_comb_out;
end

always_ff @(posedge sys_clk or negedge sys_rstn) begin
    if (~sys_rstn) mhit_ff <= 'b0;
    else if (rst_cmd_ff) mhit_ff <= 'b0;
    else if (compare_ff) mhit_ff <= mhit_comb_out;
end

// synthesis a lot of regs
always_ff @(posedge sys_clk or negedge sys_rstn) begin
    if (~sys_rstn) hit_out_ff <= 'b0;
    else if (rst_cmd) hit_out_ff <= 'b0;
    else if (compare_ff) hit_out_ff <= hit_out_comb_out;
end

assign hit      = hit_ff;
assign hit_addr = hit_addr_ff;
assign mhit     = mhit_ff;
assign hit_out  = hit_out_ff;

endmodule