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

/*
- Translator introduces NUMA.
- Col addr bypasses translator and is reflected directly in the BRAM addr.  | 1 cycle latency (inherent BRAM latency)
- Row (line) addr goes through a single stage of the translator             | 2 cycle latency
- Obj (start) addr goes through 2 stages of the translator                  | 3 cycle latency
- Therefore the write enable signal (we) is sent along with the col addr.
  This is to help mask the read/write latencies for consecutive accesses.
  The disadvantage is, the PU is now responsible for syncing addresses.
  
  EX:   With no address latency masking from PU
        (1) start = 3, line = 5, col = 1        | 1 cycle latency
        (2) start = 3, line = 5, col = 2        | 1 cycle latency
        (3) start = 3, line = 5, col = 3        | 1 cycle latency
        (4) start = 3, line = 6, col = 0        | 2 cycle latency   | 1 stall cycle seen by PU
        (5) start = 3, line = 6, col = 1        | 1 cycle latency
  
  EX:   With PU performing address latency masking
        (1) start = 3, line = 5, col = 1        | 1 cycle latency
        
        (2) start = 3, line = 6, col = 2        | 1 cycle latency   | The PU pre generates address line 6 since it knows line addr changes have 2 cycle latency (NUMA).
        (3) start = 3, line = 6, col = 3        | 1 cycle latency   | But the col addr will be immediately reflected, while the BRAM receives the old line addr = 5.
                                                                    | Hence the line addr change latency is masked.
        (4) start = 3, line = 6, col = 0        | 1 cycle latency   | no stall cycle seen by PU
        (5) start = 3, line = 6, col = 1        | 1 cycle latency
*/

