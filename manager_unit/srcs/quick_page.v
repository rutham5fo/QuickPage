`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 18.02.2025 18:33:40
// Design Name: 
// Module Name: quick_page
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


module quick_page #(
        parameter REG_INPUTS            = 0,
        parameter REG_MEMORY            = 0,
        parameter CHANS                 = 2,                            // Number of independent translator channels
        parameter SUBS                  = 8,                            // Number of side (sub) channels dependent on main channel for blk and set select | Value cannot be greater than ASSOC_D-1
        parameter LINE_S                = 256,                          // Number of bytes per line
        parameter MEM_D                 = 2048,                          // Number of lines in heap
        parameter BLOCK_D               = 512,                          // Number of lines per block in heap / Search space
        parameter BLOCK_W               = $clog2(BLOCK_D),
        parameter ASSOC_D               = 32,                        // Associativity / range of buffered phy_ptr location during translation
        parameter ASSOC_W               = $clog2(ASSOC_D),
        parameter BLOCKS                = MEM_D / BLOCK_D,
        parameter BLOCK_L               = (BLOCKS != 1) ? $clog2(BLOCKS) : 1,
        parameter REQ_S                 = BLOCK_D * LINE_S,             // Max allocable bytes
        parameter REQ_W                 = $clog2(REQ_S) + 1,
        parameter REP_W                 = BLOCK_L + 3*BLOCK_W + 1,  // Reply width is the physical blk + base_addr + size (additional 1 bit for full resolution) + offset (init to 0)
        parameter VADDR_W               = REP_W,
        parameter PADDR_W               = BLOCK_L + BLOCK_W
    )(
        input wire                              i_clk,
        input wire                              i_reset,
        input wire                              i_req_id,               // req_id must alternate for subsequent valid requests. Subsequent reqs with the same id will be ignored
        input wire  [1:0]                       i_req_func,             // 00 - idle ; 01 - alloc ; 10 - dealloc ; 11 - reserved;
        input wire  [REQ_W-1:0]                 i_req_alloc_size,       // size of alloc request in bytes
        input wire  [REP_W-1:0]                 i_req_dealloc_data,     // Object (block + obj_id + size) to be deallocated
        input wire  [VADDR_W*CHANS-1:0]         i_virt_addr,        // Virtual address for translation in each LSU channel
        input wire  [ASSOC_W*SUBS*CHANS-1:0]    i_sub_virt_addr,
        
        output wire                             o_busy,                // Backpressure signal for upstream procs | true while updating regs
        output wire                             o_rep_alloc_vld,        // 1 for valid reply
        output wire                             o_rep_dealloc_vld,      // 1 for valid dealloc
        output wire [REP_W-1:0]                 o_rep_data,             // Block_id + Obj_id + Size
        output wire [CHANS-1:0]                 o_mem_update,       // Held high for a single cycle after the channel has been updated.
        output wire [PADDR_W*CHANS-1:0]         o_mem_addr,         // Unregistered, translated physical addreses to BRAM module
        output wire [PADDR_W*SUBS*CHANS-1:0]    o_mem_sub_addr
    );
    
    localparam NODES                = BLOCK_D >> 1;
    localparam STAGES               = BLOCK_W;
    localparam SWITCH_DATA_W        = NODES * STAGES;
    localparam LSU_VADDR_W          = BLOCK_L + 2*BLOCK_W;
    
    //wire                                w_alloc_en;
    wire                                w_dealloc_en;
    wire    [BLOCK_L-1:0]               w_blk_sel;
    wire    [BLOCK_L-1:0]               w_compr_blk_sel;
    wire    [SWITCH_DATA_W-1:0]         w_compr_blk_scb;
    
    wire    [BLOCK_W-1:0]               w_alloc_free_ptr;
    wire    [BLOCK_W-1:0]               w_alloc_base_addr;
    wire    [BLOCK_W-1:0]               w_dealloc_obj_base;
    wire    [BLOCK_W:0]                 w_dealloc_obj_size;
    wire    [BLOCK_W-1:0]               w_dealloc_base_addr;
    
    wire    [SWITCH_DATA_W-1:0]         w_ptr_rd_scb;
    wire    [SWITCH_DATA_W-1:0]         w_chan_rd_scb[0:CHANS-1];
    wire    [SWITCH_DATA_W*CHANS-1:0]   w_chan_rd_scb_pkd;
    wire                                w_scb_wr_en;
    wire    [BLOCK_L-1:0]               w_scb_wr_addr;
    wire    [BLOCK_L-1:0]               w_chan_scb_addr[0:CHANS-1];
    wire    [BLOCK_L*CHANS-1:0]         w_chan_scb_addr_pkd;
    wire    [SWITCH_DATA_W-1:0]         w_scb_wr_data;
    
    wire    [VADDR_W-1:0]               w_chan_virt_addr[0:CHANS-1];
    wire    [ASSOC_W*SUBS-1:0]          w_chan_sub_virt_addr[0:CHANS-1];
    wire    [PADDR_W-1:0]               w_chan_paddr[0:CHANS-1];
    wire    [PADDR_W*SUBS-1:0]          w_chan_sub_paddr[0:CHANS-1];
    wire    [CHANS-1:0]                 w_chan_update;
    
    wire                                wi_req_id;
    wire    [1:0]                       wi_req_func;
    wire    [REQ_W-1:0]                 wi_req_alloc_size;
    wire    [REP_W-1:0]                 wi_req_dealloc_data;
    wire    [VADDR_W*CHANS-1:0]         wi_virt_addr;
    wire    [ASSOC_W*SUBS*CHANS-1:0]    wi_sub_virt_addr;
    
    wire    [PADDR_W*CHANS-1:0]         wo_mem_addr;
    wire    [PADDR_W*SUBS*CHANS-1:0]    wo_mem_sub_addr;
    wire    [CHANS-1:0]                 wo_mem_update;
    
    genvar i;
    
    generate
        if (REG_INPUTS) begin
            reg                                 ri_req_id;
            reg     [1:0]                       ri_req_func;
            reg     [REQ_W-1:0]                 ri_req_alloc_size;
            reg     [REP_W-1:0]                 ri_req_dealloc_data;
            reg     [VADDR_W*CHANS-1:0]         ri_virt_addr;
            reg     [ASSOC_W*SUBS*CHANS-1:0]    ri_sub_virt_addr;
            
            assign wi_req_id = ri_req_id;
            assign wi_req_func = ri_req_func;
            assign wi_req_alloc_size = ri_req_alloc_size;
            assign wi_req_dealloc_data = ri_req_dealloc_data;
            assign wi_virt_addr = ri_virt_addr;
            assign wi_sub_virt_addr = ri_sub_virt_addr;
            
            always @(posedge i_clk) begin
                ri_req_id <= i_req_id;
                ri_req_func <= i_req_func;
                ri_req_alloc_size <= i_req_alloc_size;
                ri_req_dealloc_data <= i_req_dealloc_data;
                ri_virt_addr <= i_virt_addr;
                ri_sub_virt_addr <= i_sub_virt_addr;
            end
        end
        else begin
            assign wi_req_id = i_req_id;
            assign wi_req_func = i_req_func;
            assign wi_req_alloc_size = i_req_alloc_size;
            assign wi_req_dealloc_data = i_req_dealloc_data;
            assign wi_virt_addr = i_virt_addr;
            assign wi_sub_virt_addr = i_sub_virt_addr;
        end
    endgenerate
    
    generate
        if (REG_MEMORY) begin
            reg     [PADDR_W*CHANS-1:0]         r_mem_addr;
            reg     [PADDR_W*SUBS*CHANS-1:0]    r_mem_sub_addr;
            reg     [CHANS-1:0]                 r_mem_update;
            
            assign o_mem_addr = r_mem_addr;
            assign o_mem_sub_addr = r_mem_sub_addr;
            assign o_mem_update = r_mem_update;
            
            always @(posedge i_clk) begin
                r_mem_addr <= (i_reset) ? 0 : wo_mem_addr;
                r_mem_sub_addr <= (i_reset) ? 0 : wo_mem_sub_addr;
                r_mem_update <= (i_reset) ? 0 : wo_mem_update;
            end
        end
        else begin
            assign o_mem_addr = wo_mem_addr;
            assign o_mem_sub_addr = wo_mem_sub_addr;
            assign o_mem_update = wo_mem_update;
        end
    endgenerate
    
    (* dont_touch = "yes" *)
    control_unit #(
        .LINE_S(LINE_S),                          // Number of bytes per line
        .MEM_D(MEM_D),                          // Number of lines in heap
        .BLOCK_D(BLOCK_D),                          // Number of lines per block in heap / Search space
        .BLOCK_W(BLOCK_W),
        .BLOCKS(BLOCKS),
        .BLOCK_L(BLOCK_L),
        .NODES(NODES),
        .REQ_S(REQ_S),             // Max allocable bytes
        .REQ_W(REQ_W),
        .REP_W(REP_W)           // Reply width is the physical blk + base_addr + size + offset (init to 0)
    ) controller_i (
        .i_clk(i_clk),
        .i_reset(i_reset),
        // From PU
        .i_req_id(wi_req_id),               // req_id must alternate for subsequent valid requests. Subsequent reqs with the same id will be ignored
        .i_req_func(wi_req_func),             // 00 - idle ; 01 - alloc ; 10 - dealloc ; 11 - reserved;
        .i_req_alloc_size(wi_req_alloc_size),       // size of alloc request in bytes
        .i_req_dealloc_obj(wi_req_dealloc_data),      // Object_id to be deallocated
        // From alloc_decoder
        .i_alloc_blk_base(w_alloc_base_addr),
        
        // To SCB file, Compressor and dealloc_decoder
        .o_dealloc_blk_en(w_dealloc_en),
        .o_blk_sel(w_blk_sel),
        .o_alloc_free_ptr(w_alloc_free_ptr),      // Base address (free_ptr) of current allocation
        .o_dealloc_blk_base(w_dealloc_obj_base),      // Object id within the blk | Object file will produce the vptr address for compressor
        .o_dealloc_blk_size(w_dealloc_obj_size),
        
        // To upstream
        .o_stall(o_busy),
        
        // To PU
        .o_rep_alloc_vld(o_rep_alloc_vld),        // 1 for valid reply
        .o_rep_dealloc_vld(o_rep_dealloc_vld),      // 1 for valid dealloc
        .o_rep_data(o_rep_data)
    );
    
    (* dont_touch = "yes" *)
    pointer_translator #(
        .BLOCKS(BLOCKS),
        .BLOCK_D(BLOCK_D),
        .BLOCK_W(BLOCK_W),
        .BLOCK_L(BLOCK_L),
        .NODES(NODES),
        .DATA_W(SWITCH_DATA_W)
    ) ptr_tanslator_i (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_blk_sel(w_blk_sel),
        .i_scb(w_ptr_rd_scb),
        .i_alloc_free_ptr(w_alloc_free_ptr),
        .i_dealloc_base(w_dealloc_obj_base),
        
        .o_blk_scb(w_compr_blk_scb),
        .o_blk_sel(w_compr_blk_sel),
        .o_alloc_base(w_alloc_base_addr),
        .o_dealloc_vptr(w_dealloc_base_addr)
    );
    
    (* dont_touch = "yes" *)
    scb_file #(
        .CHANS(CHANS),
        .BLOCKS(BLOCKS),
        .BLOCK_D(BLOCK_D),
        .BLOCK_W(BLOCK_W),
        .BLOCK_L(BLOCK_L),
        .NODES(NODES),
        .DATA_W(SWITCH_DATA_W)
    ) scb_file_i (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_we(w_scb_wr_en),
        .i_wr_data(w_scb_wr_data),
        .i_wr_addr(w_scb_wr_addr),
        .i_rd_addr(w_blk_sel),
        .i_chan_addr(w_chan_scb_addr_pkd),
        
        .o_rd_data(w_ptr_rd_scb),
        .o_chan_data(w_chan_rd_scb_pkd)
    );
    
    (* dont_touch = "yes" *)
    compressor #(
        .BITMAP(BLOCK_D),
        .NODES(NODES),
        .STAGES(STAGES),
        .BLOCK_W(BLOCK_W),
        .BLOCK_L(BLOCK_L)
    ) compressor_unit_i (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_dealloc_vld(w_dealloc_en),
        .i_dealloc_blk(w_compr_blk_sel),
        .i_dealloc_addr(w_dealloc_base_addr),
        .i_dealloc_size(w_dealloc_obj_size),
        .i_scb(w_compr_blk_scb),
        
        .o_scb_vld(w_scb_wr_en),
        .o_dealloc_blk(w_scb_wr_addr),
        .o_scb(w_scb_wr_data)
    );
    
    generate
        for (i = 0; i < CHANS; i = i+1) begin               :   gen_addr_trans
        
            assign w_chan_scb_addr_pkd[i*BLOCK_L +: BLOCK_L] = w_chan_scb_addr[i];
            assign w_chan_rd_scb[i] = w_chan_rd_scb_pkd[i*SWITCH_DATA_W +: SWITCH_DATA_W];
            assign w_chan_virt_addr[i] = wi_virt_addr[i*VADDR_W +: VADDR_W];
            assign w_chan_sub_virt_addr[i] = wi_sub_virt_addr[i*ASSOC_W*SUBS +: ASSOC_W*SUBS];
            
            assign wo_mem_addr[i*PADDR_W +: PADDR_W] = w_chan_paddr[i];
            assign wo_mem_sub_addr[i*PADDR_W*SUBS +: PADDR_W*SUBS] = w_chan_sub_paddr[i];
            assign wo_mem_update[i] = w_chan_update[i];
            
            (* dont_touch = "yes" *)
            address_translator #(
                .SUBS(SUBS),
                .BLOCKS(BLOCKS),
                .BLOCK_D(BLOCK_D),
                .BLOCK_W(BLOCK_W),
                .BLOCK_L(BLOCK_L),
                .NODES(NODES),
                .VADDR_W(VADDR_W),            // Address (Block_sel + obj_start loc + obj_offset) | OBJ_start = startign phy_addr
                .LSU_VADDR_W(LSU_VADDR_W),
                .PADDR_W(PADDR_W),
                .ASSOC_D(ASSOC_D),
                .ASSOC_W(ASSOC_W)
            ) addr_trans_i (
                .i_clk(i_clk),
                .i_reset(i_reset),
                .i_scb(w_chan_rd_scb[i]),                  // SCBs of selected block
                .i_chan_vaddr(w_chan_virt_addr[i]),            // Only LSU[0]'s blk_sel is used, rest ignored
                .i_chan_svaddr(w_chan_sub_virt_addr[i]),
                
                .o_trans_update(w_chan_update[i]),
                .o_blk_addr(w_chan_scb_addr[i]),             // Block select address to scb file
                .o_lsu_paddr(w_chan_paddr[i]),            // Translated addresses towards memory
                .o_lsu_spaddr(w_chan_sub_paddr[i])
            );
        end
    endgenerate
    
endmodule
