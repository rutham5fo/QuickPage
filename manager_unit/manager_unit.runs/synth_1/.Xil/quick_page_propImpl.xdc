set_property SRC_FILE_INFO {cfile:C:/VivadoProjects/vdmmu/manager_unit/manager_unit.srcs/constrs_1/new/manager_const.xdc rfile:../../../manager_unit.srcs/constrs_1/new/manager_const.xdc id:1} [current_design]
set_property src_info {type:XDC file:1 line:46 export:INPUT save:INPUT read:READ} [current_design]
set_max_delay 10 -from [get_clocks "sys_clk"] -to [get_ports "o_mem_addr"] -datapath_only;
