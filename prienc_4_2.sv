module prienc_4_2
(
    input  logic [3:0] req,
    output logic [1:0] lsb_priority
);
        
always_comb begin
    casex (req)
        4'bxxx1 : lsb_priority = 2'b00;
        4'bxx10 : lsb_priority = 2'b01;
        4'bx100 : lsb_priority = 2'b10;
        4'b1000 : lsb_priority = 2'b11;
        default : lsb_priority = 2'b00;
    endcase
end
        
endmodule