/*
module address_translator #(
        parameter LSUS              = 2,
        parameter BLOCKS            = 4,
        parameter BLOCK_D           = 128,
        parameter BLOCK_W           = $clog2(BLOCK_D),
        parameter BLOCK_L           = $clog2(BLOCKS),
        parameter NODES             = BLOCK_D >> 1,
        parameter VADDR_W           = BLOCK_L + 3*BLOCK_W + 1,      // Address (Block_sel + obj_start loc + obj_offset) | OBJ_start = startign phy_addr
        parameter LSU_VADDR_W       = BLOCK_L + 2*BLOCK_W,
        parameter PADDR_W           = BLOCK_L + BLOCK_W
    )(
        input wire                      i_clk,
        input wire                      i_reset,
        input wire  [NODES*BLOCK_W-1:0] i_scb,                  // SCBs of selected block
        //input wire  [LSUS-1:0]          i_lsu_we,               // Write enable signal for each lsu channel
        input wire  [LSUS*VADDR_W-1:0]  i_chan_vaddr,            // Only LSU[0]'s blk_sel is used, rest ignored
        
        output wire [BLOCK_L-1:0]       o_blk_addr,             // Block select address to scb file
        //output wire [LSUS-1:0]          o_lsu_we,               // Write enable sig towards memory for each lsu channel
        output wire [LSUS*PADDR_W-1:0]  o_lsu_paddr             // Translated addresses towards memory
    );
    
    localparam LSU_W                    = $clog2(LSUS);
    
    wire    [LSU_VADDR_W-1:0]           w_lsu_vaddr[0:LSUS-1];      // Unpacked virtual address
    wire    [BLOCK_L-1:0]               w_lsu_blk[0:LSUS-1];
    wire    [BLOCK_W-1:0]               w_lsu_saddr[0:LSUS-1];      // Obj start location in block
    wire    [BLOCK_W-1:0]               w_lsu_soffset[0:LSUS-1];    // Obj_offset from start loc
    wire    [BLOCK_D-1:0]               w_lsu_taddr[0:LSUS-1];      // Select sig for object base on w_lsu_taddr
    //wire    [LSUS-1:0]                  w_lsu_base_we;
    //wire    [LSUS-1:0]                  w_lsu_line_we;
    
    wire    [BLOCK_D*LSUS-1:0]          w_tmap_down;                  // Translator map per lsu going into switch/translator
    wire    [BLOCK_D*LSUS-1:0]          w_tmap_up;
    
    wire    [NODES*BLOCK_W-1:0]         w_up_scb;                   // SCBs to up switch
    wire    [BLOCK_D*LSUS-1:0]          w_swd_map;                  // data from down switch
    wire    [BLOCK_D-1:0]               w_swd_lsu_map[0:LSUS-1];    // unpacked data from down switch
    wire    [BLOCK_D-1:0]               w_swd_lsu_omap[0:LSUS-1];   // switch up data shifted by offset
    
    wire    [BLOCK_D*LSUS-1:0]          w_swu_map;                  // data from switch up
    wire    [BLOCK_D-1:0]               w_swu_lsu_map[0:LSUS-1];    // unpacked data from switch up
    
    wire    [PADDR_W-1:0]               w_lsu_paddr[0:LSUS-1];
    //wire    [LSUS-1:0]                  w_lsu_we;
    
    reg     [BLOCK_W-1:0]               rt_lsu_taddr[0:LSUS-1];
    
    reg     [NODES*BLOCK_W-1:0]         r_up_scb;
    reg     [BLOCK_D-1:0]               r_swd_lsu_map[0:LSUS-1];    
    reg     [BLOCK_D-1:0]               r_swu_lsu_map[0:LSUS-1];
    //reg     [BLOCK_W-1:0]               r_lsu_base_addr[0:LSUS-1][0:1];
    //reg     [BLOCK_W-1:0]               r_lsu_line_addr[0:LSUS-1];
    //reg     [LSUS-1:0]                  r_lsu_base_we;
    //reg     [LSUS-1:0]                  r_lsu_line_we;
    reg     [BLOCK_L-1:0]               r_lsu_blk[0:LSUS-1];
    //reg     [PADDR_W-1:0]               r_lsu_paddr[0:LSUS-1];
    
    genvar i, j;
    
    integer k;
    
    assign w_up_scb = r_up_scb;
    
    assign o_blk_addr = w_lsu_blk[0];
    
    generate
        for (i = 0; i < LSUS; i = i+1) begin                            :   gen_lsus
            assign w_lsu_vaddr[i] = i_chan_vaddr[i*VADDR_W +: LSU_VADDR_W];
            assign w_lsu_blk[i] = w_lsu_vaddr[i][LSU_VADDR_W-1 -: BLOCK_L];
            assign w_lsu_saddr[i] = w_lsu_vaddr[i][BLOCK_W +: BLOCK_W];
            assign w_lsu_soffset[i] = w_lsu_vaddr[i][0 +: BLOCK_W];
            assign w_lsu_taddr[i] = 1'b1 << w_lsu_saddr[i];
            
            //assign w_swd_lsu_omap[i] = w_swd_lsu_map[i] >> w_lsu_soffset[i];
            assign w_swd_lsu_omap[i] = r_swd_lsu_map[i] >> w_lsu_soffset[i];
            
            //assign w_lsu_paddr[i] = r_lsu_paddr[i];
            assign w_lsu_paddr[i] = {r_lsu_blk[i], rt_lsu_taddr[i]};
            
            //assign w_lsu_base_we[i] = (r_lsu_base_addr[i][1] == w_lsu_saddr[i]) ? i_lsu_we[i] : 1'b0;
            //assign w_lsu_line_we[i] = (r_lsu_line_addr[i] == w_lsu_soffset[i]) ? i_lsu_we[i] : 1'b0;
            //assign w_lsu_we[i] = w_lsu_base_we[i] & w_lsu_line_we[i] & i_lsu_we[i];
            
            //assign o_lsu_we[i] = w_lsu_we[i];
            assign o_lsu_paddr[i*PADDR_W +: PADDR_W] = w_lsu_paddr[i];
        end
    endgenerate
    
    generate
        for (i = 0; i < LSUS; i = i+1) begin                            :   gen_tmap_0
            for (j = 0; j < BLOCK_D; j = j+1) begin                     :   gen_tmap_1
                assign w_tmap_down[j*LSUS+i] = w_lsu_taddr[i][j];
                assign w_swd_lsu_map[i][j] = w_swd_map[j*LSUS+i];
                
                assign w_tmap_up[j*LSUS+i] = w_swd_lsu_omap[i][j];
                assign w_swu_lsu_map[i][j] = w_swu_map[j*LSUS+i];
            end
        end
    endgenerate
    
    // Physical to virtual (switch down)
    //(* dont_touch = "yes" *)
    switch_down #(
        .PIPELINE(0),
        .INPUTS(BLOCK_D),
        .NODES(NODES),
        .DATA_W(LSUS),
        .STAGES(BLOCK_W)
    ) phy_virt_down_i (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_data(w_tmap_down),
        .i_scb(i_scb),
        
        .o_data(w_swd_map)
    );
    
    // Virtual to physical (switch up)
    //(* dont_touch = "yes" *)
    switch_up #(
        .PIPELINE(0),
        .INPUTS(BLOCK_D),
        .NODES(NODES),
        .DATA_W(LSUS),
        .STAGES(BLOCK_W)
    ) virt_phy_up_i (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_data(w_tmap_up),
        .i_scb(w_up_scb),
        
        .o_data(w_swu_map)
    );
    
    initial begin
        for (k = 0; k < LSUS; k = k+1) begin
            r_lsu_blk[k] = 0;
            //r_lsu_paddr[k] = 0;
            r_swd_lsu_map[k] = 0;
            r_swu_lsu_map[k] = 0;
            //r_lsu_base_addr[k][0] = 0;
            //r_lsu_base_addr[k][1] = 0;
            //r_lsu_line_addr[k] = 0;
        end
    end
    
    always @(posedge i_clk) begin
        for (k = 0; k < LSUS; k = k+1) begin
            r_lsu_blk[k] <= w_lsu_blk[k];
            //r_lsu_paddr[k] <= {r_lsu_blk[k], rt_lsu_taddr[k]};
            r_swd_lsu_map[k] <= w_swd_lsu_map[k];
            r_swu_lsu_map[k] <= w_swu_lsu_map[k];
            //r_lsu_base_addr[k][0] <= w_lsu_saddr[k];
            //r_lsu_base_addr[k][1] <= r_lsu_base_addr[k][0];
            //r_lsu_line_addr[k] <= w_lsu_soffset[k];
        end
    end
    
    generate
        for (i = 0; i < LSUS; i = i+1) begin                        :   gen_decoders
            always @(*) begin
                rt_lsu_taddr[i] = 0;
                for (k = 0; k < BLOCK_D; k = k+1) begin
                    //if (w_swu_lsu_map[i][k]) rt_lsu_taddr[i] = k;
                    if (r_swu_lsu_map[i][k]) rt_lsu_taddr[i] = k;
                end
            end
        end
    endgenerate
    
    initial begin
        r_up_scb = 0;
    end
    
    always @(posedge i_clk) begin
        r_up_scb <= i_scb;
    end
    
endmodule
*/

