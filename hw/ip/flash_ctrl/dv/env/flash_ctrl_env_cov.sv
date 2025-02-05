// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

//
// Covergoups that are dependent on run-time parameters that may be available
// only in build_phase can be defined here
// Covergroups may also be wrapped inside helper classes if needed.
//

`include "dv_fcov_macros.svh"

class flash_ctrl_env_cov extends cip_base_env_cov #(.CFG_T(flash_ctrl_env_cfg));
  `uvm_component_utils(flash_ctrl_env_cov)

  // the base class provides the following handles for use:
  // flash_ctrl_env_cfg: cfg

  // covergroups

  covergroup control_cg with function sample (flash_op_t flash_cfg_opts);
    part_cp: coverpoint flash_cfg_opts.partition;
    erase_cp: coverpoint flash_cfg_opts.erase_type;
    op_cp: coverpoint flash_cfg_opts.op;
    op_evict_cp: coverpoint flash_cfg_opts.op {
      bins op[] = {FlashOpRead, FlashOpProgram, FlashOpErase};
      bins read_prog_read = (FlashOpRead => FlashOpProgram => FlashOpRead);
      bins read_erase_read = (FlashOpRead => FlashOpErase => FlashOpRead);
    }
    op_part_cross : cross part_cp, op_cp;
  endgroup  : control_cg

  covergroup erase_susp_cg with function sample (bit erase_req = 0);
    erase_susp_cp: coverpoint erase_req {
      bins erase_susp_true = {1};
    }
  endgroup : erase_susp_cg

  covergroup error_cg with function sample(input bit [NumFlashErrBits-1:0] err_val);

    option.per_instance = 1;
    option.name         = "error_cg";

    `DV_FCOV_EXPR_SEEN(op_err,          err_val[FlashOpErr])
    `DV_FCOV_EXPR_SEEN(mp_err,          err_val[FlashMpErr])
    `DV_FCOV_EXPR_SEEN(rd_err,          err_val[FlashRdErr])
    `DV_FCOV_EXPR_SEEN(prog_err,        err_val[FlashProgErr])
    `DV_FCOV_EXPR_SEEN(prog_win_err,    err_val[FlashProgWinErr])
    `DV_FCOV_EXPR_SEEN(prog_type_err,   err_val[FlashProgTypeErr])
    `DV_FCOV_EXPR_SEEN(flash_macro_err, err_val[FlashMacroErr])
    `DV_FCOV_EXPR_SEEN(update_err,      err_val[FlashUpdateErr])
  endgroup : error_cg

  covergroup fifo_lvl_cg with function sample (bit[4:0] prog, bit[4:0] rd);
    prog_lvl_cp: coverpoint prog {
      bins prog_lvl[] = {[1:3]};
    }

    rd_lvl_cp: coverpoint rd {
      bins rd_lvl[] = {[1:15]};
    }
  endgroup : fifo_lvl_cg

  covergroup eviction_cg with function sample (int idx, bit[1:0] op,
                                               bit [1:0] scr_ecc);
    evic_idx_cp : coverpoint idx {
      bins evic_idx[] = {[0:3]};
    }
    evic_op_cp : coverpoint op {
      bins evic_op[] = {1, 2};
    }
    evic_cfg_cp : coverpoint scr_ecc;
    evic_all_cross : cross evic_idx_cp, evic_op_cp, evic_cfg_cp;
  endgroup // eviction_cg

  covergroup fetch_code_cg with function sample(bit is_exec_key, logic [MuBi4Width-1:0] instr);
    key_cp: coverpoint is_exec_key;
    instr_type_cp: coverpoint instr {
      bins instr_types[2] = {MuBi4True, MuBi4False};
      bins others = {[0:15]} with (!(item inside {MuBi4True, MuBi4False}));
    }
    key_instr_cross : cross key_cp, instr_type_cp;
  endgroup // fetch_code_cg

  covergroup rma_init_cg with function sample(flash_ctrl_pkg::rma_state_e st);
    rma_start_cp: coverpoint st {
      bins rma_st[2] = {StRmaIdle, [StRmaPageSel:StRmaInvalid]};
    }
  endgroup // rma_init_cg

  function new(string name, uvm_component parent);
    super.new(name, parent);
    control_cg = new();
    erase_susp_cg = new();
    error_cg = new();
    fifo_lvl_cg = new();
    eviction_cg = new();
    fetch_code_cg = new();
    rma_init_cg = new();
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
  endfunction

endclass
