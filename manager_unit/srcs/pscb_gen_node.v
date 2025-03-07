`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 18.02.2025 19:10:07
// Design Name: 
// Module Name: pscb_gen_node
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module pscb_gen_node (
        input wire                      i_scb,
        input wire                      i_flag_0,
        input wire                      i_flag_1,
        
        output wire                     o_pass,
        output wire                     o_flag_0,
        output wire                     o_flag_1
    );
    
    assign o_pass = (i_flag_0 || i_flag_1) ? 1'b1 : 1'b0;
    assign o_flag_0 = (i_scb) ? i_flag_1 : i_flag_0;
    assign o_flag_1 = (i_scb) ? i_flag_0 : i_flag_1;
    
endmodule