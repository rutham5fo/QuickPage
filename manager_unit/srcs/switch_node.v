`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 18.02.2025 12:59:57
// Design Name: 
// Module Name: switch_node
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


module switch_node #(
        parameter PIPELINE          = 1,
        parameter INPUTS            = 64,
        parameter DATA_W            = 1
    )(
        input wire                      i_clk,
        input wire                      i_reset,
        input wire  [DATA_W-1:0]        i_data_0,
        input wire  [DATA_W-1:0]        i_data_1,
        input wire                      i_scb,
        
        output wire [DATA_W-1:0]        o_data_0,
        output wire [DATA_W-1:0]        o_data_1
    );
    
    wire    [DATA_W-1:0]        data_0_drv;
    wire    [DATA_W-1:0]        data_1_drv;
    
    assign data_0_drv = (i_scb) ? i_data_1 : i_data_0;
    assign data_1_drv = (i_scb) ? i_data_0 : i_data_1;
    
    generate
        if (PIPELINE) begin
            reg     [DATA_W-1:0]        r_data_0;
            reg     [DATA_W-1:0]        r_data_1;
            
            assign o_data_0 = r_data_0;
            assign o_data_1 = r_data_1;
            
            always @(posedge i_clk) begin
                r_data_0 <= (i_reset) ? 0 : data_0_drv;
                r_data_1 <= (i_reset) ? 0 : data_1_drv;
            end
        end
        else begin
            assign o_data_0 = data_0_drv;
            assign o_data_1 = data_1_drv;
        end
    endgenerate
    
endmodule
