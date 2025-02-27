`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.02.2025 00:12:24
// Design Name: 
// Module Name: pointer_translator
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


module pointer_translator #(
        parameter BLOCKS                    = 4,
        parameter BLOCK_D                   = 128,
        parameter BLOCK_W                   = $clog2(BLOCK_D),
        parameter BLOCK_L                   = $clog2(BLOCKS),
        parameter NODES                     = BLOCK_D >> 1,
        parameter DATA_W                    = NODES * BLOCK_W
    )(
        input wire                          i_clk,
        input wire                          i_reset,
        input wire  [BLOCK_L-1:0]           i_blk_sel,
        input wire  [DATA_W-1:0]            i_scb,
        input wire  [BLOCK_W-1:0]           i_alloc_free_ptr,
        input wire  [BLOCK_W-1:0]           i_dealloc_base,
        
        output wire [DATA_W-1:0]            o_blk_scb,
        output wire [BLOCK_L-1:0]           o_blk_sel,
        output wire [BLOCK_W-1:0]           o_alloc_base,
        output wire [BLOCK_W-1:0]           o_dealloc_vptr
    );
    
    wire    [BLOCK_D-1:0]               w_vtp_data;
    wire    [BLOCK_D-1:0]               w_ptv_data;
    wire    [BLOCK_D-1:0]               w_alloc_base_map;
    wire    [BLOCK_D-1:0]               w_dealloc_vptr_map;
    
    reg     [BLOCK_W-1:0]               rt_alloc_base;
    reg     [BLOCK_W-1:0]               rt_dealloc_vptr;
    
    reg     [BLOCK_D-1:0]               r_alloc_base_map;
    reg     [BLOCK_D-1:0]               r_dealloc_vptr_map;
    reg     [BLOCK_L-1:0]               r_blk_sel;
    reg     [DATA_W-1:0]                r_blk_scb;
    
    integer k;
    
    assign w_vtp_data = 1'b1 << i_alloc_free_ptr;
    assign w_ptv_data = 1'b1 << i_dealloc_base;
    
    assign o_blk_scb = r_blk_scb;
    assign o_blk_sel = r_blk_sel;
    assign o_alloc_base = rt_alloc_base;
    assign o_dealloc_vptr = rt_dealloc_vptr;
    
    // Allocator virt-phy translator
    switch_up #(
        .PIPELINE(0),
        .INPUTS(BLOCK_D),
        .NODES(NODES),
        .DATA_W(1),
        .STAGES(BLOCK_W)
    ) vtp_trans_i (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_data(w_vtp_data),
        .i_scb(i_scb),
        
        .o_data(w_alloc_base_map)
    );
    
    // Deallocator phy-virt translator
    switch_down #(
        .PIPELINE(0),
        .INPUTS(BLOCK_D),
        .NODES(NODES),
        .DATA_W(1),
        .STAGES(BLOCK_W)
    ) ptv_trans_i (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_data(w_ptv_data),
        .i_scb(i_scb),
        
        .o_data(w_dealloc_vptr_map)
    );
    
    initial begin
        r_alloc_base_map = 0;
        r_dealloc_vptr_map = 0;
        r_blk_sel = 0;
        r_blk_scb = 0;
    end
    
    always @(posedge i_clk) begin
        r_alloc_base_map <= w_alloc_base_map;
        r_dealloc_vptr_map <= w_dealloc_vptr_map;
        r_blk_sel <= i_blk_sel;
        r_blk_scb <= i_scb;
    end
    
    always @(*) begin
        rt_alloc_base = 0;
        for (k = 0; k < BLOCK_D; k = k+1) begin
            if (r_alloc_base_map[k]) rt_alloc_base = k;
        end
    end
    
    always @(*) begin
        rt_dealloc_vptr = 0;
        for (k = 0; k < BLOCK_D; k = k+1) begin
            if (r_dealloc_vptr_map[k]) rt_dealloc_vptr = k;
        end
    end
    
endmodule
