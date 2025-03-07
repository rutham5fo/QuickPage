`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 18.02.2025 13:00:54
// Design Name: 
// Module Name: switch_dstage
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


module switch_dstage #(
        parameter PIPELINE          = 1,
        parameter STAGE_NUM         = 0,
        parameter INPUTS            = 32,
        parameter NODES             = INPUTS/2,
        parameter DATA_W            = 1,
        parameter STAGES            = $clog2(INPUTS)
    )(
        input wire                      i_clk,
        input wire                      i_reset,
        input wire  [DATA_W*INPUTS-1:0] i_data,
        input wire  [NODES-1:0]         i_scb,
        
        output wire [DATA_W*INPUTS-1:0] o_data
    );
    
    localparam SPLIT            = (STAGE_NUM < STAGES-1) ? 2**(STAGE_NUM+1) : 2**STAGE_NUM;
    
    wire    [DATA_W-1:0]        data_in_unpkd[0:INPUTS-1];
    wire    [DATA_W-1:0]        r_data_out[0:INPUTS-1];
    wire    [DATA_W-1:0]        data_out_unpkd[0:INPUTS-1];
    
    genvar i;
    
    // Packed to unpacked
    generate
        for (i = 0; i < INPUTS; i = i+1) begin
            assign data_in_unpkd[i] = i_data[i*DATA_W +: DATA_W];
            assign o_data[i*DATA_W +: DATA_W] = data_out_unpkd[i];
        end
    endgenerate
    
    // Stage output mapping
    generate      
        if (STAGE_NUM < STAGES-1) begin
            for (i = 0; i < INPUTS; i = i+1) begin
                if ((i/SPLIT)%2 == 0) begin
                    if (i%2 == 0) begin
                        assign data_out_unpkd[i] = r_data_out[i];
                    end
                    else begin
                        assign data_out_unpkd[i] = r_data_out[i+SPLIT-1];
                    end
                end
                else begin
                    if (i%2 == 0) begin
                        assign data_out_unpkd[i] = r_data_out[i-SPLIT+1];
                    end
                    else begin
                        assign data_out_unpkd[i] = r_data_out[i];
                    end
                end
            end
        end
        else begin
            for (i = 0; i < INPUTS; i = i+1) begin
                if (i < SPLIT) begin
                    assign data_out_unpkd[i] = r_data_out[2*i];
                end
                else begin
                    assign data_out_unpkd[i] = r_data_out[2*(i-SPLIT)+1];
                end
            end
        end
    endgenerate
    
    // Node generation
    generate
        for (i = 0; i < NODES; i = i+1) begin
            switch_node #(
                .PIPELINE(PIPELINE),
                .INPUTS(INPUTS),
                .DATA_W(DATA_W)
            ) switch_node_i (
                .i_clk(i_clk),
                .i_reset(i_reset),
                .i_data_0(data_in_unpkd[2*i]),
                .i_data_1(data_in_unpkd[2*i+1]),
                .i_scb(i_scb[i]),
                
                .o_data_0(r_data_out[2*i]),
                .o_data_1(r_data_out[2*i+1])
            );
        end
    endgenerate
    
endmodule
