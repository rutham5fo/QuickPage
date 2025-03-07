`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.02.2025 11:20:11
// Design Name: 
// Module Name: address_translator
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


module address_translator #(
        parameter SUBS              = 4,
        parameter BLOCKS            = 4,
        parameter BLOCK_D           = 128,
        parameter BLOCK_W           = $clog2(BLOCK_D),
        parameter BLOCK_L           = $clog2(BLOCKS),
        parameter NODES             = BLOCK_D >> 1,
        parameter VADDR_W           = BLOCK_L + 3*BLOCK_W + 1,      // Address (Block_sel + obj_start loc + obj_offset) | OBJ_start = startign phy_addr
        parameter LSU_VADDR_W       = BLOCK_L + 2*BLOCK_W,
        parameter PADDR_W           = BLOCK_L + BLOCK_W,
        parameter ASSOC_D           = 8,
        parameter ASSOC_W           = $clog2(ASSOC_D)
    )(
        input wire                          i_clk,
        input wire                          i_reset,
        input wire  [NODES*BLOCK_W-1:0]     i_scb,                  // SCBs of selected block
        input wire  [VADDR_W-1:0]           i_chan_vaddr,            // Only LSU[0]'s blk_sel is used, rest ignored
        input wire  [ASSOC_W*SUBS-1:0]      i_chan_svaddr,          // The sub-channels LSU[1->LSUS-1] can simultaneously read rows from the same set as LSU[0] using these side-channels
        
        output wire                         o_trans_update,         // High for a single cycle after successful translator update.
        output wire [BLOCK_L-1:0]           o_blk_addr,             // Block select address to scb file
        output wire [PADDR_W-1:0]           o_lsu_paddr,            // Translated addresses towards memory
        output wire [PADDR_W*SUBS-1:0]      o_lsu_spaddr
    );
    
    localparam SET_D                    = BLOCK_D >> ASSOC_W;
    localparam SET_W                    = (SET_D == 1) ? 1 : $clog2(SET_D);
    
    wire    [LSU_VADDR_W-1:0]           w_lsu_vaddr;            // Unpacked virtual address
    wire    [BLOCK_L-1:0]               w_lsu_blk;
    wire    [BLOCK_W-1:0]               w_lsu_saddr;            // Obj start location in block
    wire    [SET_W-1:0]                 w_lsu_soffset;
    wire    [ASSOC_W-1:0]               w_lsu_sassoc;
    
    wire    [BLOCK_W*BLOCK_D-1:0]       w_phy_map;
    wire    [BLOCK_W*BLOCK_D-1:0]       w_phy_ptr;
    wire    [BLOCK_D-1:0]               w_tmap_down;                // Phy to virt map
    //wire    [SET_W-1:0]                 w_lsu_set;
    wire    [BLOCK_W-1:0]               w_lsu_rotate;
    wire    [BLOCK_W-1:0]               w_swd_scb;
    wire    [NODES*BLOCK_W-1:0]         w_rscb;
    wire    [BLOCK_W-1:0]               w_lsu_base_ptr;
    wire    [BLOCK_W-1:0]               w_lsu_taddr;          // translated addr
    wire    [BLOCK_W-1:0]               w_lsu_staddr[0:SUBS-1];
    wire    [PADDR_W-1:0]               w_lsu_paddr;          // physical addr
    wire    [PADDR_W-1:0]               w_lsu_spaddr[0:SUBS-1];
    
    wire                                w_lsu_blk_stbl;
    wire                                w_lsu_soffset_stbl;
    wire                                w_lsu_update_stbl;
    
    reg     [NODES*BLOCK_W-1:0]         r_scb;
    reg     [BLOCK_W-1:0]               r_lsu_rotate;
    reg     [BLOCK_L-1:0]               r_lsu_blk;
    reg     [BLOCK_W-1:0]               r_lsu_taddr[0:ASSOC_D-1];
    reg                                 r_lsu_update_stbl;
    reg                                 r_update;                           // High for a single cycle when r_lsu_taddr gets updated
    
    reg     [BLOCK_L-1:0]               rp_lsu_blk[0:1];
    reg     [SET_W-1:0]                 rp_lsu_soffset;
    reg     [BLOCK_W-1:0]               rp_lsu_saddr;
    
    genvar i;
    
    integer k;
    
    assign o_blk_addr = w_lsu_blk;
    
    assign w_lsu_vaddr = i_chan_vaddr[0 +: LSU_VADDR_W];
    assign w_lsu_blk = w_lsu_vaddr[LSU_VADDR_W-1 -: BLOCK_L];
    assign w_lsu_saddr = w_lsu_vaddr[BLOCK_W +: BLOCK_W];
    assign w_lsu_soffset = w_lsu_vaddr[ASSOC_W +: SET_W];
    assign w_lsu_sassoc = w_lsu_vaddr[0 +: ASSOC_W];
    assign w_lsu_base_ptr = w_lsu_saddr ^ w_swd_scb;
    assign w_lsu_taddr = r_lsu_taddr[w_lsu_sassoc];
    assign w_lsu_paddr = {r_lsu_blk, w_lsu_taddr};
    
    assign w_tmap_down = 1'b1 << w_lsu_saddr;
    //assign w_lsu_set = ~w_lsu_base_ptr[BLOCK_W-1 -: SET_W];
    assign w_lsu_rotate = r_lsu_rotate;
    
    assign w_lsu_blk_stbl = (w_lsu_blk == rp_lsu_blk[1]) ? 1'b1 : 1'b0;
    assign w_lsu_soffset_stbl = (w_lsu_soffset == rp_lsu_soffset && w_lsu_saddr == rp_lsu_saddr) ? 1'b1 : 1'b0;
    assign w_lsu_update_stbl = w_lsu_blk_stbl & w_lsu_soffset_stbl;    
    
    assign o_lsu_paddr = w_lsu_paddr;
    assign o_trans_update = r_update;
    
    generate
        for (i = 0; i < SUBS; i = i+1) begin                :       gen_lsus
            assign w_lsu_staddr[i] = r_lsu_taddr[i_chan_svaddr];
            assign w_lsu_spaddr[i] = {r_lsu_blk, w_lsu_staddr[i]};
            
            assign o_lsu_spaddr[i*PADDR_W +: PADDR_W] = w_lsu_spaddr[i];
        end
    endgenerate
    
    generate
        for (i = 0; i < BLOCK_D; i = i+1) begin             :       gen_phy_map
            assign w_phy_map[i*BLOCK_W +: BLOCK_W] = i;
        end
    endgenerate
        
    // Physical to virtual pointer gen (switch down)
    //(* dont_touch = "yes" *)
    trans_down #(
        .PIPELINE(0),
        .INPUTS(BLOCK_D),
        .NODES(NODES),
        .DATA_W(1),
        .STAGES(BLOCK_W)
    ) base_addr_gen_i (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_data(w_tmap_down),
        .i_scb(r_scb),
        
        .o_scb(w_swd_scb)
    );
    
    rscb_gen_tree #(
        .BITMAP(BLOCK_D),
        .STAGES(BLOCK_W),
        .DATA_W(BLOCK_W+1),
        .MAX_NODES(NODES)
    ) trans_rscb_gen_i (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_scb(r_scb),
        .i_rotate(w_lsu_rotate),
        
        .o_scb(w_rscb)
    );
    
    //(* dont_touch = "yes" *)
    switch_down #(
        .PIPELINE(0),
        .INPUTS(BLOCK_D),
        .NODES(NODES),
        .DATA_W(BLOCK_W),
        .STAGES(BLOCK_W)
    ) phy_virt_down_i (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_data(w_phy_map),
        .i_scb(w_rscb),
        
        .o_data(w_phy_ptr)
    );
    
    initial begin
        r_lsu_rotate = 0;
        r_lsu_blk = 0;
        rp_lsu_blk[0] = 0;
        rp_lsu_blk[1] = 0;
        rp_lsu_soffset = 0;
        rp_lsu_saddr = 0;
        r_lsu_update_stbl = 0;
        r_update = 0;
        for (k = 0; k < ASSOC_D; k = k+1) begin
            r_lsu_taddr[k] = 0;
        end
    end
    
    always @(posedge i_clk) begin
        r_scb <= (i_reset) ? 0 : i_scb;
        //r_lsu_rotate <= (w_lsu_set + w_lsu_soffset) << ASSOC_W;
        r_lsu_rotate <= BLOCK_D - 1 - w_lsu_base_ptr + (w_lsu_soffset << ASSOC_W);
        //r_lsu_blk <= w_lsu_blk;
        rp_lsu_blk[0] <= w_lsu_blk;
        rp_lsu_blk[1] <= rp_lsu_blk[0];
        rp_lsu_soffset <= w_lsu_soffset;
        rp_lsu_saddr <= w_lsu_saddr;
        r_lsu_update_stbl <= w_lsu_update_stbl;
        r_lsu_blk <= (w_lsu_blk_stbl) ? rp_lsu_blk[1] : r_lsu_blk;
        r_update <= ({r_lsu_update_stbl, w_lsu_update_stbl} == 2'b01 && !i_reset) ? 1'b1 : 1'b0;
    end
    
    always @(posedge i_clk) begin
        for (k = 0; k < ASSOC_D; k = k+1) begin
            r_lsu_taddr[k] <= (w_lsu_soffset_stbl) ? w_phy_ptr[(BLOCK_W*BLOCK_D-1)-(k*BLOCK_W) -: BLOCK_W] : r_lsu_taddr[k];
        end
    end
    
endmodule
