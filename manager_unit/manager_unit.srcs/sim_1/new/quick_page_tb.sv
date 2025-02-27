`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 19.02.2025 11:37:59
// Design Name: 
// Module Name: quick_page_tb
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
module quick_page_tb;
    
    parameter CLK_PERIOD            = 10;
    parameter WR_DLY                = 1;
    parameter RD_DLY                = 1;
    
    parameter REG_INPUTS            = 0;
    parameter LSUS                  = 4;                            // Number of load/store units
    parameter LINE_S                = 4;                          // Number of bytes per line
    parameter MEM_D                 = 32;                          // Number of lines in heap
    parameter BLOCK_D               = 8;                          // Number of lines per block in heap / Search space
    parameter BLOCK_W               = $clog2(BLOCK_D);
    parameter BLOCKS                = MEM_D / BLOCK_D;
    parameter BLOCK_L               = $clog2(BLOCKS);
    parameter REQ_S                 = BLOCK_D * LINE_S;             // Max allocable bytes
    parameter REQ_W                 = $clog2(REQ_S) + 1;
    parameter OBJ_D                 = BLOCK_D >> 1;                 // Total number of allocable objects, PER BLOCK
    parameter OBJ_W                 = $clog2(OBJ_D);
    parameter REP_W                 = BLOCK_L + OBJ_W + 2*BLOCK_W;  // Reply width is composite obj_id (MSBs indicate block_id of object) + allocated size + reserved space for virtual offset
    parameter LSU_VADDR_W           = REP_W;
    parameter LSU_TADDR_W           = BLOCK_L + BLOCK_W;
    
    parameter MAX_OBJ               = OBJ_D * BLOCKS;
    parameter LSU_W                 = $clog2(LSUS);
    
    parameter f_IDLE                = 2'b00;
    parameter f_ALLOC               = 2'b01;
    parameter f_DEALLOC             = 2'b10;
    parameter f_RESERVED            = 2'b11;
    
    wire                            w_stall;
    wire                            w_rep_alloc_vld;
    wire                            w_rep_dealloc_vld;
    wire    [REP_W-1:0]             w_rep_data;
    wire    [LSU_VADDR_W*LSUS-1:0]  w_lsu_virt_addr;
    wire    [LSU_TADDR_W*LSUS-1:0]  w_lsu_mem_addr;
    
    wire    [BLOCK_L-1:0]           w_rep_data_block;
    wire    [OBJ_W-1:0]             w_rep_data_obj;
    wire    [BLOCK_W-1:0]           w_rep_data_size;
    wire    [BLOCK_W-1:0]           w_rep_data_offset;
    
    wire    [BLOCK_L+OBJ_W-1:0]     w_rep_global_obj;
    
    wire    [LSU_TADDR_W-1:0]       w_lsu_mem_chan_addr[0:LSUS-1];
    wire    [BLOCK_L-1:0]           w_lsu_mem_chan_block[0:LSUS-1];
    wire    [BLOCK_W-1:0]           w_lsu_mem_chan_offset[0:LSUS-1];
    
    reg                             s_clk;
    reg                             s_reset;
    reg                             s_req_id;
    reg     [1:0]                   s_req_func;             // 00 - IDLE, 01 - ALLOC, 10 - DEALLOC, 11 - RESERVED
    reg     [REQ_W-1:0]             s_req_alloc_size;       // size in bytes
    reg     [REP_W-1:0]             s_req_dealloc_data;
    reg     [LSU_VADDR_W-1:0]       s_virt_addr[0:LSUS-1];
    
    reg     [REP_W-1:0]             r_obj[0:MAX_OBJ-1];
    
    genvar i;
    
    integer k;
    
    task alloc (
        input [7:0]         req_id,
        input [REQ_W-1:0]   req_size
    );
        s_req_id = ~s_req_id;
        s_req_func = f_ALLOC;
        s_req_alloc_size = req_size;
        @(negedge w_stall);
        //r_obj[w_rep_global_obj] = w_rep_data;
        r_obj[req_id] = w_rep_data;
        //$display("%t:   ALLOC   || req_id = %0d, req_size = %0d, rep_vld = %0d | rep_data = %0h", $time, s_req_id, req_size, w_rep_alloc_vld, w_rep_data);
        // re-introduce input dly
        #WR_DLY;
    endtask
    
    task dealloc (
        input [REP_W-1:0]   req_data
    );
        s_req_id = ~s_req_id;
        s_req_func = f_DEALLOC;
        s_req_dealloc_data = req_data;
        @(negedge w_stall);
        // re-introduce input dly
        #WR_DLY;
    endtask
    
    task get_addr (
        input [LSU_W-1:0]       chan_sel,
        input [LSU_VADDR_W-1:0] obj_addr,
        input [BLOCK_W-1:0]     offset
    );
        s_virt_addr[chan_sel] = obj_addr + offset;
    endtask
    
    // Break down rep_data
    assign w_rep_data_block = w_rep_data[REP_W-1 -: BLOCK_L];
    assign w_rep_data_obj = w_rep_data[REP_W-BLOCK_L-1 -: OBJ_W];
    assign w_rep_data_size = w_rep_data[BLOCK_W +: BLOCK_W];
    assign w_rep_data_offset = w_rep_data[0 +: BLOCK_W];
    
    assign w_rep_global_obj = {w_rep_data_block, w_rep_data_obj};
    
    generate
        for (i = 0; i < LSUS; i = i+1) begin            :   gen_lsu_virt_addr
            assign w_lsu_virt_addr[i*LSU_VADDR_W +: LSU_VADDR_W] = s_virt_addr[i];
            assign w_lsu_mem_chan_addr[i] = w_lsu_mem_addr[i*LSU_TADDR_W +: LSU_TADDR_W];
            assign w_lsu_mem_chan_block[i] = w_lsu_mem_chan_addr[i][BLOCK_W +: BLOCK_L];
            assign w_lsu_mem_chan_offset[i] = w_lsu_mem_chan_addr[i][0 +: BLOCK_W];
        end
    endgenerate
        
    quick_page #(
        .REG_INPUTS(REG_INPUTS),
        .LSUS(LSUS),                            // Number of load/store unit channels
        .LINE_S(LINE_S),                          // Number of bytes per line
        .MEM_D(MEM_D),                          // Number of lines in heap
        .BLOCK_D(BLOCK_D),                          // Number of lines per block in heap / Search space
        .BLOCK_W(BLOCK_W),
        .BLOCKS(BLOCKS),
        .BLOCK_L(BLOCK_L),
        .REQ_S(REQ_S),             // Max allocable bytes
        .REQ_W(REQ_W),
        .OBJ_D(OBJ_D),                 // Total number of allocable objects, PER BLOCK
        .OBJ_W(OBJ_W),
        .REP_W(REP_W),    // Reply width is composite obj_id (MSBs indicate block_id of object) + allocated size
        .LSU_VADDR_W(LSU_VADDR_W),
        .LSU_TADDR_W(LSU_TADDR_W)
    ) quickie_i (
        .i_clk(s_clk),
        .i_reset(s_reset),
        .i_req_id(s_req_id),               // req_id must alternate for subsequent valid requests. Subsequent reqs with the same id will be ignored
        .i_req_func(s_req_func),             // 00 - idle ; 01 - alloc ; 10 - dealloc ; 11 - reserved;
        .i_req_alloc_size(s_req_alloc_size),       // size of alloc request in bytes
        .i_req_dealloc_data(s_req_dealloc_data),      // Object (block + obj_addr + size) to be deallocated
        .i_lsu_virt_addr(w_lsu_virt_addr),
        
        .o_stall(w_stall),
        .o_rep_alloc_vld(w_rep_alloc_vld),        // 1 for valid reply
        .o_rep_dealloc_vld(w_rep_dealloc_vld),      // 1 for valid dealloc
        .o_rep_data(w_rep_data),             // Block_id + Obj_id + Size = object
        .o_lsu_mem_addr(w_lsu_mem_addr)          // Unregistered, goes to BRAM modules
    );
    
    always #(CLK_PERIOD/2) s_clk = ~s_clk;
    
    initial begin
        // Init sigs
        k = 0;
        s_clk = 1'b1;
        s_reset = 1'b0;
        s_req_id = 1'b0;
        s_req_func = f_IDLE;
        s_req_alloc_size = 0;
        s_req_dealloc_data = 0;
        for (k = 0; k < LSUS; k = k+1) begin
            s_virt_addr[k] = 0;
        end
        for (k = 0; k < MAX_OBJ; k = k+1) begin
            r_obj[k] = 0;
        end
        // Cause input delay
        #WR_DLY;
        
        // reset
        s_reset = 1'b1;
        #(CLK_PERIOD*2);
        s_reset = 1'b0;
        #(CLK_PERIOD*2);
        
        // Alloc 0 ->   Size = 4 lines
        alloc (0, 4*LINE_S);
        
        // Alloc 1 ->   Size = 3 lines
        alloc (1, 3*LINE_S);
        
        // Alloc 2 ->   Size = 16 lines         || Should fail due to req_size rolling back to 0, i.e, lines requested exceeds allocation span (BLOCK_D)
        // Alloc with req_size = 0 is treated as an NOP
        alloc (2, 16*LINE_S);
        
        // Alloc 3 ->   Size = 1 line           || Triggers block_overflow (block_full)
        alloc (3, LINE_S);
        
        // Dealloc 1 -> Obj = Alloc 1
        dealloc (r_obj[1]);
        
        // Terminate
        #(CLK_PERIOD*4);
        $finish;
        
    end
    
endmodule
*/

module quick_page_tb;
    
    parameter CLK_PERIOD            = 10;
    parameter WR_DLY                = 1;
    parameter RD_DLY                = 1;
    
    parameter REG_INPUTS            = 0;
    parameter LSUS                  = 4;                            // Number of load/store units
    parameter LINE_S                = 4;                          // Number of bytes per line
    parameter MEM_D                 = 32;                          // Number of lines in heap
    parameter BLOCK_D               = 8;                          // Number of lines per block in heap / Search space
    parameter BLOCK_W               = $clog2(BLOCK_D);
    parameter BLOCKS                = MEM_D / BLOCK_D;
    parameter BLOCK_L               = $clog2(BLOCKS);
    parameter REQ_S                 = BLOCK_D * LINE_S;             // Max allocable bytes
    parameter REQ_W                 = $clog2(REQ_S) + 1;
    parameter REP_W                 = BLOCK_L + 3*BLOCK_W + 1;  // Reply width is composite obj_id (MSBs indicate block_id of object) + allocated size + reserved space for virtual offset
    parameter VADDR_W               = REP_W;
    parameter PADDR_W               = BLOCK_L + BLOCK_W;
    parameter REG_COMPR_STAGE       = 1;
    
    parameter MAX_OBJ               = 20;
    parameter LSU_W                 = $clog2(LSUS);
    
    parameter f_IDLE                = 2'b00;
    parameter f_ALLOC               = 2'b01;
    parameter f_DEALLOC             = 2'b10;
    parameter f_RESERVED            = 2'b11;
    
    wire                            w_busy;
    wire                            w_rep_alloc_vld;
    wire                            w_rep_dealloc_vld;
    wire    [REP_W-1:0]             w_rep_data;
    wire    [VADDR_W*LSUS-1:0]      w_virt_addr;
    wire    [PADDR_W*LSUS-1:0]      w_mem_addr;
    
    wire    [BLOCK_L-1:0]           w_rep_data_block;
    wire    [BLOCK_W-1:0]           w_rep_data_obj;
    wire    [BLOCK_W:0]             w_rep_data_size;
    wire    [BLOCK_W-1:0]           w_rep_data_offset;
    
    wire    [PADDR_W-1:0]           w_lsu_mem_chan_addr[0:LSUS-1];
    wire    [BLOCK_L-1:0]           w_lsu_mem_chan_block[0:LSUS-1];
    wire    [BLOCK_W-1:0]           w_lsu_mem_chan_offset[0:LSUS-1];
    
    reg                             s_clk;
    reg                             s_reset;
    reg                             s_req_id;
    reg     [1:0]                   s_req_func;             // 00 - IDLE, 01 - ALLOC, 10 - DEALLOC, 11 - RESERVED
    reg     [REQ_W-1:0]             s_req_alloc_size;       // size in bytes
    reg     [REP_W-1:0]             s_req_dealloc_data;
    reg     [VADDR_W-1:0]           s_virt_addr[0:LSUS-1];
    
    reg     [REP_W-1:0]             r_obj[0:MAX_OBJ-1];
    
    genvar i;
    
    integer k;
    
    task alloc (
        input [7:0]         req_id,
        input [REQ_W-1:0]   req_size
    );
        s_req_id = ~s_req_id;
        s_req_func = f_ALLOC;
        s_req_alloc_size = req_size;
        @(negedge w_busy);                    // Uncomment for un-piped alloc test
        r_obj[req_id] = w_rep_data;           // Uncomment for un-piped alloc test
        //@(posedge s_clk);                       // Uncomment for piped alloc test
        // re-introduce input dly
        #WR_DLY;
    endtask
    
    task dealloc (
        input [REP_W-1:0]   req_data
    );
        s_req_id = ~s_req_id;
        s_req_func = f_DEALLOC;
        s_req_dealloc_data = req_data;
        @(negedge w_busy);
        // re-introduce input dly
        #WR_DLY;
    endtask
    
    task get_addr (
        input [LSU_W-1:0]       chan_sel,
        input [VADDR_W-1:0]     obj_addr,
        input [BLOCK_W-1:0]     offset
    );
        s_virt_addr[chan_sel] = obj_addr + offset;
    endtask
    
    // Break down rep_data
    assign w_rep_data_block = w_rep_data[REP_W-BLOCK_W-2 -: BLOCK_L];
    assign w_rep_data_obj = w_rep_data[BLOCK_W +: BLOCK_W];
    assign w_rep_data_size = w_rep_data[REP_W-1 -: BLOCK_W+1];
    assign w_rep_data_offset = w_rep_data[0 +: BLOCK_W];
    
    assign w_rep_global_obj = {w_rep_data_block, w_rep_data_obj};
    
    generate
        for (i = 0; i < LSUS; i = i+1) begin            :   gen_lsu_virt_addr
            assign w_virt_addr[i*VADDR_W +: VADDR_W] = s_virt_addr[i];
            assign w_lsu_mem_chan_addr[i] = w_mem_addr[i*PADDR_W +: PADDR_W];
            assign w_lsu_mem_chan_block[i] = w_lsu_mem_chan_addr[i][BLOCK_W +: BLOCK_L];
            assign w_lsu_mem_chan_offset[i] = w_lsu_mem_chan_addr[i][0 +: BLOCK_W];
        end
    endgenerate
        
    quick_page #(
        .REG_INPUTS(REG_INPUTS),
        .LSUS(LSUS),                            // Number of load/store unit channels
        .LINE_S(LINE_S),                          // Number of bytes per line
        .MEM_D(MEM_D),                          // Number of lines in heap
        .BLOCK_D(BLOCK_D),                          // Number of lines per block in heap / Search space
        .BLOCK_W(BLOCK_W),
        .BLOCKS(BLOCKS),
        .BLOCK_L(BLOCK_L),
        .REQ_S(REQ_S),             // Max allocable bytes
        .REQ_W(REQ_W),
        .REP_W(REP_W),    // Reply width is composite obj_id (MSBs indicate block_id of object) + allocated size
        .VADDR_W(VADDR_W),
        .PADDR_W(PADDR_W),
        .REG_COMPR_STAGE(REG_COMPR_STAGE)
    ) quickie_i (
        .i_clk(s_clk),
        .i_reset(s_reset),
        .i_req_id(s_req_id),               // req_id must alternate for subsequent valid requests. Subsequent reqs with the same id will be ignored
        .i_req_func(s_req_func),             // 00 - idle ; 01 - alloc ; 10 - dealloc ; 11 - reserved;
        .i_req_alloc_size(s_req_alloc_size),       // size of alloc request in bytes
        .i_req_dealloc_data(s_req_dealloc_data),      // Object (block + obj_addr + size) to be deallocated
        .i_virt_addr(w_virt_addr),
        
        .o_busy(w_busy),
        .o_rep_alloc_vld(w_rep_alloc_vld),        // 1 for valid reply
        .o_rep_dealloc_vld(w_rep_dealloc_vld),      // 1 for valid dealloc
        .o_rep_data(w_rep_data),             // Block_id + Obj_id + Size = object
        .o_mem_addr(w_mem_addr)          // Unregistered, goes to BRAM modules
    );
    
    always #(CLK_PERIOD/2) s_clk = ~s_clk;
    
    initial begin
        // Init sigs
        k = 0;
        s_clk = 1'b1;
        s_reset = 1'b0;
        s_req_id = 1'b0;
        s_req_func = f_IDLE;
        s_req_alloc_size = 0;
        s_req_dealloc_data = 0;
        for (k = 0; k < LSUS; k = k+1) begin
            s_virt_addr[k] = 0;
        end
        for (k = 0; k < MAX_OBJ; k = k+1) begin
            r_obj[k] = 0;
        end
        // Cause input delay
        #WR_DLY;
        
        // reset
        s_reset = 1'b1;
        #(CLK_PERIOD*2);
        s_reset = 1'b0;
        #(CLK_PERIOD*2);
        
        // Alloc 0 ->   Size = 4 lines
        alloc (0, 4*LINE_S);
        
        // Alloc 1 ->   Size = 3 lines
        alloc (1, 3*LINE_S);
        
        // Alloc 2 ->   Size = 16 lines         || NOP due to req_size rolling back to 0, i.e, lines requested exceeds allocation span (BLOCK_D)
        // Alloc with req_size = 0 is treated as an NOP
        //alloc (2, 16*LINE_S);
        
        // Alloc 3 ->   Size = 1 line           || Triggers block_overflow (block_full)
        alloc (3, LINE_S);
        
        // The below tb is designed to test quick_page with un-piped alloc responeses
        // This is due to the rudementary design of tb to recieve replies from allocator
        
        // Dealloc 1 -> Obj = Alloc 1
        dealloc (r_obj[1]);
        
        // Alloc 4 ->   Size = 8 lines          || Trigger block overflow
        alloc (4, 8*LINE_S);
        
        // Alloc 5 ->   Size = 2 lines
        alloc (5, 2*LINE_S);
        
        // Alloc 6 ->   Size = 1 line           || Trigger block overflow
        alloc (6, LINE_S);
        
        // Address Translator tests
        get_addr (0, r_obj[5], 1);
        get_addr (1, r_obj[0], 3);
        get_addr (2, r_obj[6], 0);
        
        #(CLK_PERIOD*3);                        // 3 cycle latency due to Block addr change
        
        get_addr (1, r_obj[0], 0);
        
        #(CLK_PERIOD*2);                        // 2 cycle latency due to row/line addr change
        
        // Dealloc 2 -> Obj = Alloc 0
        dealloc (r_obj[0]);
        
        // Terminate
        #(CLK_PERIOD*4);                      // Uncomment for un-piped alloc test
        //#(CLK_PERIOD*8);                        // Uncomment for piped alloc test
        $finish;
        
    end
    
endmodule