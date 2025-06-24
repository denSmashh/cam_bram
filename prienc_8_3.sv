module prienc_8_3
(
    input  logic [7:0] req,
    output logic [2:0] lsb_priority
);
    
always_comb begin
    casex (req)
        8'bxxxxxxx1 : lsb_priority = 3'b000;
        8'bxxxxxx10 : lsb_priority = 3'b001;
        8'bxxxxx100 : lsb_priority = 3'b010;
        8'bxxxx1000 : lsb_priority = 3'b011;
        8'bxxx10000 : lsb_priority = 3'b100;
        8'bxx100000 : lsb_priority = 3'b101;
        8'bx1000000 : lsb_priority = 3'b110;
        8'b10000000 : lsb_priority = 3'b111;
            default : lsb_priority = 3'b000;
    endcase
end
    
endmodule