/*
- Translator introduces NUMA.
- Col addr bypasses translator and is reflected directly in the BRAM addr.  | 1 cycle latency (inherent BRAM latency)
- Row (line) addr goes through a single decoder stage of the translator.
  Hence depending on the interconnect complexity to memory, the address
  may/may-not be reflected immediately. But in best case ->                 | 1/2 cycle latency
- Obj (base_pointer) addr goes through 1 stages of the translator,
  followed by the address decoder.                                          | 2/3 cycle latency
- Therefore the write enable signal (we) is sent along with the col addr.
  This is to help mask the read/write latencies for consecutive accesses.
  The disadvantage is, the PU is now responsible for syncing addresses.
- Not shown below is the case when the Translation block changes.
  A block change requires 1 cycle to setup the register maps (pointers).    | 3/4 cycle latency
  
  EX:   With no address latency masking from PU
        (1) start = 3, line = 4, col = 1        | 1 cycle latency
        (2) start = 3, line = 4, col = 2        | 1 cycle latency
        (3) start = 3, line = 5, col = 3        | 1 cycle latency
        (4) start = 7, line = 6, col = 0        | 2 cycle latency   | 1 stall cycle seen by PU
        (5) start = 7, line = 6, col = 1        | 1 cycle latency
  
  EX:   With PU performing address latency masking
        (1) start = 3, line = 4, col = 1        | 1 cycle latency
        (2) start = 3, line = 4, col = 2        | 1 cycle latency
        (3) start = 7, line = 5, col = 3        | 1 cycle latency   | The PU pre generates base_pointer 7 since it knows base addr changes have 2 cycle latency (NUMA).
                                                                    | But the row/col addr will be immediately reflected. Hence the line addr change latency is masked.
                                                                    | No stall cycle seen by PU
        (4) start = 7, line = 6, col = 0        | 1 cycle latency 
        (5) start = 7, line = 6, col = 1        | 1 cycle latency

!!! NOTE => the position of the offset subtractor will impact the latency +- 1.
         => For a smaller search space (BLOCK_D), 1 cycle latency is acheivable,
            but for search_space = 128, 2 cycle latency is minimum.
*/

