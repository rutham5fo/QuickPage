`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 18.02.2025 18:26:16
// Design Name: 
// Module Name: rscb_gen_tree
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
module rscb_gen_tree #(
        parameter REGISTER          = 0,
        parameter BITMAP            = 128,
        parameter STAGES            = $clog2(BITMAP),
        parameter DATA_W            = 8,
        parameter MAX_NODES         = BITMAP >> 1
    )(
        input wire                          i_clk,
        input wire                          i_reset,
        input wire  [DATA_W-1:0]            i_rotate,
        
        output wire [MAX_NODES*STAGES-1:0]  o_scb
    );
    
    wire    [MAX_NODES-1:0]         w_scb[0:STAGES-1];
    
    genvar i;
    
    generate
        if (REGISTER) begin
            reg     [MAX_NODES-1:0]         r_scb[0:STAGES-1];
            
            integer k;
            
            for (i = 0; i < STAGES; i = i+1) begin          :   gen_outputs_regd
                assign o_scb[i*MAX_NODES +: MAX_NODES] = r_scb[i];
            end
            
            always @(posedge i_clk) begin
                for (k = 0; k < STAGES; k = k+1) begin
                    r_scb[k] <= (i_reset) ? 0 : w_scb[k];
                end
            end
        end
        else begin
            for (i = 0; i < STAGES; i = i+1) begin          :   gen_outputs
                assign o_scb[i*MAX_NODES +: MAX_NODES] = w_scb[i];
            end
        end
    endgenerate
    
    generate
        for (i = 0; i < STAGES; i = i+1) begin          :   gen_scb_stage_0
            localparam NODES        = BITMAP >> (i+1);
            localparam MAP_W        = 1 << i;
            
            rscb_gen_stage #(
                .BITMAP(BITMAP),
                .STAGE(i),
                .NODES(NODES),
                .DATA_W(DATA_W),
                .MAP_W(MAP_W)
            ) rscb_gen_stage_i (
                .i_rotate(i_rotate),
                
                .o_scb(w_scb[i])
            );
        end
    endgenerate
    
endmodule
*/

module rscb_gen_tree #(
        parameter REG_STAGE         = 0,                    // Set to STAGES+1 for unregistered output, and REG_STAGE = STAGES to register final output
        parameter BITMAP            = 128,
        parameter STAGES            = $clog2(BITMAP),
        parameter DATA_W            = 8,
        parameter MAX_NODES         = BITMAP >> 1
    )(
        input wire                          i_clk,
        input wire                          i_reset,
        input wire  [MAX_NODES*STAGES-1:0]  i_scb,
        input wire  [DATA_W-1:0]            i_rotate,
        
        output wire [MAX_NODES*STAGES-1:0]  o_scb
    );
    
    wire    [MAX_NODES-1:0]         wi_scb[0:STAGES-1];
    wire    [MAX_NODES-1:0]         wo_scb[0:STAGES-1];
    
    genvar i;
    
    //generate
    //    if (REG_STAGE == STAGES) begin
    //        reg     [MAX_NODES-1:0]         r_scb[0:STAGES-1];
    //        
    //        integer k;
    //        
    //        for (i = 0; i < STAGES; i = i+1) begin          :   gen_outputs_regd
    //            assign wi_scb[i] = i_scb[i*MAX_NODES +: MAX_NODES];
    //            assign o_scb[i*MAX_NODES +: MAX_NODES] = r_scb[i];
    //        end
    //        
    //        always @(posedge i_clk) begin
    //            for (k = 0; k < STAGES; k = k+1) begin
    //                r_scb[k] <= (i_reset) ? 0 : wo_scb[k];
    //            end
    //        end
    //    end
    //    else begin
    //        for (i = 0; i < STAGES; i = i+1) begin          :   gen_outputs
    //            assign wi_scb[i] = i_scb[i*MAX_NODES +: MAX_NODES];
    //            assign o_scb[i*MAX_NODES +: MAX_NODES] = wo_scb[i];
    //        end
    //    end
    //endgenerate
    
    generate
        for (i = 0; i < STAGES; i = i+1) begin          :   gen_outputs
            assign wi_scb[i] = i_scb[i*MAX_NODES +: MAX_NODES];
            assign o_scb[i*MAX_NODES +: MAX_NODES] = wo_scb[i];
        end
    endgenerate
    
    generate
        for (i = 0; i < STAGES; i = i+1) begin          :   gen_scb_stage_0
            localparam NODES        = BITMAP >> (i+1);
            localparam MAP_W        = 1 << i;
            
            rscb_gen_stage #(
                .REG_STAGE(REG_STAGE),
                .BITMAP(BITMAP),
                .STAGE(i),
                .NODES(NODES),
                .DATA_W(DATA_W),
                .MAP_W(MAP_W)
            ) rscb_gen_stage_i (
                .i_clk(i_clk),
                .i_reset(i_reset),
                .i_scb(wi_scb[i]),
                .i_rotate(i_rotate),
                
                .o_scb(wo_scb[i])
            );
        end
    endgenerate
    
endmodule
