`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.02.2025 00:07:31
// Design Name: 
// Module Name: switch_ustage
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


module switch_ustage #(
        //parameter TEST_EN           = 0,
        parameter PIPELINE          = 1,
        parameter STAGE_NUM         = 0,
        parameter INPUTS            = 32,
        parameter NODES             = INPUTS/2,
        parameter DATA_W            = 1,
        parameter STAGES            = $clog2(INPUTS)
    )(
        input wire                      i_clk,
        input wire                      i_reset,
        input wire  [DATA_W*INPUTS-1:0] i_data,
        input wire  [NODES-1:0]         i_scb,
        
        output wire [DATA_W*INPUTS-1:0] o_data
    );
    
    localparam SPLIT            = (STAGE_NUM < STAGES-1) ? 2**(STAGE_NUM+1) : 2**STAGE_NUM;
    
    wire    [DATA_W-1:0]        data_in_unpkd[0:INPUTS-1];
    //wire    [DATA_W-1:0]        r_data_out[0:INPUTS-1];
    wire    [DATA_W-1:0]        r_data_in[0:INPUTS-1];
    wire    [DATA_W-1:0]        data_out_unpkd[0:INPUTS-1];
    
    genvar i;
    
    // Test wires
    //generate
    //    if (TEST_EN >= 2) begin                  : BUTTERFLY_STAGE_TEST_EN
    //        integer k;
    //        always @(*) begin
    //            $write("%t: STAGE[%0d] ||| addr_in = {|", $time, STAGE_NUM);
    //            for (k = 0; k < INPUTS; k = k+1) begin
    //                $write(" [%0d]%0d |", k, addr_in_unpkd[k]);
    //            end
    //            $display("}");
    //            $write("%t: STAGE[%0d] ||| i_addr_out = {|", $time, STAGE_NUM);
    //            for (k = 0; k < INPUTS; k = k+1) begin
    //                $write(" [%0d]%0d |", k, r_addr_out[k]);
    //            end
    //            $display("}");
    //            $write("%t: STAGE[%0d] ||| addr_out = {|", $time, STAGE_NUM);
    //            for (k = 0; k < INPUTS; k = k+1) begin
    //                $write(" [%0d]%0d |", k, addr_out_unpkd[k]);
    //            end
    //            $display("}");
    //        end
    //    end
    //endgenerate
    //--------------------------------------------
    
    // Packed to unpacked
    generate
        for (i = 0; i < INPUTS; i = i+1) begin
            assign data_in_unpkd[i] = i_data[i*DATA_W +: DATA_W];
            assign o_data[i*DATA_W +: DATA_W] = data_out_unpkd[i];
        end
    endgenerate
    
    // Stage output mapping
    generate      
        if (STAGE_NUM < STAGES-1) begin
            for (i = 0; i < INPUTS; i = i+1) begin
                if ((i/SPLIT)%2 == 0) begin
                    if (i%2 == 0) begin
                        //assign data_out_unpkd[i] = r_data_out[i];
                        assign r_data_in[i] = data_in_unpkd[i];
                    end
                    else begin
                        //assign data_out_unpkd[i] = r_data_out[i+SPLIT-1];
                        assign r_data_in[i+SPLIT-1] = data_in_unpkd[i];
                    end
                end
                else begin
                    if (i%2 == 0) begin
                        //assign data_out_unpkd[i] = r_data_out[i-SPLIT+1];
                        assign r_data_in[i-SPLIT+1] = data_in_unpkd[i];
                    end
                    else begin
                        //assign data_out_unpkd[i] = r_data_out[i];
                        assign r_data_in[i] = data_in_unpkd[i];
                    end
                end
            end
        end
        else begin
            for (i = 0; i < INPUTS; i = i+1) begin
                if (i < SPLIT) begin
                    //assign data_out_unpkd[i] = r_data_out[2*i];
                    assign r_data_in[2*i] = data_in_unpkd[i];
                end
                else begin
                    //assign data_out_unpkd[i] = r_data_out[2*(i-SPLIT)+1];
                    assign r_data_in[2*(i-SPLIT)+1] = data_in_unpkd[i];
                end
            end
        end
    endgenerate
    
    // Node generation
    generate
        for (i = 0; i < NODES; i = i+1) begin
            switch_node #(
                .PIPELINE(PIPELINE),
                .INPUTS(INPUTS),
                .DATA_W(DATA_W)
            ) switch_node_i (
                .i_clk(i_clk),
                .i_reset(i_reset),
                //.i_data_0(data_in_unpkd[2*i]),
                //.i_data_1(data_in_unpkd[2*i+1]),
                .i_data_0(r_data_in[2*i]),
                .i_data_1(r_data_in[2*i+1]),
                .i_scb(i_scb[i]),
                
                //.o_data_0(r_data_out[2*i]),
                //.o_data_1(r_data_out[2*i+1])
                .o_data_0(data_out_unpkd[2*i]),
                .o_data_1(data_out_unpkd[2*i+1])
            );
        end
    endgenerate
    
endmodule
