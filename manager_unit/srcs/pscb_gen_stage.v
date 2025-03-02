`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 18.02.2025 19:10:51
// Design Name: 
// Module Name: pscb_gen_stage
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


module pscb_gen_stage #(
        parameter STAGE_NUM         = 0,
        parameter INPUTS            = 32,
        parameter NODES             = INPUTS/2,
        parameter STAGES            = $clog2(INPUTS)
    )(
        input wire                  i_clk,
        input wire                  i_reset,
        input wire  [NODES-1:0]     i_scb,
        input wire  [INPUTS-1:0]    i_data,
        
        output wire [NODES-1:0]     o_pass,
        output wire [INPUTS-1:0]    o_data
    );
    
    localparam SPLIT            = (STAGE_NUM < STAGES-1) ? 2**(STAGE_NUM+1) : 2**STAGE_NUM;
    
    wire    [INPUTS-1:0]        w_data_in;
    wire    [INPUTS-1:0]        w_data_out;
    wire    [NODES-1:0]         w_pass;
    
    genvar i;
    
    assign o_data = w_data_out;
    assign o_pass = w_pass;
        
    // Stage output mapping
    generate      
        if (STAGE_NUM < STAGES-1) begin
            for (i = 0; i < INPUTS; i = i+1) begin
                if ((i/SPLIT)%2 == 0) begin
                    if (i%2 == 0) begin
                        assign w_data_in[i] = i_data[i];
                    end
                    else begin
                        assign w_data_in[i+SPLIT-1] = i_data[i];
                    end
                end
                else begin
                    if (i%2 == 0) begin
                        assign w_data_in[i-SPLIT+1] = i_data[i];
                    end
                    else begin
                        assign w_data_in[i] = i_data[i];
                    end
                end
            end
        end
        else begin
            for (i = 0; i < INPUTS; i = i+1) begin
                if (i < SPLIT) begin
                    assign w_data_in[2*i] = i_data[i];
                end
                else begin
                    assign w_data_in[2*(i-SPLIT)+1] = i_data[i];
                end
            end
        end
    endgenerate
    
    // Node generation
    generate
        for (i = 0; i < NODES; i = i+1) begin
            pscb_gen_node pscb_node_gen_i (
                .i_scb(i_scb[i]),
                .i_flag_0(w_data_in[2*i]),
                .i_flag_1(w_data_in[2*i+1]),
                
                .o_pass(w_pass[i]),
                .o_flag_0(w_data_out[2*i]),
                .o_flag_1(w_data_out[2*i+1])
            );
        end
    endgenerate
    
endmodule
