`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 18.02.2025 18:25:29
// Design Name: 
// Module Name: rscb_gen_stage
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
module rscb_gen_stage #(
        parameter BITMAP            = 128,
        parameter STAGE             = 6,
        parameter NODES             = BITMAP >> (STAGE+1),
        parameter DATA_W            = 8,
        parameter MAP_W             = 1 << STAGE
    )(
        input wire  [DATA_W-1:0]        i_rotate,
        
        output wire [NODES*MAP_W-1:0]   o_scb
    );
    
    wire    [MAP_W-1:0]             w_scb[0:NODES-1];
    
    genvar i;
    
    generate
        for (i = 0; i < NODES; i = i+1) begin           :   gen_output
            assign o_scb[i*MAP_W +: MAP_W] = w_scb[i];
        end
    endgenerate
    
    generate
        for (i = 0; i < NODES; i = i+1) begin           :   gen_rscb_nodes
            rscb_gen_node #(
                .STAGE(STAGE),
                .MAP_W(MAP_W),
                .DATA_W(DATA_W)
            ) rscb_gen_node_i (
                .i_rotate(i_rotate),
                
                .o_scb(w_scb[i])
            );
        end
    endgenerate
    
endmodule
*/

module rscb_gen_stage #(
        parameter REG_STAGE         = 6,
        parameter BITMAP            = 128,
        parameter STAGE             = 6,
        parameter NODES             = BITMAP >> (STAGE+1),
        parameter DATA_W            = 8,
        parameter MAP_W             = 1 << STAGE
    )(
        input wire                      i_clk,
        input wire                      i_reset,
        input wire  [NODES*MAP_W-1:0]   i_scb,
        input wire  [DATA_W-1:0]        i_rotate,
        
        output wire [NODES*MAP_W-1:0]   o_scb
    );
    
    wire    [MAP_W-1:0]             wi_scb[0:NODES-1];
    wire    [MAP_W-1:0]             wo_scb[0:NODES-1];
    
    genvar i;
    
    generate
        if (REG_STAGE == STAGE) begin
            reg     [MAP_W-1:0]     r_scb[0:NODES-1];
            
            integer k;
            
            for (i = 0; i < NODES; i = i+1) begin           :   gen_pkd_unpkd_regd
                assign o_scb[i*MAP_W +: MAP_W] = r_scb[i];
            end
            
            always @(posedge i_clk) begin
                for (k = 0; k < NODES; k = k+1) begin
                    r_scb[k] <= (i_reset) ? 0 : wo_scb[k];
                end
            end
        end
        else begin
            for (i = 0; i < NODES; i = i+1) begin           :   gen_pkd_unpkd
                assign o_scb[i*MAP_W +: MAP_W] = wo_scb[i];
            end
        end
    endgenerate
    
    generate
        for (i = 0; i < NODES; i = i+1) begin           :   gen_rscb_nodes
            
            assign wi_scb[i] = i_scb[i*MAP_W +: MAP_W];
            
            rscb_gen_node #(
                .STAGE(STAGE),
                .MAP_W(MAP_W),
                .DATA_W(DATA_W)
            ) rscb_gen_node_i (
                .i_scb(wi_scb[i]),
                .i_rotate(i_rotate),
                
                .o_scb(wo_scb[i])
            );
        end
    endgenerate
    
endmodule
