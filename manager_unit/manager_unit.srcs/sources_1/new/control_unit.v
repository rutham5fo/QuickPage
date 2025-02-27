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

// TODO:
// Add support for single line allocs.
// Currently, single line allocs will also consume an object.
// Fix - Single line allocs must return the physical addr instead of an object id composite

// For concurrent alloc/dealloc (un tested)
/*
module control_unit #(
        parameter LINE_S                = 256,                          // Number of bytes per line
        parameter MEM_D                 = 512,                          // Number of lines in heap
        parameter BLOCK_D               = 128,                          // Number of lines per block in heap / Search space
        parameter BLOCK_W               = $clog2(BLOCK_D),
        parameter BLOCKS                = MEM_D / BLOCK_D,
        parameter BLOCK_L               = $clog2(BLOCKS),
        parameter REQ_S                 = BLOCK_D * LINE_S,             // Max allocable bytes
        parameter REQ_W                 = $clog2(REQ_S) + 1,
        parameter OBJ_D                 = BLOCK_D >> 1,                 // Total number of allocable objects, PER BLOCK
        parameter OBJ_W                 = $clog2(OBJ_D),
        parameter REP_W                 = BLOCK_L + OBJ_W + BLOCK_W     // Reply width is composite obj_id (MSBs indicate block_id of object) + allocated size
    )(
        input wire                      i_clk,
        input wire                      i_reset,
        // From PU
        input wire                      i_req_alloc_vld,        // 1 for valid alloc request
        input wire  [REQ_W-1:0]         i_req_alloc_size,       // size of alloc request in bytes
        input wire                      i_req_dealloc_vld,
        input wire  [REP_W-1:0]         i_req_dealloc_obj,      // Object_id to be deallocated
        // From Object file
        input wire                      i_alloc_obj_vld,        // True when a free object is available in block
        input wire  [OBJ_W-1:0]         i_alloc_obj_addr,       // Address of free object in object file
        
        // To Object file and Compressor
        output wire                     o_alloc_blk_en,
        output wire [BLOCK_L-1:0]       o_alloc_blk_sel,
        output wire [BLOCK_W-1:0]       o_alloc_blk_addr,       // Base address (free_ptr) of current allocation
        output wire                     o_dealloc_blk_en,
        output wire [BLOCK_L-1:0]       o_dealloc_blk_sel,
        output wire [OBJ_W-1:0]         o_dealloc_blk_obj,      // Object id within the blk | Object file will produce the vptr address for compressor
        output wire [BLOCK_W-1:0]       o_dealloc_blk_size,
        
        // To PU
        output wire                     o_rep_alloc_vld,        // 1 for valid reply
        output wire                     o_rep_dealloc_vld,      // 1 for valid dealloc
        output wire [REP_W-1:0]         o_rep_alloc             // Block_id + Obj_id + Size
    );
        
    localparam LINE_W               = $clog2(LINE_S);
    
    wire    [BLOCK_W-1:0]           w_req_quo;
    wire    [BLOCK_W-1:0]           w_req_rem;
    wire    [BLOCK_W-1:0]           w_req_lines;
    
    wire    [BLOCKS-1:0]            w_free_alloc_en;
    wire    [BLOCKS-1:0]            w_free_dealloc_en;
    
    wire    [BLOCK_L-1:0]           w_dealloc_blk_sel;
    wire    [BLOCK_W-1:0]           w_dealloc_blk_size;
    wire    [OBJ_W-1:0]             w_dealloc_blk_obj;
    
    wire    [BLOCK_L-1:0]           w_lock_block;
    
    reg     [BLOCK_W-1:0]           r_free_ptr[0:BLOCKS-1];                 // Regfile holding free ptr location within each block
    reg     [BLOCK_L-1:0]           r_lock_block;                           // Mutex lock from deallocator to mask block during allocation
    reg                             r_rep_alloc_vld;
    reg                             r_rep_dealloc_vld;
    reg     [REP_W-1:0]             r_rep_alloc;
    
    reg     [BLOCK_L-1:0]           r_alloc_blk_sel;
    reg                             r_alloc_blk_found;
    
    integer k;
    
    assign w_req_rem = i_req_alloc_size & (LINE_S - 1);
    assign w_req_quo = i_req_alloc_size >> LINE_W;
    assign w_req_lines = w_req_quo + w_req_rem;
    
    assign w_free_alloc_en = (i_alloc_obj_vld & r_alloc_blk_found) << r_alloc_blk_sel;            // i_alloc_obj_vld = o_alloc_blk_en & blk_obj_found
    assign w_free_dealloc_en = i_req_dealloc_vld << w_dealloc_blk_sel;
    
    assign w_dealloc_blk_sel = i_req_dealloc_obj[REP_W-1 -: BLOCK_L];
    assign w_dealloc_blk_size = i_req_dealloc_obj[0 +: BLOCK_W];
    assign w_dealloc_blk_obj = i_req_dealloc_obj[BLOCK_W +: OBJ_W];
    
    assign w_lock_block = i_req_dealloc_vld << w_dealloc_blk_sel;
    
    assign o_alloc_blk_en = r_alloc_blk_found;
    assign o_alloc_blk_sel = r_alloc_blk_sel;
    assign o_alloc_blk_addr = r_free_ptr[r_alloc_blk_sel];
    assign o_dealloc_blk_en = i_req_dealloc_vld;
    assign o_dealloc_blk_sel = w_dealloc_blk_sel;
    assign o_dealloc_blk_obj = w_dealloc_blk_obj;
    assign o_dealloc_blk_size = w_dealloc_blk_size;
    
    assign o_rep_alloc_vld = r_rep_alloc_vld;
    assign o_rep_dealloc_vld = r_rep_dealloc_vld;
    assign o_rep_alloc = r_rep_alloc;
    
    // Free ptr to keep track of available space in each block
    always @(posedge i_clk) begin
        for (k = 0; k < BLOCKS; k = k+1) begin
            if (i_reset) r_free_ptr[k] <= BLOCK_D - 1;
            else if (w_free_alloc_en[k] && !w_free_dealloc_en[k]) r_free_ptr[k] <= r_free_ptr[k] - w_req_lines;
            else if (!w_free_alloc_en[k] && w_free_dealloc_en[k]) r_free_ptr[k] <= r_free_ptr[k] + w_dealloc_blk_size;
            else if (w_free_alloc_en[k] && w_free_dealloc_en[k]) r_free_ptr[k] <= r_free_ptr[k] - w_req_lines + w_dealloc_blk_size;
            else r_free_ptr[k] <= r_free_ptr[k];
        end
    end
    
    always @(posedge i_clk) begin
        r_lock_block <= (i_reset) ? 0 : w_lock_block;
        r_rep_alloc_vld <= (i_reset) ? 0 : i_alloc_obj_vld;
        r_rep_dealloc_vld <= (i_reset) ? 0 : i_req_dealloc_vld;
        r_rep_alloc <= (i_reset) ? 0 : {r_alloc_blk_sel, i_alloc_obj_addr, w_req_lines};
    end
    
    // Block finder
    always @(*) begin
        r_alloc_blk_sel = 0;
        r_alloc_blk_found = 0;
        for (k = 0; k < BLOCKS; k = k+1) begin
            if ((r_free_ptr[k] + 1) >= w_req_lines && !r_lock_block[k]) begin
                r_alloc_blk_sel = k;
                r_alloc_blk_found = i_req_alloc_vld;
            end
        end
    end
    
endmodule
*/
/*
module control_unit #(
        parameter LINE_S                = 256,                          // Number of bytes per line
        parameter MEM_D                 = 512,                          // Number of lines in heap
        parameter BLOCK_D               = 128,                          // Number of lines per block in heap / Search space
        parameter BLOCK_W               = $clog2(BLOCK_D),
        parameter BLOCKS                = MEM_D / BLOCK_D,
        parameter BLOCK_L               = $clog2(BLOCKS),
        parameter REQ_S                 = BLOCK_D * LINE_S,             // Max allocable bytes
        parameter REQ_W                 = $clog2(REQ_S) + 1,
        parameter OBJ_D                 = BLOCK_D >> 1,                 // Total number of allocable objects, PER BLOCK
        parameter OBJ_W                 = $clog2(OBJ_D),
        parameter REP_W                 = BLOCK_L + OBJ_W + 2*BLOCK_W   // Reply width is composite obj_id (MSBs indicate block_id of object) + allocated size
    )(
        input wire                      i_clk,
        input wire                      i_reset,
        // From PU
        input wire                      i_req_id,               // req_id must alternate for subsequent valid requests. Subsequent reqs with the same id will be ignored
        input wire  [1:0]               i_req_func,             // 00 - idle ; 01 - alloc ; 10 - dealloc ; 11 - reserved;
        input wire  [REQ_W-1:0]         i_req_alloc_size,       // size of alloc request in bytes
        input wire  [REP_W-1:0]         i_req_dealloc_obj,      // Object_id to be deallocated
        // From Object file
        input wire                      i_alloc_obj_vld,        // True when a free object is available in block
        input wire  [OBJ_W-1:0]         i_alloc_obj_addr,       // Address of free object in object file
        
        // To Object file and Compressor
        output wire                     o_alloc_blk_en,
        output wire                     o_dealloc_blk_en,
        output wire [BLOCK_L-1:0]       o_blk_sel,
        output wire [BLOCK_W-1:0]       o_alloc_blk_addr,       // Base address (free_ptr) of current allocation
        output wire [OBJ_W-1:0]         o_dealloc_blk_obj,      // Object id within the blk | Object file will produce the vptr address for compressor
        output wire [BLOCK_W-1:0]       o_dealloc_blk_size,
        
        // To upstream
        output wire                     o_stall,                // Stall signal asserted for a single update cycle
        
        // To PU
        output wire                     o_rep_alloc_vld,        // 1 for valid reply
        output wire                     o_rep_dealloc_vld,      // 1 for valid dealloc
        output wire [REP_W-1:0]         o_rep_data              // Block_id + Obj_id + Size
    );
        
    localparam LINE_W               = $clog2(LINE_S);
    
    wire    [BLOCK_W-1:0]           w_req_quo;
    wire    [BLOCK_W-1:0]           w_req_rem;
    wire    [BLOCK_W-1:0]           w_req_lines;
    
    wire                            w_blk_found;
    wire    [BLOCK_L-1:0]           w_blk_sel;
    wire    [BLOCKS-1:0]            w_free_ptr_en;
    wire    [BLOCK_L-1:0]           w_dealloc_blk_sel;
    wire    [BLOCK_W-1:0]           w_dealloc_blk_size;
    wire    [OBJ_W-1:0]             w_dealloc_blk_obj;
    
    wire                            w_alloc_vld;
    wire                            w_dup_req;                              // True if previous req id == current req id | ignores duplicate reqs
    wire    [BLOCKS-1:0]            w_block_overflow;                       // True when free_ptr is negative, i.e, r_free_ptr lt 0 and block is full
    
    //reg     [BLOCK_W-1:0]           r_free_ptr[0:BLOCKS-1];                 // Regfile holding free ptr location within each block
    reg     [BLOCK_W:0]             r_free_ptr[0:BLOCKS-1];                 // Regfile holding free ptr location within each block | MSB marks overflow/block full
    reg                             r_rep_alloc_vld;
    reg                             r_rep_dealloc_vld;
    reg     [REP_W-1:0]             r_rep_data;
    
    reg     [BLOCK_L-1:0]           rt_alloc_blk_sel;
    reg                             rt_alloc_blk_found;
    
    reg                             r_alloc_blk_found;
    reg     [BLOCK_L-1:0]           r_alloc_blk_sel;
    reg                             r_dealloc_vld;
    reg                             r_stall;
    reg                             r_alloc_blk_en;
    reg                             r_dealloc_blk_en;
    reg                             r_req_id;
    reg     [BLOCK_W-1:0]           r_req_lines;
    reg     [BLOCK_L-1:0]           r_blk_sel;
    reg     [BLOCK_W-1:0]           r_alloc_blk_addr;
    reg     [OBJ_W-1:0]             r_dealloc_blk_obj;
    reg     [BLOCK_W-1:0]           r_dealloc_blk_size;
    
    genvar i;
    
    integer k;
    
    assign w_req_rem = i_req_alloc_size & (LINE_S - 1);
    assign w_req_quo = i_req_alloc_size >> LINE_W;
    assign w_req_lines = w_req_quo + w_req_rem;
    
    assign w_blk_sel = (i_req_func[1]) ? w_dealloc_blk_sel : rt_alloc_blk_sel;
    assign w_blk_found = (i_req_func[1]) ? 1'b1 : rt_alloc_blk_found;
    assign w_dealloc_blk_sel = i_req_dealloc_obj[REP_W-1 -: BLOCK_L];
    assign w_dealloc_blk_size = i_req_dealloc_obj[BLOCK_W +: BLOCK_W];
    assign w_dealloc_blk_obj = i_req_dealloc_obj[2*BLOCK_W +: OBJ_W];
    assign w_free_ptr_en = w_blk_found << w_blk_sel;
    
    assign w_alloc_vld = i_alloc_obj_vld & r_alloc_blk_found;
    assign w_dup_req = ~(i_req_id ^ r_req_id);
    
    //assign o_alloc_blk_en = r_alloc_blk_found;
    //assign o_dealloc_blk_en = i_req_func[1];
    //assign o_blk_sel = (i_req_func[1]) ? w_dealloc_blk_sel : r_alloc_blk_sel;
    //assign o_alloc_blk_addr = r_free_ptr[r_alloc_blk_sel];
    //assign o_dealloc_blk_obj = w_dealloc_blk_obj;
    //assign o_dealloc_blk_size = w_dealloc_blk_size;
    
    assign o_alloc_blk_en = r_alloc_blk_en;
    assign o_dealloc_blk_en = r_dealloc_blk_en;
    assign o_blk_sel = r_blk_sel;
    assign o_alloc_blk_addr = r_alloc_blk_addr;
    assign o_dealloc_blk_obj = r_dealloc_blk_obj;
    assign o_dealloc_blk_size = r_dealloc_blk_size;
    assign o_stall = r_stall;
    
    assign o_rep_alloc_vld = r_rep_alloc_vld;
    assign o_rep_dealloc_vld = r_rep_dealloc_vld;
    assign o_rep_data = r_rep_data;
    
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
        r_alloc_blk_found = 0;
        r_alloc_blk_sel = 0;
        r_dealloc_vld = 0;
        r_req_lines = 0;
        r_blk_sel = 0;
        r_alloc_blk_en = 0;
        r_dealloc_blk_en = 0;
        r_alloc_blk_addr = 0;
        r_dealloc_blk_obj = 0;
        r_dealloc_blk_size = 0;
        r_rep_data = 0;
    end
    
    always @(posedge i_clk) begin
        r_req_id <= (i_reset) ? 0 : i_req_id;
        r_req_lines <= (r_stall) ? r_req_lines : w_req_lines;
        r_dealloc_vld <= i_req_func[1];
        r_alloc_blk_found <= (r_stall) ? r_alloc_blk_found : rt_alloc_blk_found;
        r_alloc_blk_sel <= (r_stall) ? r_alloc_blk_sel : rt_alloc_blk_sel;
        //r_rep_alloc_vld <= (i_reset || r_stall || w_dup_req) ? 0 : w_alloc_vld;
        r_rep_alloc_vld <= (i_reset || !r_stall) ? 0 : w_alloc_vld;
        //r_rep_dealloc_vld <= (i_reset || r_stall || w_dup_req) ? 0 : i_req_func[1];
        r_rep_dealloc_vld <= (i_reset || !r_stall) ? 0 : r_dealloc_vld;
        //r_rep_data <= (i_reset) ? 0 : (w_alloc_vld && !(r_stall || w_dup_req)) ? {r_alloc_blk_sel, i_alloc_obj_addr, w_req_lines, {BLOCK_W{1'b0}}} : r_rep_data;
        r_rep_data <= (w_alloc_vld && r_stall) ? {r_alloc_blk_sel, i_alloc_obj_addr, r_req_lines, {BLOCK_W{1'b0}}} : r_rep_data;
        //r_alloc_blk_en <= (i_reset || r_stall || w_dup_req) ? 0 : r_alloc_blk_found;
        //r_dealloc_blk_en <= (i_reset || r_stall || w_dup_req) ? 0 : i_req_func[1];
        //r_blk_sel <= (i_reset) ? 0 : w_blk_sel;
        //r_alloc_blk_addr <= (i_reset) ? 0 : r_free_ptr[r_alloc_blk_sel];
        //r_dealloc_blk_obj <= (i_reset) ? 0 : w_dealloc_blk_obj;
        //r_dealloc_blk_size <= (i_reset) ? 0 : w_dealloc_blk_size;
        r_alloc_blk_en <= (i_reset || r_stall || w_dup_req) ? 0 : rt_alloc_blk_found;
        r_dealloc_blk_en <= (i_reset || r_stall || w_dup_req) ? 0 : i_req_func[1];
        r_blk_sel <= w_blk_sel;
        r_alloc_blk_addr <= r_free_ptr[r_alloc_blk_sel];
        r_dealloc_blk_obj <= w_dealloc_blk_obj;
        r_dealloc_blk_size <= w_dealloc_blk_size;
    end
    
    always @(posedge i_clk) begin
        if(i_reset) r_stall <= 1'b0;
        else if(i_req_func && !r_stall && !w_dup_req) r_stall <= 1'b1;
        else if (r_stall) r_stall <= 1'b0;
    end
    
    // Block finder
    always @(*) begin
        rt_alloc_blk_sel = 0;
        rt_alloc_blk_found = 0;
        for (k = 0; k < BLOCKS; k = k+1) begin
            if ((r_free_ptr[k] + 1) >= w_req_lines && !w_block_overflow[k]) begin
                rt_alloc_blk_sel = k;
                rt_alloc_blk_found = (i_req_func[0] & |w_req_lines);
            end
        end
    end
    
endmodule
*/

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
    reg     [2:0]                   r_dealloc_vld;
    reg                             r_req_id;
    reg     [BLOCK_W:0]             r_req_lines[0:1];
    reg     [BLOCK_L-1:0]           r_blk_sel;
    reg     [BLOCK_W-1:0]           r_alloc_free_ptr;
    reg     [BLOCK_W-1:0]           r_dealloc_blk_base;
    reg     [BLOCK_W:0]             r_dealloc_blk_size[1:0];
    
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
    
    assign o_dealloc_blk_en = r_dealloc_vld[1];
    assign o_blk_sel = r_blk_sel;
    assign o_alloc_free_ptr = r_alloc_free_ptr;
    assign o_dealloc_blk_base = r_dealloc_blk_base;
    assign o_dealloc_blk_size = r_dealloc_blk_size[1];
    
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
            r_dealloc_blk_size[k] = 0;
        end
    end
    
    always @(posedge i_clk) begin
        r_req_id <= (i_reset) ? 0 : i_req_id;
        r_req_lines[0] <= w_req_lines;
        r_req_lines[1] <= r_req_lines[0];
        r_alloc_vld <= (i_reset) ? 0 : {r_alloc_vld[0], w_alloc_vld};
        r_rep_alloc_vld <= r_alloc_vld[1];
        r_dealloc_vld <= (i_reset) ? 0 : {r_dealloc_vld[0 +: 2], w_dealloc_vld};
        r_rep_dealloc_vld <= r_dealloc_vld[2];
        r_rep_data <= (r_alloc_vld[1]) ? {r_req_lines[1], r_alloc_blk_sel[1], i_alloc_blk_base} << BLOCK_W : r_rep_data;
        r_alloc_blk_sel[0] <= rt_alloc_blk_sel;
        r_alloc_blk_sel[1] <= r_alloc_blk_sel[0];
        r_blk_sel <= w_blk_sel;
        r_alloc_free_ptr <= rt_alloc_free_ptr;
        r_dealloc_blk_base <= w_dealloc_blk_base;
        r_dealloc_blk_size[0] <= w_dealloc_blk_size;
        r_dealloc_blk_size[1] <= r_dealloc_blk_size[0];
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
    
    //always @(posedge i_clk) begin
    //    if (i_reset) r_stall <= 1'b0;
    //    else if (w_dealloc_vld && !r_stall) r_stall <= 1'b1;
    //    else if (r_stall && r_dealloc_vld[2]) r_stall <= 1'b0;
    //    else r_stall <= r_stall;
    //end
    
    always @(posedge i_clk) begin
        if (i_reset) r_stall <= 1'b0;
        else if ((w_alloc_vld || w_dealloc_vld) && !r_stall) r_stall <= 1'b1;
        else if (r_stall && (r_alloc_vld[1] || r_dealloc_vld[2])) r_stall <= 1'b0;
        else r_stall <= r_stall;
    end
    
endmodule
