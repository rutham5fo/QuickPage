`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 18.02.2025 18:23:57
// Design Name: 
// Module Name: compressor
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
module compressor #(
        parameter BLOCKS            = 4,
        parameter BITMAP            = 128,
        parameter NODES             = BITMAP >> 1,
        parameter STAGES            = $clog2(BITMAP),
        parameter BLOCK_W           = $clog2(BITMAP),                     // BLOCK_W from allocator
        parameter BLOCK_L           = $clog2(BLOCKS)
    )(
        input wire                      i_clk,
        input wire                      i_reset,
        input wire                      i_dealloc_vld,
        input wire  [BLOCK_L-1:0]       i_dealloc_blk,
        input wire  [BLOCK_W-1:0]       i_dealloc_addr,
        input wire  [BLOCK_W-1:0]       i_dealloc_size,
        
        output wire                     o_dealloc_vld,
        output wire [BLOCK_L-1:0]       o_dealloc_blk,
        output wire [NODES*STAGES-1:0]  o_scb
    );
    
    wire    [NODES*STAGES-1:0]          w_rscb;
    wire    [NODES*STAGES-1:0]          w_pscb;
    //wire    [NODES*STAGES-1:0]          w_cscb;
    
    reg                                 r_cscb_vld;
    reg     [NODES*STAGES-1:0]          r_cscb;
    reg     [BLOCK_L-1:0]               r_dealloc_blk;
    
    //assign w_cscb = w_rscb & w_pscb;
    
    assign o_dealloc_vld = r_cscb_vld;
    assign o_scb = r_cscb;
    assign o_dealloc_blk = r_dealloc_blk;
    
    rscb_gen_tree #(
        .REGISTER(0),
        .BITMAP(BITMAP),
        .STAGES(STAGES),
        .DATA_W(BLOCK_W),
        .MAX_NODES(NODES)
    ) rscb_gen_tree_i (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_rotate(i_dealloc_size),
        
        .o_scb(w_rscb)
    );
    
    pscb_gen_tree #(
        .REGISTER(0),
        .INPUTS(BITMAP),
        .NODES(NODES),
        .STAGES(STAGES),
        .DATA_W(BLOCK_W)
    ) pscb_gen_tree_i (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_pass_start(i_dealloc_addr),
        
        .o_scb(w_pscb)
    );
    
    always @(posedge i_clk) begin
        r_cscb <= (i_reset) ? 0 : w_pscb & w_rscb;
        r_cscb_vld <= (i_reset) ? 1'b0 : i_dealloc_vld;
        r_dealloc_blk <= (i_reset) ? 0 : i_dealloc_blk;
    end
    
endmodule
*/

module compressor #(
        parameter BITMAP            = 256,
        parameter NODES             = BITMAP >> 1,
        parameter STAGES            = $clog2(BITMAP),
        parameter BLOCK_W           = STAGES,
        parameter BLOCK_L           = 8,
        parameter REG_STAGE         = STAGES
    )(
        input wire                      i_clk,
        input wire                      i_reset,
        input wire                      i_dealloc_vld,
        input wire  [BLOCK_L-1:0]       i_dealloc_blk,
        input wire  [BLOCK_W-1:0]       i_dealloc_addr,
        input wire  [BLOCK_W:0]         i_dealloc_size,                 // Size is not zero indexed and hence requires 1 additional bit for full reolution
        input wire  [NODES*STAGES-1:0]  i_scb,
        
        output wire                     o_scb_vld,
        output wire [NODES*STAGES-1:0]  o_scb,
        output wire [BLOCK_L-1:0]       o_dealloc_blk
    );
    
    localparam MAX_SCB                  = NODES * STAGES;
    
    wire    [NODES*STAGES-1:0]          w_rscb;
    wire    [NODES*STAGES-1:0]          w_pscb;
    wire    [NODES*STAGES-1:0]          w_cscb;
    
    reg                                 r_cscb_vld;
    //reg     [NODES*STAGES-1:0]          r_cscb;
    reg     [BLOCK_L-1:0]               r_dealloc_blk;
    
    genvar i;
    
    //integer k;
    
    assign o_scb_vld = r_cscb_vld;
    //assign o_scb = r_cscb;
    //assign o_scb = w_cscb;
    assign o_dealloc_blk = r_dealloc_blk;
    
    generate
        if (REG_STAGE == STAGES) begin
        
            reg     [NODES*STAGES-1:0]          r_cscb;
            
            assign o_scb = r_cscb;
            
            always @(posedge i_clk) begin
                r_cscb <= (i_reset) ? 0 : w_cscb;
            end
        end
        else begin
            assign o_scb = w_cscb;
        end
    endgenerate
    
    generate
        for (i = 0; i < MAX_SCB; i = i+1) begin                :   gen_cscb
            assign w_cscb[i] = (w_pscb[i]) ? i_scb[i] : w_rscb[i];
        end
    endgenerate
    
    rscb_gen_tree #(
        .REG_STAGE(REG_STAGE),
        .BITMAP(BITMAP),
        .STAGES(STAGES),
        .DATA_W(BLOCK_W+1),                 // 1 additional bit for full resolution
        .MAX_NODES(NODES)
    ) rscb_gen_tree_i (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_scb(i_scb),
        .i_rotate(i_dealloc_size),
        
        .o_scb(w_rscb)
    );
    
    pscb_gen_tree #(
        .REG_STAGE(REG_STAGE),
        .INPUTS(BITMAP),
        .NODES(NODES),
        .STAGES(STAGES),
        .DATA_W(BLOCK_W)
    ) pscb_gen_tree_i (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_scb(i_scb),
        .i_pass_start(i_dealloc_addr),
        
        .o_pass(w_pscb)
    );
    
    // Regs Power init
    initial begin
        r_dealloc_blk = 0;
    //    r_cscb = 0;
        r_cscb_vld = 0;
    end
    
    always @(posedge i_clk) begin
        r_cscb_vld <= (i_reset) ? 1'b0 : i_dealloc_vld;
        r_dealloc_blk <= i_dealloc_blk;
    //    r_cscb <= (i_reset) ? 0 : w_cscb;
    end
        
endmodule
