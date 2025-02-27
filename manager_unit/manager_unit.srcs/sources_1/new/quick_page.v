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

// Version 1 (tested)
/*
module quick_page #(
        parameter REG_INPUTS            = 0,
        parameter LSUS                  = 8,                            // Number of load/store units
        parameter LINE_S                = 256,                          // Number of bytes per line
        parameter MEM_D                 = 128,                          // Number of lines in heap
        parameter BLOCK_D               = 32,                          // Number of lines per block in heap / Search space
        parameter BLOCK_W               = $clog2(BLOCK_D),
        parameter BLOCKS                = MEM_D / BLOCK_D,
        parameter BLOCK_L               = (BLOCKS != 1) ? $clog2(BLOCKS) : 1,
        parameter REQ_S                 = BLOCK_D * LINE_S,             // Max allocable bytes
        parameter REQ_W                 = $clog2(REQ_S) + 1,
        parameter OBJ_D                 = BLOCK_D >> 1,                 // Total number of allocable objects, PER BLOCK
        parameter OBJ_W                 = $clog2(OBJ_D),
        parameter REP_W                 = BLOCK_L + OBJ_W + 2*BLOCK_W,  // Reply width is composite obj_id (MSBs indicate block_id of object) + allocated size
        parameter LSU_VADDR_W           = REP_W,
        parameter LSU_TADDR_W           = BLOCK_L + BLOCK_W
    )(
        input wire                          i_clk,
        input wire                          i_reset,
        input wire                          i_req_id,               // req_id must alternate for subsequent valid requests. Subsequent reqs with the same id will be ignored
        input wire  [1:0]                   i_req_func,             // 00 - idle ; 01 - alloc ; 10 - dealloc ; 11 - reserved;
        input wire  [REQ_W-1:0]             i_req_alloc_size,       // size of alloc request in bytes
        input wire  [REP_W-1:0]             i_req_dealloc_data,     // Object (block + obj_id + size) to be deallocated
        input wire  [LSU_VADDR_W*LSUS-1:0]  i_lsu_virt_addr,        // Virtual address for translation in each LSU channel
        
        output wire                         o_stall,                // Backpressure signal for upstream procs | true while updating regs
        output wire                         o_rep_alloc_vld,        // 1 for valid reply
        output wire                         o_rep_dealloc_vld,      // 1 for valid dealloc
        output wire [REP_W-1:0]             o_rep_data,             // Block_id + Obj_id + Size
        output wire [LSU_TADDR_W*LSUS-1:0]  o_lsu_mem_addr          // Unregistered, translated physical addreses to BRAM module
    );
    
    localparam NODES                = BLOCK_D >> 1;
    localparam STAGES               = BLOCK_W;
    
    wire                            w_alloc_en;
    wire                            w_dealloc_en;
    wire    [BLOCK_L-1:0]           w_blk_sel;
    
    wire    [BLOCK_W-1:0]           w_alloc_base_addr;
    wire    [OBJ_W-1:0]             w_dealloc_obj_addr;
    wire    [BLOCK_W-1:0]           w_dealloc_obj_size;
    wire    [BLOCK_W-1:0]           w_dealloc_base_addr;
    wire                            w_alloc_obj_vld;
    wire    [OBJ_W-1:0]             w_alloc_obj_addr;
    
    wire                            w_vptr_wr_en;
    wire    [BLOCK_L-1:0]           w_vptr_blk;
    wire    [NODES*STAGES-1:0]      w_vptr_scb;
    
    wire    [LSU_TADDR_W*LSUS-1:0]  w_lsu_trans_addr;
    
    wire                            wi_req_id;
    wire    [1:0]                   wi_req_func;
    wire    [REQ_W-1:0]             wi_req_alloc_size;
    wire    [REP_W-1:0]             wi_req_dealloc_data;
    wire    [LSU_VADDR_W*LSUS-1:0]  wi_lsu_virt_addr;
    
    generate
        if (REG_INPUTS) begin
            reg                             ri_req_id;
            reg     [1:0]                   ri_req_func;
            reg     [REQ_W-1:0]             ri_req_alloc_size;
            reg     [REP_W-1:0]             ri_req_dealloc_data;
            reg     [LSU_VADDR_W*LSUS-1:0]  ri_lsu_virt_addr;
            
            assign wi_req_id = ri_req_id;
            assign wi_req_func = ri_req_func;
            assign wi_req_alloc_size = ri_req_alloc_size;
            assign wi_req_dealloc_data = ri_req_dealloc_data;
            assign wi_lsu_virt_addr = ri_lsu_virt_addr;
            
            always @(posedge i_clk) begin
                ri_req_id <= i_req_id;
                ri_req_func <= i_req_func;
                ri_req_alloc_size <= i_req_alloc_size;
                ri_req_dealloc_data <= i_req_dealloc_data;
                ri_lsu_virt_addr <= i_lsu_virt_addr;
            end
        end
        else begin
            assign wi_req_id = i_req_id;
            assign wi_req_func = i_req_func;
            assign wi_req_alloc_size = i_req_alloc_size;
            assign wi_req_dealloc_data = i_req_dealloc_data;
            assign wi_lsu_virt_addr = i_lsu_virt_addr;
        end
    endgenerate
    
    //(* dont_touch = "yes" *)
    control_unit #(
        .LINE_S(LINE_S),
        .MEM_D(MEM_D),
        .BLOCK_D(BLOCK_D),
        .BLOCK_W(BLOCK_W),
        .BLOCKS(BLOCKS),
        .BLOCK_L(BLOCK_L),
        .REQ_S(REQ_S),
        .REQ_W(REQ_W),
        .OBJ_D(OBJ_D),
        .OBJ_W(OBJ_W),
        .REP_W(REP_W)
    ) controller_i (
        .i_clk(i_clk),
        .i_reset(i_reset),
        // From PU
        .i_req_id(wi_req_id),
        .i_req_func(wi_req_func),             // 00 - idle ; 01 - alloc ; 10 - dealloc ; 11 - reserved;
        .i_req_alloc_size(wi_req_alloc_size),       // size of alloc request in bytes
        .i_req_dealloc_obj(wi_req_dealloc_data),      // Object_id to be deallocated
        // From Object file
        .i_alloc_obj_vld(w_alloc_obj_vld),        // True when a free object is available in block
        .i_alloc_obj_addr(w_alloc_obj_addr),       // Address of free object in object file
        
        // To Object file and Compressor
        .o_alloc_blk_en(w_alloc_en),
        .o_dealloc_blk_en(w_dealloc_en),
        .o_blk_sel(w_blk_sel),
        .o_alloc_blk_addr(w_alloc_base_addr),       // Base address (free_ptr) of current allocation
        .o_dealloc_blk_obj(w_dealloc_obj_addr),      // Object id within the blk | Object file will produce the vptr address for compressor
        .o_dealloc_blk_size(w_dealloc_obj_size),
        
        // Upstream
        .o_stall(o_stall),
        
        // To PU
        .o_rep_alloc_vld(o_rep_alloc_vld),        // 1 for valid reply
        .o_rep_dealloc_vld(o_rep_dealloc_vld),      // 1 for valid dealloc
        .o_rep_data(o_rep_data)              // Block_id + Obj_id + Size
    );
    
    //(* dont_touch = "yes" *)
    object_file #(
        .LSUS(LSUS),
        .BLOCKS(BLOCKS),
        .BLOCK_D(BLOCK_D),
        .BLOCK_W(BLOCK_W),
        .BLOCK_L(BLOCK_L),
        .OBJ_D(OBJ_D),
        .OBJ_W(OBJ_W),
        .OFFSET_W(BLOCK_W),
        .LSU_VADDR_W(LSU_VADDR_W),
        .LSU_TADDR_W(LSU_TADDR_W)
    ) object_file_i (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_alloc_en(w_alloc_en),
        .i_dealloc_en(w_dealloc_en),
        .i_blk_sel(w_blk_sel),
        .i_alloc_blk_base(w_alloc_base_addr),
        .i_dealloc_obj_addr(w_dealloc_obj_addr),
        .i_dealloc_obj_size(w_dealloc_obj_size),
        .i_lsu_virt_addr(wi_lsu_virt_addr),
        
        .o_alloc_obj_vld(w_alloc_obj_vld),
        .o_alloc_obj_addr(w_alloc_obj_addr),
        .o_dealloc_base_addr(w_dealloc_base_addr),
        .o_lsu_trans_addr(w_lsu_trans_addr)
    );
    
    //(* dont_touch = "yes" *)
    compressor #(
        .BLOCKS(BLOCKS),
        .BITMAP(BLOCK_D),
        .NODES(NODES),
        .STAGES(STAGES),
        .BLOCK_W(BLOCK_W),
        .BLOCK_L(BLOCK_L)
    ) compressor_unit_i (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_dealloc_vld(w_dealloc_en),
        .i_dealloc_blk(w_blk_sel),
        .i_dealloc_addr(w_dealloc_base_addr),
        .i_dealloc_size(w_dealloc_obj_size),
        
        .o_dealloc_vld(w_vptr_wr_en),
        .o_dealloc_blk(w_vptr_blk),
        .o_scb(w_vptr_scb)
    );
    
    //(* dont_touch = "yes" *)
    virtual_ptr_file #(
        .LSUS(LSUS),
        .BLOCKS(BLOCKS),
        .BLOCK_D(BLOCK_D),
        .BLOCK_W(BLOCK_W),
        .BLOCK_L(BLOCK_L),
        .NODES(NODES),
        .STAGES(STAGES),
        .LSU_TADDR_W(LSU_TADDR_W)
    ) virtual_pointer_file (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_dealloc_en(w_vptr_wr_en),
        .i_dealloc_blk_sel(w_vptr_blk),
        .i_scb(w_vptr_scb),
        .i_lsu_trans_addr(w_lsu_trans_addr),
        
        .o_lsu_mem_addr(o_lsu_mem_addr)
    );
    
endmodule
*/

