set "clk_p" 10.0;

create_clock -name sys_clk -period "$clk_p" [get_ports "i_clk"];

set_input_delay -clock "sys_clk" -max 1.5 [get_ports [list "i_reset" "i_req_id" "i_req_func" "i_req_alloc_size" "i_req_dealloc_data" "i_virt_addr"]];
set_input_delay -clock "sys_clk" -min 1.5 [get_ports [list "i_reset" "i_req_id" "i_req_func" "i_req_alloc_size" "i_req_dealloc_data" "i_virt_addr"]];

set_output_delay -clock "sys_clk" -max 0.5 [get_ports [list "o_busy" "o_rep_alloc_vld" "o_rep_dealloc_vld" "o_rep_data" "o_mem_update"]];
set_output_delay -clock "sys_clk" -min 0.5 [get_ports [list "o_busy" "o_rep_alloc_vld" "o_rep_dealloc_vld" "o_rep_data" "o_mem_update"]];

set_max_delay 10 -from [get_clocks "sys_clk"] -to [get_ports [list "o_mem_addr" "o_mem_sub_addr"]] -datapath_only;