module address_translator #(
        parameter LSUS              = 2,
        parameter BLOCKS            = 4,
        parameter BLOCK_D           = 128,
        parameter BLOCK_W           = $clog2(BLOCK_D),
        parameter BLOCK_L           = $clog2(BLOCKS),
        parameter NODES             = BLOCK_D >> 1,
        parameter VADDR_W           = BLOCK_L + 3*BLOCK_W + 1,      // Address (Block_sel + obj_start loc + obj_offset) | OBJ_start = startign phy_addr
        parameter LSU_VADDR_W       = BLOCK_L + 2*BLOCK_W,
        parameter PADDR_W           = BLOCK_L + BLOCK_W,
        parameter ROW_LATENCY       = 1
    )(
        input wire                      i_clk,
        input wire                      i_reset,
        input wire  [NODES*BLOCK_W-1:0] i_scb,                  // SCBs of selected block
        //input wire  [LSUS-1:0]          i_lsu_we,               // Write enable signal for each lsu channel
        input wire  [LSUS*VADDR_W-1:0]  i_chan_vaddr,            // Only LSU[0]'s blk_sel is used, rest ignored
        
        output wire [BLOCK_L-1:0]       o_blk_addr,             // Block select address to scb file
        //output wire [LSUS-1:0]          o_lsu_we,               // Write enable sig towards memory for each lsu channel
        output wire [LSUS*PADDR_W-1:0]  o_lsu_paddr             // Translated addresses towards memory
    );
    
    localparam LSU_W                    = $clog2(LSUS);
    
    wire    [LSU_VADDR_W-1:0]           w_lsu_vaddr[0:LSUS-1];      // Unpacked virtual address
    wire    [BLOCK_L-1:0]               w_lsu_blk[0:LSUS-1];
    wire    [BLOCK_W-1:0]               w_lsu_saddr[0:LSUS-1];      // Obj start location in block
    wire    [BLOCK_W-1:0]               w_lsu_soffset[0:LSUS-1];    // Obj_offset from start loc
    //wire    [LSUS-1:0]                  w_lsu_base_we;
    //wire    [LSUS-1:0]                  w_lsu_line_we;
    
    wire    [BLOCK_W*BLOCK_D-1:0]       w_tmap_down;                // Phy to virt map
    wire    [BLOCK_W*BLOCK_D-1:0]       w_tmap_up;                  // Virt to phy map
    
    //wire    [NODES*BLOCK_W-1:0]         w_up_scb;                   // SCBs to up switch
    wire    [BLOCK_W*BLOCK_D-1:0]       w_swd_map;
    wire    [BLOCK_W*BLOCK_D-1:0]       w_swu_map;
    wire    [BLOCK_W-1:0]               w_swd_map_unpkd[0:BLOCK_D-1];
    wire    [BLOCK_W-1:0]               w_swu_map_unpkd[0:BLOCK_D-1];
    wire    [BLOCK_W-1:0]               w_lsu_base_ptr[0:LSUS-1];
    wire    [BLOCK_W-1:0]               w_lsu_daddr[0:LSUS-1];          // decoder addr
    wire    [BLOCK_W-1:0]               w_lsu_iaddr[0:LSUS-1];          // Intermediate address. Used to play around with the latency of offset translation
    wire    [BLOCK_W-1:0]               w_lsu_taddr[0:LSUS-1];          // translated addr
    wire    [PADDR_W-1:0]               w_lsu_paddr[0:LSUS-1];          // physical addr
    //wire    [LSUS-1:0]                  w_lsu_we;
    
    //reg     [NODES*BLOCK_W-1:0]         r_up_scb;
    reg     [BLOCK_W-1:0]               r_swd_map[0:BLOCK_D-1];
    reg     [BLOCK_W-1:0]               r_swu_map[0:BLOCK_D-1];
    //reg     [BLOCK_W-1:0]               r_lsu_base_ptr[0:LSUS-1];
    reg     [BLOCK_W-1:0]               r_lsu_daddr[0:LSUS-1];
    reg     [BLOCK_L-1:0]               r_lsu_blk[0:LSUS-1];
    
    genvar i;
    
    integer k;
    
    //assign w_up_scb = r_up_scb;
    
    assign o_blk_addr = w_lsu_blk[0];
    
    generate
        for (i = 0; i < LSUS; i = i+1) begin                            :   gen_lsus
            assign w_lsu_vaddr[i] = i_chan_vaddr[i*VADDR_W +: LSU_VADDR_W];
            assign w_lsu_blk[i] = w_lsu_vaddr[i][LSU_VADDR_W-1 -: BLOCK_L];
            assign w_lsu_saddr[i] = w_lsu_vaddr[i][BLOCK_W +: BLOCK_W];
            assign w_lsu_soffset[i] = w_lsu_vaddr[i][0 +: BLOCK_W];
            assign w_lsu_base_ptr[i] = r_swu_map[w_lsu_saddr[i]];
            
            if (ROW_LATENCY == 2) begin
                assign w_lsu_daddr[i] = w_lsu_base_ptr[i] - w_lsu_soffset[i];
                assign w_lsu_iaddr[i] = r_lsu_daddr[i];
            end
            else if (ROW_LATENCY == 1) begin
                assign w_lsu_daddr[i] = w_lsu_base_ptr[i];
                assign w_lsu_iaddr[i] = r_lsu_daddr[i] - w_lsu_soffset[i];
            end
            
            assign w_lsu_taddr[i] = r_swd_map[w_lsu_iaddr[i]];
            assign w_lsu_paddr[i] = {r_lsu_blk[i], w_lsu_taddr[i]};
            
            assign o_lsu_paddr[i*PADDR_W +: PADDR_W] = w_lsu_paddr[i];
        end
    endgenerate
    
    generate
        for (i = 0; i < BLOCK_D; i = i+1) begin                         :   gen_maps
            assign w_tmap_down[i*BLOCK_W +: BLOCK_W] = i;                   // Ordered phy map connected to ordered virt map
            assign w_tmap_up[i*BLOCK_W +: BLOCK_W] = i;                     // Ordered virt map connected to ordered phy map
            assign w_swd_map_unpkd[i] = w_swd_map[i*BLOCK_W +: BLOCK_W];
            assign w_swu_map_unpkd[i] = w_swu_map[i*BLOCK_W +: BLOCK_W];
        end
    endgenerate
    
    // Physical to virtual pointer gen (switch down)
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
        .i_data(w_tmap_down),
        .i_scb(i_scb),
        
        .o_data(w_swd_map)
    );
    
    // Virtual to physical pointer gen (switch up)
    //(* dont_touch = "yes" *)
    switch_up #(
        .PIPELINE(0),
        .INPUTS(BLOCK_D),
        .NODES(NODES),
        .DATA_W(BLOCK_W),
        .STAGES(BLOCK_W)
    ) virt_phy_up_i (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_data(w_tmap_up),
        //.i_scb(w_up_scb),
        .i_scb(i_scb),
        
        .o_data(w_swu_map)
    );
    
    initial begin
        for (k = 0; k < LSUS; k = k+1) begin
            //r_lsu_base_ptr[k] = 0;
            r_lsu_daddr[k] = 0;
            r_lsu_blk[k] = 0;
        end
    end
    
    always @(posedge i_clk) begin
        for (k = 0; k < LSUS; k = k+1) begin
            //r_lsu_base_ptr[k] <= w_lsu_base_ptr[k];
            r_lsu_daddr[k] <= w_lsu_daddr[k];
            r_lsu_blk[k] <= w_lsu_blk[k];
        end
    end
    
    initial begin
        //r_up_scb = 0;
        for (k = 0; k < BLOCK_D; k = k+1) begin
            r_swd_map[k] = k;
            r_swu_map[k] = k;
        end
    end
    
    always @(posedge i_clk) begin
        //r_up_scb <= i_scb;
        for (k = 0; k < BLOCK_D; k = k+1) begin
            r_swd_map[k] <= (i_reset) ? k : w_swd_map_unpkd[k];
            r_swu_map[k] <= (i_reset) ? k : w_swu_map_unpkd[k];
        end
    end
    
endmodule