module quick_page #(
        parameter REG_INPUTS            = 0,
        parameter REG_MEMORY            = 0,
        parameter CHANS                 = 1,                            // Number of independent translator channels
        parameter LSUS                  = 16,                            // Number of load/store units per channel
        parameter LINE_S                = 256,                          // Number of bytes per line
        parameter MEM_D                 = 1024,                          // Number of lines in heap
        parameter BLOCK_D               = 128,                          // Number of lines per block in heap / Search space
        parameter BLOCK_W               = $clog2(BLOCK_D),
        parameter BLOCKS                = MEM_D / BLOCK_D,
        parameter BLOCK_L               = (BLOCKS != 1) ? $clog2(BLOCKS) : 1,
        parameter REQ_S                 = BLOCK_D * LINE_S,             // Max allocable bytes
        parameter REQ_W                 = $clog2(REQ_S) + 1,
        parameter REP_W                 = BLOCK_L + 3*BLOCK_W + 1,  // Reply width is the physical blk + base_addr + size (additional 1 bit for full resolution) + offset (init to 0)
        parameter VADDR_W               = REP_W,
        parameter PADDR_W               = BLOCK_L + BLOCK_W,
        parameter REG_COMPR_STAGE       = 4,
        parameter ROW_ADDR_LATENCY      = 2                         // Valid values are 1 and 2
    )(
        input wire                              i_clk,
        input wire                              i_reset,
        input wire                              i_req_id,               // req_id must alternate for subsequent valid requests. Subsequent reqs with the same id will be ignored
        input wire  [1:0]                       i_req_func,             // 00 - idle ; 01 - alloc ; 10 - dealloc ; 11 - reserved;
        input wire  [REQ_W-1:0]                 i_req_alloc_size,       // size of alloc request in bytes
        input wire  [REP_W-1:0]                 i_req_dealloc_data,     // Object (block + obj_id + size) to be deallocated
        input wire  [VADDR_W*LSUS*CHANS-1:0]    i_virt_addr,        // Virtual address for translation in each LSU channel
        
        output wire                             o_busy,                // Backpressure signal for upstream procs | true while updating regs
        output wire                             o_rep_alloc_vld,        // 1 for valid reply
        output wire                             o_rep_dealloc_vld,      // 1 for valid dealloc
        output wire [REP_W-1:0]                 o_rep_data,             // Block_id + Obj_id + Size
        output wire [PADDR_W*LSUS*CHANS-1:0]    o_mem_addr          // Unregistered, translated physical addreses to BRAM module
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
    
    wire    [VADDR_W*LSUS-1:0]          w_chan_virt_addr[0:CHANS-1];
    //wire    [LSU_VADDR_W*LSUS-1:0]      w_lsu_virt_addr[0:CHANS-1];
    wire    [PADDR_W*LSUS-1:0]          w_chan_paddr[0:CHANS-1];
    
    wire                                wi_req_id;
    wire    [1:0]                       wi_req_func;
    wire    [REQ_W-1:0]                 wi_req_alloc_size;
    wire    [REP_W-1:0]                 wi_req_dealloc_data;
    wire    [VADDR_W*LSUS*CHANS-1:0]    wi_virt_addr;
    
    wire    [PADDR_W*LSUS*CHANS-1:0]    wo_mem_addr;
    
    genvar i;
    
    generate
        if (REG_INPUTS) begin
            reg                                 ri_req_id;
            reg     [1:0]                       ri_req_func;
            reg     [REQ_W-1:0]                 ri_req_alloc_size;
            reg     [REP_W-1:0]                 ri_req_dealloc_data;
            reg     [VADDR_W*LSUS*CHANS-1:0]    ri_virt_addr;
            
            assign wi_req_id = ri_req_id;
            assign wi_req_func = ri_req_func;
            assign wi_req_alloc_size = ri_req_alloc_size;
            assign wi_req_dealloc_data = ri_req_dealloc_data;
            assign wi_virt_addr = ri_virt_addr;
            
            always @(posedge i_clk) begin
                ri_req_id <= i_req_id;
                ri_req_func <= i_req_func;
                ri_req_alloc_size <= i_req_alloc_size;
                ri_req_dealloc_data <= i_req_dealloc_data;
                ri_virt_addr <= i_virt_addr;
            end
        end
        else begin
            assign wi_req_id = i_req_id;
            assign wi_req_func = i_req_func;
            assign wi_req_alloc_size = i_req_alloc_size;
            assign wi_req_dealloc_data = i_req_dealloc_data;
            assign wi_virt_addr = i_virt_addr;
        end
    endgenerate
    
    generate
        if (REG_MEMORY) begin
            reg     [PADDR_W*LSUS*CHANS-1:0]    r_mem_addr;
            
            assign o_mem_addr = r_mem_addr;
            
            always @(posedge i_clk) begin
                r_mem_addr <= (i_reset) ? 0 : wo_mem_addr;
            end
        end
        else begin
            assign o_mem_addr = wo_mem_addr;
        end
    endgenerate
    
    //(* dont_touch = "yes" *)
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
    
    //(* dont_touch = "yes" *)
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
    
    //(* dont_touch = "yes" *)
    compressor #(
        .BITMAP(BLOCK_D),
        .NODES(NODES),
        .STAGES(STAGES),
        .BLOCK_W(BLOCK_W),
        .BLOCK_L(BLOCK_L),
        .REG_STAGE(REG_COMPR_STAGE)                          // Set REG_STAGE = STAGES for register at final output
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
            assign w_chan_virt_addr[i] = wi_virt_addr[i*VADDR_W*LSUS +: VADDR_W*LSUS];
            //assign w_lsu_virt_addr[i] = w_chan_virt_addr[i][0 +: LSU_VADDR_W];
            
            assign wo_mem_addr[i*PADDR_W*LSUS +: PADDR_W*LSUS] = w_chan_paddr[i];
            
            address_translator #(
                .LSUS(LSUS),
                .BLOCKS(BLOCKS),
                .BLOCK_D(BLOCK_D),
                .BLOCK_W(BLOCK_W),
                .BLOCK_L(BLOCK_L),
                .NODES(NODES),
                .VADDR_W(VADDR_W),            // Address (Block_sel + obj_start loc + obj_offset) | OBJ_start = startign phy_addr
                .LSU_VADDR_W(LSU_VADDR_W),
                .PADDR_W(PADDR_W),
                .ROW_LATENCY(ROW_ADDR_LATENCY)
            ) addr_trans_i (
                .i_clk(i_clk),
                .i_reset(i_reset),
                .i_scb(w_chan_rd_scb[i]),                  // SCBs of selected block
                //.i_lsu_we(),               // Write enable signal for each lsu channel
                .i_chan_vaddr(w_chan_virt_addr[i]),            // Only LSU[0]'s blk_sel is used, rest ignored
                
                .o_blk_addr(w_chan_scb_addr[i]),             // Block select address to scb file
                //.o_lsu_we(),               // Write enable sig towards memory for each lsu channel
                .o_lsu_paddr(w_chan_paddr[i])             // Translated addresses towards memory
            );
        end
    endgenerate
    
endmodule