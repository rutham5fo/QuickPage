`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 18.02.2025 18:24:33
// Design Name: 
// Module Name: rscb_gen_node
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

/*
module rscb_gen_node #(
        parameter STAGE                 = 6,
        parameter MAP_W                 = 1 << STAGE,
        parameter DATA_W                = 8
    )(
        input wire  [DATA_W-1:0]        i_rotate,
        
        output wire [MAP_W-1:0]         o_scb
    );
    
    //-----------------------------------------------------------------
    //  The template for pmap is Big endian -> 0, 1, 2, 3, ..., MSB
    //  Shift rights are specified according to big endian format
    //  But, the shifters are little endian, hence simply switch the
    //  right shift to a left shift to reflect the endianess.
    //-----------------------------------------------------------------
    
    localparam TRUNC_W              = $clog2(MAP_W)+1;
    //localparam SHFTR_INIT           = {{MAP_W{1'b1}}, {MAP_W{1'b0}}};
    localparam SHFTR_INIT           = {{MAP_W{1'b0}}, {MAP_W{1'b1}}};
    
    wire    [TRUNC_W-1:0]           w_rot_trunc;
    wire    [2*MAP_W-1:0]           w_shftr;
    
    assign w_rot_trunc = i_rotate[0 +: TRUNC_W];
    // Perform shift
    //assign w_shftr = SHFTR_INIT >> w_shft_val_trunc;
    assign w_shftr = SHFTR_INIT << w_rot_trunc;
    // Assign scb
    //assign o_scb = w_shftr[0 +: MAP_W];
    assign o_scb = w_shftr[MAP_W +: MAP_W];
    
endmodule
*/

module rscb_gen_node #(
        parameter STAGE                 = 6,
        parameter MAP_W                 = 1 << STAGE,
        parameter DATA_W                = 8
    )(
        input wire  [MAP_W-1:0]         i_scb,
        input wire  [DATA_W-1:0]        i_rotate,
        
        output wire [MAP_W-1:0]         o_scb
    );
    
    /*
        The template for pmap is Big endian -> 0, 1, 2, 3, ..., MSB
        Shift rights are specified according to big endian format
        But, the shifters are little endian, hence simply switch the
        right shift to a left shift to reflect the endianess.
    */
    localparam TRUNC_W              = $clog2(MAP_W)+1;
    //localparam SHFTR_INIT           = {{MAP_W{1'b0}}, {MAP_W{1'b1}}};
    
    wire    [TRUNC_W-1:0]           w_rot_trunc;
    wire    [2*MAP_W-1:0]           w_shftr_init;
    wire    [2*MAP_W-1:0]           w_shftr;
    
    assign w_rot_trunc = i_rotate[0 +: TRUNC_W];
    // Perform shift
    assign w_shftr_init = {i_scb, ~i_scb};
    assign w_shftr = w_shftr_init << w_rot_trunc;
    // Assign scb
    assign o_scb = w_shftr[MAP_W +: MAP_W];
    
endmodule