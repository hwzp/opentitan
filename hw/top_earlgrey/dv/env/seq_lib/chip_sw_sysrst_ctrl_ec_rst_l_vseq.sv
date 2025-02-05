// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class chip_sw_sysrst_ctrl_ec_rst_l_vseq extends chip_sw_base_vseq;
  `uvm_object_utils(chip_sw_sysrst_ctrl_ec_rst_l_vseq)

  `uvm_object_new

  localparam time AON_CYCLE_PERIOD = 5us;
  localparam bit [1:0] OUTPUT_ALL_SET = 2'b11;
  localparam bit [1:0] OUTPUT_NONE_SET = 2'b00;
  localparam uint TIMEOUT_VALUE = 5000000;
  localparam int EC_RST_TIMER = 512;

  localparam string PWRMGR_RSTREQ_PATH = "tb.dut.top_earlgrey.u_pwrmgr_aon.rstreqs_i[0]";
  localparam string RST_AON_NI_PATH = "tb.dut.top_earlgrey.u_sysrst_ctrl_aon.rst_aon_ni";

  localparam int PAD_KEY0 = 0;
  localparam int PAD_KEY1 = 1;

  typedef enum {
    PHASE_INITIAL               = 0,
    PHASE_COMBO_RESET           = 1,
    PHASE_OVERRIDE_SETUP        = 2,
    PHASE_OVERRIDE_ZEROS        = 3,
    PHASE_OVERRIDE_ONES         = 4,
    PHASE_DONE                  = 5
  } test_phases_e;

  logic [1:0] output_pad_read_values;
  logic       output_ec_rst_read_values;
  logic       ec_rst_timer_over;

  virtual function void write_test_phase(input test_phases_e phase);
    sw_symbol_backdoor_overwrite("kTestPhase", {<<8{phase}});
  endfunction

  virtual task set_combo0_pads_low();
    cfg.chip_vif.sysrst_ctrl_if.drive_pin(PAD_KEY0, 0);
    cfg.chip_vif.sysrst_ctrl_if.drive_pin(PAD_KEY1, 0);
  endtask

  virtual task set_combo0_pads_high();
    cfg.chip_vif.sysrst_ctrl_if.drive_pin(PAD_KEY0, 1);
    cfg.chip_vif.sysrst_ctrl_if.drive_pin(PAD_KEY1, 1);
  endtask

  virtual task check_ec_rst_pads(bit exp_ec_rst_l);
    #(3 * AON_CYCLE_PERIOD);
    `DV_CHECK_EQ_FATAL(cfg.chip_vif.ec_rst_l_if.sample_pin(0), exp_ec_rst_l)
  endtask

  virtual task check_output_pads(bit exp_ec_rst_l, bit exp_flash_wp_l);
    #(3 * AON_CYCLE_PERIOD);
    `DV_CHECK_EQ_FATAL(cfg.chip_vif.ec_rst_l_if.sample_pin(0), exp_ec_rst_l)
    `DV_CHECK_EQ_FATAL(cfg.chip_vif.flash_wp_l_if.sample_pin(0), exp_flash_wp_l)
  endtask

  virtual task sync_with_sw();
    `DV_WAIT(cfg.sw_test_status_vif.sw_test_status == SwTestStatusInWfi)
    `DV_WAIT(cfg.sw_test_status_vif.sw_test_status == SwTestStatusInTest)
  endtask

  virtual task wait_for_ec_rst_high();
    int timeout_count = 0;
    forever begin
      if (cfg.chip_vif.ec_rst_l_if.sample_pin(0) == 0) begin
        timeout_count++;
        if (timeout_count >= TIMEOUT_VALUE) begin
          `uvm_error(`gfn, "Timed out waiting for ec_rst to go high.")
        end
      end else begin
        break;
      end
      // Some amount of delay between samples of ec_rst.
      cfg.clk_rst_vif.wait_clks(1);
    end
  endtask

  virtual task control_ec_rst_low(int min_exp_cycles);
    int timeout_count = 0;
    `DV_WAIT(cfg.chip_vif.ec_rst_l_if.pins[0] === 0)
    // wait until ec_rst is de-active and check the length.
    `DV_SPINWAIT(
    forever begin
      if (cfg.chip_vif.ec_rst_l_if.sample_pin(0) == 0) begin
        timeout_count++;
        if (timeout_count >= EC_RST_TIMER) begin
          ec_rst_timer_over = 1; // set this for the other thread to continue
        end
      end else begin
        break;
      end
      // Some amount of delay between samples of ec_rst.
      #(AON_CYCLE_PERIOD);
    end)
    `DV_CHECK(timeout_count > min_exp_cycles) // check ec_rst length
  endtask

  virtual task check_ec_rst_with_transition(string path, int exp_value);
    bit retval = 0;
    int timeout_count = 0;
    forever begin
      `DV_CHECK(uvm_hdl_read(path, retval));
      if (retval == exp_value) begin
        timeout_count++;
        if (timeout_count >= TIMEOUT_VALUE) begin
          `uvm_error(`gfn, $sformatf("Timed out waiting for %0s to go to %d \n",
              path, exp_value))
        end
      end else begin
        break;
      end
      cfg.clk_rst_vif.wait_clks(1);
    end
    // Check that ec_rst is low.
    cfg.clk_rst_vif.wait_clks(1);
    if (cfg.chip_vif.ec_rst_l_if.sample_pin(0) == 1) begin
      `uvm_error(`gfn, "Unexpected ec_rst high after reset request.")
    end
  endtask

  virtual task check_flash_wp_value(input bit level_to_check);
    if (cfg.chip_vif.flash_wp_l_if.sample_pin(0) != level_to_check) begin
      `uvm_error(`gfn, $sformatf("Flash write protect signal expected %0d.", level_to_check))
    end
  endtask

  virtual task body();
    super.body();

    // TODO(lowRISC/opentitan:#13373): Revisit pad assignments.
    // pinmux_wkup_vif (at Iob7) is re-used for PinZ3WakeupOut
    // due to lack of unused pins. Disable the default drive
    // to this pin.
    cfg.chip_vif.pinmux_wkup_if.drive_en_pin(0, 0);
    set_combo0_pads_high();

    write_test_phase(PHASE_INITIAL);
    `DV_WAIT(cfg.sw_test_status_vif.sw_test_status == SwTestStatusInBootRom)
    `DV_WAIT(cfg.sw_test_status_vif.sw_test_status == SwTestStatusInWfi)

    check_flash_wp_value(1);
    wait_for_ec_rst_high();
    set_combo0_pads_low();
    ec_rst_timer_over = 0;

    fork
      begin
        control_ec_rst_low(EC_RST_TIMER);
      end
      begin
        check_ec_rst_with_transition(PWRMGR_RSTREQ_PATH, 1'b0);
        check_ec_rst_with_transition(RST_AON_NI_PATH , 1'b0);
        sync_with_sw();
        write_test_phase(PHASE_COMBO_RESET);
        `DV_WAIT(cfg.sw_test_status_vif.sw_test_status == SwTestStatusInTest)
        `DV_WAIT(cfg.sw_test_status_vif.sw_test_status == SwTestStatusInWfi)
        `DV_WAIT(ec_rst_timer_over)

        write_test_phase(PHASE_OVERRIDE_SETUP);
        sync_with_sw();
        check_ec_rst_pads(1'b0);

        write_test_phase(PHASE_OVERRIDE_ZEROS);
        sync_with_sw();
        check_output_pads(1'b0, 1'b0);

        write_test_phase(PHASE_OVERRIDE_ONES);
        sync_with_sw();
        check_output_pads(1'b1, 1'b1);

        write_test_phase(PHASE_DONE);
      end
    join
  endtask
endclass
