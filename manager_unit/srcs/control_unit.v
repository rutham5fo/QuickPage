`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 17.02.2025 11:11:32
// Design Name: 
// Module Name: control_unit
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


module control_unit #(
        parameter LINE_S                = 256,                          // Number of bytes per line
        parameter MEM_D                 = 512,                          // Number of lines in heap
        parameter BLOCK_D               = 128,                          // Number of lines per block in heap / Search space
        parameter BLOCK_W               = $clog2(BLOCK_D),
        parameter BLOCKS                = MEM_D / BLOCK_D,
        parameter BLOCK_L               = $clog2(BLOCKS),
        parameter NODES                 = BLOCK_D >> 1,
        parameter REQ_S                 = BLOCK_D * LINE_S,             // Max allocable bytes
        parameter REQ_W                 = $clog2(REQ_S) + 1,
        parameter REP_W                 = BLOCK_L + 3*BLOCK_W + 1          // Reply width is the physical blk + base_addr + size (additional 1 bit for full resolution) + offset (init to 0)
    )(
        input wire                      i_clk,
        input wire                      i_reset,
        // From PU
        input wire                      i_req_id,               // req_id must alternate for subsequent valid requests. Subsequent reqs with the same id will be ignored
        input wire  [1:0]               i_req_func,             // 00 - idle ; 01 - alloc ; 10 - dealloc ; 11 - reserved;
        input wire  [REQ_W-1:0]         i_req_alloc_size,       // size of alloc request in bytes
        input wire  [REP_W-1:0]         i_req_dealloc_obj,      // Object_id to be deallocated
        // From alloc_decoder
        input wire  [BLOCK_W-1:0]       i_alloc_blk_base,
        
        // To SCB file and Compressor
        output wire                     o_dealloc_blk_en,
        output wire [BLOCK_L-1:0]       o_blk_sel,
        output wire [BLOCK_W-1:0]       o_alloc_free_ptr,      // Base address (free_ptr) of current allocation
        output wire [BLOCK_W-1:0]       o_dealloc_blk_base,      // Object id within the blk | Object file will produce the vptr address for compressor
        output wire [BLOCK_W:0]         o_dealloc_blk_size,
        
        // To upstream procs
        output wire                     o_stall,
        
        // To PU
        output wire                     o_rep_alloc_vld,        // 1 for valid reply
        output wire                     o_rep_dealloc_vld,      // 1 for valid dealloc
        output wire [REP_W-1:0]         o_rep_data
    );
        
    localparam LINE_W               = $clog2(LINE_S);
    
    wire    [BLOCK_W:0]             w_req_quo;
    wire    [BLOCK_W:0]             w_req_rem;
    wire    [BLOCK_W:0]             w_req_lines;
    
    wire                            w_blk_found;
    wire    [BLOCK_L-1:0]           w_blk_sel;
    wire    [BLOCKS-1:0]            w_free_ptr_en;
    wire    [BLOCK_L-1:0]           w_dealloc_blk_sel;
    wire    [BLOCK_W:0]             w_dealloc_blk_size;
    wire    [BLOCK_W-1:0]           w_dealloc_blk_base;
    
    wire                            w_alloc_vld;
    wire                            w_dealloc_vld;
    wire                            w_dup_req;                              // True if previous req id == current req id | ignores duplicate reqs
    wire    [BLOCKS-1:0]            w_block_overflow;                       // True when free_ptr is negative, i.e, r_free_ptr lt 0 and block is full
    
    reg     [BLOCK_W:0]             r_free_ptr[0:BLOCKS-1];                 // Regfile holding free ptr location within each block | MSB marks overflow/block full
    reg                             r_rep_alloc_vld;
    reg                             r_rep_dealloc_vld;
    reg     [REP_W-1:0]             r_rep_data;
    
    reg     [BLOCK_L-1:0]           rt_alloc_blk_sel;
    reg     [BLOCK_W-1:0]           rt_alloc_free_ptr;
    reg                             rt_alloc_blk_found;
    
    reg                             r_stall;
    reg     [BLOCK_L-1:0]           r_alloc_blk_sel[0:1];
    reg     [1:0]                   r_alloc_vld;
    reg     [3:0]                   r_dealloc_vld;
    reg                             r_req_id;
    reg     [BLOCK_W:0]             r_req_lines[0:1];
    reg     [BLOCK_L-1:0]           r_blk_sel;
    reg     [BLOCK_W-1:0]           r_alloc_free_ptr;
    reg     [BLOCK_W-1:0]           r_dealloc_blk_base;
    reg     [BLOCK_W:0]             r_dealloc_blk_size[0:2];
    
    genvar i;
    
    integer k;
    
    assign w_req_rem = i_req_alloc_size & (LINE_S - 1);
    assign w_req_quo = i_req_alloc_size >> LINE_W;
    assign w_req_lines = w_req_quo + w_req_rem;
    
    assign w_blk_sel = (i_req_func[1]) ? w_dealloc_blk_sel : rt_alloc_blk_sel;
    assign w_blk_found = (i_req_func[1]) ? 1'b1 : rt_alloc_blk_found;
    assign w_dealloc_blk_sel = i_req_dealloc_obj[REP_W-BLOCK_W-2 -: BLOCK_L];
    assign w_dealloc_blk_size = i_req_dealloc_obj[REP_W-1 -: BLOCK_W+1];
    assign w_dealloc_blk_base = i_req_dealloc_obj[BLOCK_W +: BLOCK_W];
    assign w_free_ptr_en = w_blk_found << w_blk_sel;
    
    assign w_alloc_vld = i_req_func[0] & rt_alloc_blk_found & ~w_dup_req;
    assign w_dealloc_vld = i_req_func[1] & ~w_dup_req;
    assign w_dup_req = ~(i_req_id ^ r_req_id);
    
    assign o_dealloc_blk_en = r_dealloc_vld[2];
    assign o_blk_sel = r_blk_sel;
    assign o_alloc_free_ptr = r_alloc_free_ptr;
    assign o_dealloc_blk_base = r_dealloc_blk_base;
    assign o_dealloc_blk_size = r_dealloc_blk_size[2];
    
    assign o_rep_alloc_vld = r_rep_alloc_vld;
    assign o_rep_dealloc_vld = r_rep_dealloc_vld;
    assign o_rep_data = r_rep_data;
    
    assign o_stall = r_stall;
    
    generate
        for (i = 0; i < BLOCKS; i = i+1) begin              :   gen_block_full
            assign w_block_overflow[i] = r_free_ptr[i][BLOCK_W];
        end
    endgenerate
    
    // Free ptr to keep track of available space in each block
    always @(posedge i_clk) begin
        for (k = 0; k < BLOCKS; k = k+1) begin
            if (i_reset) r_free_ptr[k] <= BLOCK_D - 1;
            else if (i_req_func == 2'b01 && !w_dup_req && w_free_ptr_en[k]) r_free_ptr[k] <= r_free_ptr[k] - w_req_lines;
            else if (i_req_func == 2'b10 && !w_dup_req && w_free_ptr_en[k]) r_free_ptr[k] <= r_free_ptr[k] + w_dealloc_blk_size;
            else r_free_ptr[k] <= r_free_ptr[k];
        end
    end
    
    // Power init
    initial begin
        r_alloc_vld = 0;
        r_rep_alloc_vld = 0;
        r_dealloc_vld = 0;
        r_blk_sel = 0;
        r_alloc_free_ptr = 0;
        r_dealloc_blk_base = 0;
        r_rep_data = 0;
        for (k = 0; k < 2; k = k+1) begin
            r_alloc_blk_sel[k] = 0;
            r_req_lines[k] = 0;
        end
        for (k = 0; k < 3; k = k+1) begin
            r_dealloc_blk_size[k] = 0;
        end
    end
    
    always @(posedge i_clk) begin
        r_req_id <= (i_reset) ? 0 : i_req_id;
        r_req_lines[0] <= w_req_lines;
        r_req_lines[1] <= r_req_lines[0];
        r_alloc_vld <= (i_reset) ? 0 : {r_alloc_vld[0], w_alloc_vld};
        r_rep_alloc_vld <= r_alloc_vld[1];
        r_dealloc_vld <= (i_reset) ? 0 : {r_dealloc_vld[0 +: 3], w_dealloc_vld};
        r_rep_dealloc_vld <= r_dealloc_vld[3];
        r_rep_data <= (r_alloc_vld[1]) ? {r_req_lines[1], r_alloc_blk_sel[1], i_alloc_blk_base} << BLOCK_W : r_rep_data;
        r_alloc_blk_sel[0] <= rt_alloc_blk_sel;
        r_alloc_blk_sel[1] <= r_alloc_blk_sel[0];
        r_blk_sel <= w_blk_sel;
        r_alloc_free_ptr <= rt_alloc_free_ptr;
        r_dealloc_blk_base <= w_dealloc_blk_base;
        r_dealloc_blk_size[0] <= w_dealloc_blk_size;
        r_dealloc_blk_size[1] <= r_dealloc_blk_size[0];
        r_dealloc_blk_size[2] <= r_dealloc_blk_size[1];
    end
    
    // Block finder
    always @(*) begin
        rt_alloc_blk_sel = 0;
        rt_alloc_free_ptr = 0;
        rt_alloc_blk_found = 0;
        for (k = 0; k < BLOCKS; k = k+1) begin
            if ((r_free_ptr[k] + 1) >= w_req_lines && !w_block_overflow[k]) begin
                rt_alloc_blk_sel = k;
                rt_alloc_free_ptr = r_free_ptr[k];
                rt_alloc_blk_found = (i_req_func[0] & |w_req_lines);
            end
        end
    end
    
    always @(posedge i_clk) begin
        if (i_reset) r_stall <= 1'b0;
        else if ((w_alloc_vld || w_dealloc_vld) && !r_stall) r_stall <= 1'b1;
        else if (r_stall && (r_alloc_vld[1] || r_dealloc_vld[3])) r_stall <= 1'b0;
        else r_stall <= r_stall;
    end
    
endmodule
