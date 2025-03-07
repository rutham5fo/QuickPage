`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.02.2025 00:09:35
// Design Name: 
// Module Name: switch_up
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


module switch_up #(
        parameter PIPELINE          = 0,
        parameter INPUTS            = 128,
        parameter NODES             = INPUTS/2,
        parameter DATA_W            = 7,
        parameter STAGES            = $clog2(INPUTS)
    )(
        input wire                          i_clk,
        input wire                          i_reset,
        input wire  [DATA_W*INPUTS-1:0]     i_data,
        input wire  [NODES*STAGES-1:0]      i_scb,
        
        output wire [DATA_W*INPUTS-1:0]     o_data
    );
    
    wire    [DATA_W*INPUTS-1:0]         stage_data_out[0:STAGES-1];
    wire    [NODES-1:0]                 stage_scb_unpkd[0:STAGES-1];
          
    genvar i;
    
    assign o_data = stage_data_out[0];
    
    generate
        for (i = 0; i < STAGES; i = i+1) begin      :   gen_unpkd_scb
            assign stage_scb_unpkd[i] = i_scb[i*NODES +: NODES];
        end
    endgenerate
    
    generate
        for (i = 0; i < STAGES; i = i+1) begin      :   gen_butt_stage
            if (i == STAGES-1) begin
                switch_ustage #(
                    .PIPELINE(PIPELINE),
                    .STAGE_NUM(i),
                    .INPUTS(INPUTS),
                    .NODES(NODES),
                    .DATA_W(DATA_W),
                    .STAGES(STAGES)
                ) switch_ustage_i (
                    .i_clk(i_clk),
                    .i_reset(i_reset),
                    .i_data(i_data),
                    .i_scb(stage_scb_unpkd[i]),
                    
                    .o_data(stage_data_out[i])
                );
            end
            else begin
                switch_ustage #(
                    .PIPELINE(PIPELINE),
                    .STAGE_NUM(i),
                    .INPUTS(INPUTS),
                    .NODES(NODES),
                    .DATA_W(DATA_W),
                    .STAGES(STAGES)
                ) switch_ustage_i (
                    .i_clk(i_clk),
                    .i_reset(i_reset),
                    .i_data(stage_data_out[i+1]),
                    .i_scb(stage_scb_unpkd[i]),
                    
                    .o_data(stage_data_out[i])
                );
            end
        end
    endgenerate
    
endmodule
