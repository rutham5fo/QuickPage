`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.02.2025 23:51:04
// Design Name: 
// Module Name: scb_file
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


module scb_file #(
        parameter CHANS                 = 8,
        parameter BLOCKS                = 4,
        parameter BLOCK_D               = 128,
        parameter BLOCK_W               = $clog2(BLOCK_D),
        parameter BLOCK_L               = $clog2(BLOCKS),
        parameter NODES                 = BLOCK_D >> 1,
        parameter DATA_W                = NODES * BLOCK_W
    )(
        input wire                          i_clk,
        input wire                          i_reset,
        input wire                          i_we,
        input wire  [DATA_W-1:0]            i_wr_data,
        input wire  [BLOCK_L-1:0]           i_wr_addr,
        input wire  [BLOCK_L-1:0]           i_rd_addr,
        input wire  [BLOCK_L*CHANS-1:0]     i_chan_addr,
        
        output wire [DATA_W-1:0]            o_rd_data,
        output wire [DATA_W*CHANS-1:0]      o_chan_data
    );
    
    wire    [BLOCKS-1:0]                    w_we;
    wire    [BLOCK_L-1:0]                   w_chan_addr[0:CHANS-1];
    wire    [DATA_W-1:0]                    w_chan_data[0:CHANS-1];
    wire    [DATA_W-1:0]                    w_rd_data;
    
    //reg     [DATA_W-1:0]                    r_rd_data;
    reg     [DATA_W-1:0]                    r_scb[0:BLOCKS-1];
    
    genvar i;
    
    integer k;
    
    assign w_we = i_we << i_wr_addr;
    assign w_rd_data = r_scb[i_rd_addr];
    
    //assign o_rd_data = r_rd_data;
    assign o_rd_data = w_rd_data;
    
    generate
        for (i = 0; i < CHANS; i = i+1) begin                   :   gen_chans
            assign w_chan_addr[i] = i_chan_addr[i*BLOCK_L +: BLOCK_L];
            assign w_chan_data[i] = r_scb[w_chan_addr[i]];
            assign o_chan_data[i*DATA_W +: DATA_W] = w_chan_data[i];
        end
    endgenerate
    
    always @(posedge i_clk) begin
        for (k = 0; k < BLOCKS; k = k+1) begin
            r_scb[k] <= (i_reset) ? 0 : (w_we[k]) ? i_wr_data : r_scb[k];
        end
    end
    
    //initial begin
    //    r_rd_data = 0;
    //end
    
    //always @(posedge i_clk) begin
    //    r_rd_data <= w_rd_data;
    //end
    
endmodule
