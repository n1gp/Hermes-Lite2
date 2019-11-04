
module led_flash (
  clk,
  cnt,
  sig,
  led
);
input       clk;
input       cnt;
input       sig;
output      led;

localparam  STATE_CLR   = 2'b00,
            STATE_SET   = 2'b01,
            STATE_WAIT1 = 2'b10,
            STATE_WAIT2 = 2'b11;

logic [1:0] state = STATE_CLR;
logic [1:0] state_next;

always @(posedge clk) state <= state_next;

// LED remains on for 2-3 ticks of cnt
always @* begin
  state_next = state;

  case (state)
    STATE_CLR: begin
      led = 1'b1; // 1 clears LED
      if (sig) state_next = STATE_SET;
    end

    STATE_SET: begin
      led = 1'b0;
      if (cnt) state_next = STATE_WAIT1;
    end

    STATE_WAIT1: begin
      led = 1'b0;
      if (cnt) state_next = STATE_WAIT2;
    end

    STATE_WAIT2: begin
      led = 1'b0;
      if (cnt) state_next = STATE_CLR;
    end
  endcase
end

endmodule



module control(
  // Internal
  clk,
  clk_ad9866,
  clk_125,

  ethup,
  have_dhcp_ip,
  have_fixed_ip,
  network_speed,
  ad9866up,

  rxclip,
  rxgoodlvl,
  rxclrstatus,
  run,
  tx_hang,

  dsiq_status,
  dsiq_sample,

  cmd_addr,
  cmd_data,
  cmd_rqst,
  cmd_requires_resp,
  cmd_ptt,

  tx_on,
  cw_keydown,

  resp_rqst,
  resp,

  static_ip,
  alt_mac,
  eeprom_config,

  // External
  rffe_rfsw_sel,

  rffe_ad9866_rst_n,
  rffe_ad9866_sdio,
  rffe_ad9866_sclk,
  rffe_ad9866_sen_n,

  rffe_ad9866_pga5,

  // Power
  pwr_clk3p3,
  pwr_clk1p2,
  pwr_envpa,
  pwr_envop,
  pwr_envbias,

  sda1_i,
  sda1_o,
  sda1_t,
  scl1_i,
  scl1_o,
  scl1_t,

  sda2_i,
  sda2_o,
  sda2_t,
  scl2_i,
  scl2_o,
  scl2_t,

  sda3_i,
  sda3_o,
  sda3_t,
  scl3_i,
  scl3_o,
  scl3_t,

  // IO
  io_led_run,
  io_led_tx,
  io_led_adc75,
  io_led_adc100,

  io_tx_inhibit,

  io_uart_txd,

  io_cw_keydown,

  io_phone_tip,   // BETA2,BETA3: io_cn4_2
  io_phone_ring,  // BETA2,BETA3: io_cn4_3

  io_atu_ack,
  io_atu_req,

  // PA
  pa_inttr,
  pa_exttr
);

// Internal
input           clk;
input           clk_ad9866;
input           clk_125;

input           ethup;
input           have_dhcp_ip;
input           have_fixed_ip;
input  [1:0]    network_speed;
input           ad9866up;

input           rxclip;
input           rxgoodlvl;
output logic    rxclrstatus = 1'b0;
input           run;
input           tx_hang;

input [7:0]     dsiq_status;
output logic    dsiq_sample = 1'b0;

input  [5:0]    cmd_addr;
input  [31:0]   cmd_data;
input           cmd_rqst;
input           cmd_requires_resp;
input           cmd_ptt;

output          tx_on;
output          cw_keydown;

input           resp_rqst;
output [39:0]   resp;

output [31:0]   static_ip;
output [15:0]   alt_mac;
output [ 7:0]   eeprom_config;

// External
output          rffe_rfsw_sel;

output          rffe_ad9866_rst_n;

output          rffe_ad9866_sdio;
output          rffe_ad9866_sclk;
output          rffe_ad9866_sen_n;

output          rffe_ad9866_pga5;

// Power
output logic    pwr_clk3p3 = 1'b0;
output logic    pwr_clk1p2 = 1'b0;
output          pwr_envpa;
output          pwr_envop;
output          pwr_envbias;

input           sda1_i;
output          sda1_o;
output          sda1_t;
input           scl1_i;
output          scl1_o;
output          scl1_t;

input           sda2_i;
output          sda2_o;
output          sda2_t;
input           scl2_i;
output          scl2_o;
output          scl2_t;

input           sda3_i;
output          sda3_o;
output          sda3_t;
input           scl3_i;
output          scl3_o;
output          scl3_t;

// IO
output          io_led_run;
output          io_led_tx;
output          io_led_adc75;
output          io_led_adc100;

input           io_tx_inhibit;

output          io_uart_txd;
output          io_cw_keydown;
input           io_phone_tip;
input           io_phone_ring;

input           io_atu_ack;
output          io_atu_req;

// PA
output          pa_inttr;
output          pa_exttr;

parameter     HERMES_SERIALNO = 8'h0;
parameter     UART = 0;
parameter     ATU = 0;


logic         vna = 1'b0;                    // Selects vna mode when set.
logic         pa_enable = 1'b0;
logic         tr_disable = 1'b0;
logic [9:0]   cw_hang_time;

logic [11:0]  fwd_pwr;
logic [11:0]  rev_pwr;
logic [11:0]  bias_current;
logic [11:0]  temperature;

logic         cmd_ack_i2c, cmd_ack_ad9866;
logic [31:0]  cmd_resp_data_i2c;
logic         ptt;

logic [39:0]  iresp = {8'h00, 8'b00011110, 8'h00, 8'h00, HERMES_SERIALNO};
logic [ 1:0]  resp_addr = 2'b00;

logic         cmd_resp_rqst;

logic         cmd_ack;
logic [ 5:0]  resp_cmd_addr = 6'h00, resp_cmd_addr_next;
logic [31:0]  resp_cmd_data = 32'h00, resp_cmd_data_next;

logic         int_ptt = 1'b0;
logic         int_ptt_gated;

logic [8:0]   led_count;
logic         led_saturate;
logic [11:0]  millisec_count;
logic         millisec_pulse;

logic         ext_txinhibit, ext_cwkey, ext_ptt;

logic         slow_adc_rst, ad9866_rst;
logic         clk_i2c_rst;
logic         clk_i2c_start;

logic [15:0]  resetcounter = 16'h0000;
logic         resetsaturate;

logic [ 1:0]  clip_cnt = 2'b00;

logic         led_d2, led_d3, led_d4, led_d5;

logic         disable_syncfreq = 1'b0;

logic [ 5:0]  pwrcnt = 6'h10;
//logic [ 2:0]  pwrphase = 3'b100;

logic         resp_cnt = 1'b0;

localparam RESP_START   = 2'b00,
           RESP_ACK     = 2'b01,
           RESP_READ    = 2'b11,
           RESP_WAIT    = 2'b10;

logic [1:0]   resp_state = RESP_START, resp_state_next;


logic         cw_keydown;
logic         cw_power_on;

logic         ptt_resp = 1'b0;

logic [ 7:0]  ieeprom_config;

logic         use_eeprom_config = 1'b0;


/////////////////////////////////////////////////////
// Reset

// Most FPGA logic is reset when ethernet is up and ad9866 PLL is locked
// AD9866 is released from reset

assign resetsaturate = &resetcounter;

always @ (posedge clk)
  if (~resetsaturate & ethup) resetcounter <= resetcounter + 16'h01;

// At ~410us
assign clk_i2c_rst = ~(|resetcounter[15:10]);

// At ~820us
assign clk_i2c_start = (|resetcounter[15:11]);

// At ~6.5ms
assign slow_adc_rst = ~(|resetcounter[15:14]);

// At ~13ms
assign rffe_ad9866_rst_n = resetcounter[15];

// At ~26ms
assign ad9866_rst = ~resetsaturate | ~ad9866up;



always @(posedge clk) begin
  if (cmd_rqst) begin
    int_ptt <= cmd_ptt;
    if (cmd_addr == 6'h09) begin
      vna          <= cmd_data[23];      // 1 = enable vna mode
      pa_enable    <= cmd_data[19];
      tr_disable   <= cmd_data[18];
    end
    else if (cmd_addr == 6'h10) begin
      cw_hang_time <= {cmd_data[31:24], cmd_data[17:16]};
    end
    else if (cmd_addr == 6'h00) begin
      disable_syncfreq <= cmd_data[12];
    end
  end
end


generate
  case (UART)
    0: begin: NOUART // No UART
      assign uart_txd = 1'b0;
    end

    1: begin: JI1UDD_HR50 // JI1UDD HR50

      logic [31:0]  tx_freq = 32'h00000000;
      always @(posedge clk) begin
        if (cmd_addr == 6'h01) begin
          tx_freq <= cmd_data;
        end
      end

      extamp extamp_i (
        .clk(clk),
        .freq(tx_freq),
        .ptt(tx_on),
        .uart_txd(io_uart_txd)
      );
    end
  endcase
endgenerate

generate
  case (ATU)
    0: begin: NOATU // No ATU
      assign int_ptt_gated = int_ptt;
      assign io_atu_req = 1'b0;
    end

    1: begin: JI1UDD_ATU // JI1UDD ATU

      logic auto_tune = 1'b0;
      always @(posedge clk) begin
        if (cmd_addr == 6'h09) begin
          auto_tune <=cmd_data[20];
        end
      end

      exttuner exttuner_i (
        .clk(clk),
        .auto_tune(auto_tune),
        .ATU_Status(io_atu_ack),
        .ATU_Start(io_atu_req),
        .mox_in(int_ptt),
        .mox_out(int_ptt_gated)
      );
    end
  endcase
endgenerate


always @(posedge clk)
  if (slow_adc_rst) use_eeprom_config <= ~(ext_ptt & ext_cwkey);

assign eeprom_config[7:5] = use_eeprom_config ? ieeprom_config[7:5] : 3'b000;
assign eeprom_config[4:0] = ieeprom_config[4:0];

i2c i2c_i (
  .clk(clk),
  .rst(clk_i2c_rst),
  .init_start(clk_i2c_start),

  .cmd_addr(cmd_addr),
  .cmd_data(cmd_data),
  .cmd_rqst(cmd_rqst),
  .cmd_ack(cmd_ack_i2c),
  .cmd_resp_data(cmd_resp_data_i2c),

  .static_ip(static_ip),
  .alt_mac(alt_mac),
  .eeprom_config(ieeprom_config),

  .scl1_i(scl1_i),
  .scl1_o(scl1_o),
  .scl1_t(scl1_t),
  .sda1_i(sda1_i),
  .sda1_o(sda1_o),
  .sda1_t(sda1_t),
  .scl2_i(scl2_i),
  .scl2_o(scl2_o),
  .scl2_t(scl2_t),
  .sda2_i(sda2_i),
  .sda2_o(sda2_o),
  .sda2_t(sda2_t)
);

slow_adc slow_adc_i (
  .clk(clk),
  .rst(slow_adc_rst),
  .sample(resp_rqst & resp_cnt),
  .ain0(rev_pwr),
  .ain1(temperature),
  .ain2(bias_current),
  .ain3(fwd_pwr),
  .scl_i(scl3_i),
  .scl_o(scl3_o),
  .scl_t(scl3_t),
  .sda_i(sda3_i),
  .sda_o(sda3_o),
  .sda_t(sda3_t)
);



// 6.5 ms debounce with 2.5MHz clock
debounce de_phone_tip(.clean_pb(ext_cwkey), .pb(~io_phone_tip), .clk(clk));
assign io_cw_keydown = cw_keydown;

debounce de_phone_ring(.clean_pb(ext_ptt), .pb(~io_phone_ring), .clk(clk));
debounce de_txinhibit(.clean_pb(ext_txinhibit), .pb(~io_tx_inhibit), .clk(clk));


assign tx_on = (int_ptt_gated | cw_keydown | ext_ptt | tx_hang) & ~ext_txinhibit & run;

// Gererate two slow pulses for timing.  millisec_pulse occurs every one millisecond.
// led_saturate occurs every 64 milliseconds.
always @(posedge clk) begin	// clock is 2.5 MHz
  if (millisec_count == 12'd2500) begin
    millisec_count <= 12'b0;
    millisec_pulse <= 1'b1;
    led_count <= led_count + 1'b1;
  end else begin
    millisec_count <= millisec_count + 1'b1;
    millisec_pulse <= 1'b0;
  end
end
assign led_saturate = &led_count[5:0];


led_flash led_rxgoodlvl(.clk(clk), .cnt(led_saturate), .sig(rxgoodlvl), .led(led_d4));
led_flash led_rxclip(.clk(clk), .cnt(led_saturate), .sig(rxclip), .led(led_d5));

// For test, measure the ad9866 clock, if it is
logic [5:0] fast_clk_cnt;
always @(posedge clk_ad9866) begin
  // Count when 1x, at 76.8 MHz we should see 62 ticks when 1x is true
  if (millisec_count[1] & ~(&fast_clk_cnt)) fast_clk_cnt <= fast_clk_cnt + 6'h01;
  // Clear when 01 to prepare for next count
  else if (millisec_count[0]) fast_clk_cnt <= 6'h00;
end

logic good_fast_clk;
always @(posedge clk) begin
  // Compute when 00
  if (millisec_count[1:0] == 2'b00) good_fast_clk <= ~(&fast_clk_cnt);
end

// Solid when connected to software
// Blinking to indicate good ethernet clock
assign io_led_run = run ? ~run : ~(ethup & led_count[8]);

// Blinking indicates fixed ip, solid indicates dhcp
assign io_led_tx = run ? ~tx_on : ~((have_fixed_ip & led_count[8]) | have_dhcp_ip);

// Blinks if 100 Mbps, solid if 1Gbs, off otherwise
assign io_led_adc75 = run ? led_d4 : ~(((network_speed == 2'b01) & led_count[8]) | network_speed == 2'b10);

// Lights if ad9866 is up and the  clock is less than 80 MHz
assign io_led_adc100 = run ? led_d5 : ~(ad9866up & good_fast_clk);

// Clear status
always @(posedge clk) rxclrstatus <= ~rxclrstatus;



cw_support cw_support_i(
  .clk(clk),
  .millisec_pulse(millisec_pulse),
  .dot_key(~io_phone_tip),
  .dash_key(~io_phone_ring),
  .dot_key_debounced(ext_cwkey),
  .dash_key_debounced(ext_ptt),
  .cw_power_on(cw_power_on),
  .cw_keydown(cw_keydown)
);

// Include CW and hang times in ptt response
always @(posedge clk) begin
  if (cw_keydown | ext_ptt) begin
    ptt_resp <= 1'b1;
  end else if (~tx_hang) begin
    ptt_resp <= 1'b0;
  end
end



logic tx_power_on; // Is the power on?
assign tx_power_on = cw_power_on | tx_on;

assign pwr_envbias = tx_power_on & ~vna & pa_enable;
assign pwr_envop = tx_power_on;
assign pa_exttr = tx_power_on;
assign pa_inttr = tx_power_on & ~vna & (pa_enable | ~tr_disable);
assign pwr_envpa = tx_power_on & ~vna & pa_enable;

assign rffe_rfsw_sel = ~vna & pa_enable;


// AD9866 Ctrl
ad9866ctrl ad9866ctrl_i (
  .clk(clk),
  .rst(ad9866_rst),

  .rffe_ad9866_sdio(rffe_ad9866_sdio),
  .rffe_ad9866_sclk(rffe_ad9866_sclk),
  .rffe_ad9866_sen_n(rffe_ad9866_sen_n),

  .rffe_ad9866_pga5(rffe_ad9866_pga5),

  .cmd_addr(cmd_addr),
  .cmd_data(cmd_data),
  .cmd_rqst(cmd_rqst),
  .cmd_ack(cmd_ack_ad9866)
);



// Response state machine
always @ (posedge clk) begin
  resp_state <= resp_state_next;
  resp_cmd_addr <= resp_cmd_addr_next;
  resp_cmd_data <= resp_cmd_data_next;
end

// FSM Combinational
always @* begin
  // Next State
  resp_state_next = resp_state;
  resp_cmd_addr_next = resp_cmd_addr;
  resp_cmd_data_next = resp_cmd_data;

  // Combinational
  cmd_resp_rqst = 1'b0;

  case (resp_state)
    RESP_START: begin
      if (cmd_rqst & cmd_requires_resp) begin
        // Save data for response
        resp_cmd_addr_next = cmd_addr;
        resp_cmd_data_next = cmd_data;
        resp_state_next  = RESP_ACK;
      end
    end

    RESP_ACK: begin
      // Always send a response, may be error
      resp_state_next = RESP_READ;
      if (~(cmd_ack_i2c & cmd_ack_ad9866)) begin
        // Error response if subsystem was not ready
        resp_cmd_addr_next = 6'h3f;
        resp_state_next = RESP_WAIT;
      end
    end

    RESP_READ: begin
      // If there is a read, the ack will be low here until the read is ready
      if (~(cmd_ack_i2c & cmd_ack_ad9866)) begin
        if (~cmd_ack_i2c) begin
          resp_cmd_data_next = cmd_resp_data_i2c;
        end else if (~cmd_ack_ad9866) begin
          resp_cmd_data_next = cmd_resp_data_i2c; // FIXME: suppor read cmd_resp_data_ad9866
        end
      end else begin
        resp_state_next = RESP_WAIT;
      end
    end

    RESP_WAIT: begin
      cmd_resp_rqst = 1'b1;
      if (resp_rqst & ~resp_cnt) begin // Only every other resp_rqst
        if (cmd_rqst & cmd_requires_resp) begin
          // Save data for response
          resp_cmd_addr_next = cmd_addr;
          resp_cmd_data_next = cmd_data;
          resp_state_next  = RESP_ACK;
        end else begin
          resp_state_next = RESP_START;
        end
      end
    end

    default: begin
      resp_state_next = RESP_START;
    end

  endcase
end

// Resp request occurs relatively infrequently
// Output register iresp is updated on resp_rqst
// Output register iresp will be stable before required in any other clock domain
always @(posedge clk) begin
  if (resp_rqst) begin
    resp_cnt <= ~resp_cnt; // Count every other response
    clip_cnt  <= 2'b00;
    resp_addr <= resp_addr + 2'b01; // Slot will be skipped if command response
    if (cmd_resp_rqst & ~resp_cnt) begin // Only every other resp_rqst
      // Command response
      iresp <= {1'b1,resp_cmd_addr,tx_on, resp_cmd_data}; // Queue size is 1
    end else begin
      case( resp_addr)
        2'b00: iresp <= {3'b000,resp_addr, ext_cwkey, 1'b0, ptt_resp, 7'b0001111,(&clip_cnt), 8'h00, dsiq_status, HERMES_SERIALNO};
        2'b01: iresp <= {3'b000,resp_addr, ext_cwkey, 1'b0, ptt_resp, 4'h0,temperature, 4'h0,fwd_pwr};
        2'b10: iresp <= {3'b000,resp_addr, ext_cwkey, 1'b0, ptt_resp, 4'h0,rev_pwr, 4'h0,bias_current};
        2'b11: iresp <= {3'b000,resp_addr, ext_cwkey, 1'b0, ptt_resp, 32'h0}; // Unused in HL
      endcase
    end
  end else if (~(&clip_cnt)) begin
    clip_cnt <= clip_cnt + {1'b0,rxclip};
  end
end

assign resp = iresp;


always @(posedge clk) begin
  if (resp_rqst & (resp_addr == 2'b01))
    dsiq_sample <= ~dsiq_sample;
end


// sync clock
always @(posedge clk_125) begin
  if (pwrcnt == 6'h00) begin
    //case(pwrphase)
    //  3'b000: pwrcnt <= 6'd59;
    //  3'b001: pwrcnt <= 6'd57;
    //  3'b010: pwrcnt <= 6'd58;
    //  3'b011: pwrcnt <= 6'd55;
    //  3'b100: pwrcnt <= 6'd58;
    //  3'b101: pwrcnt <= 6'd59;
    //  3'b110: pwrcnt <= 6'd56;
    //  3'b111: pwrcnt <= 6'd59;
    //endcase
    //if (pwrphase == 3'b000) pwrphase <= 3'b110;
    //else pwrphase <= pwrphase - 3'b001;
    pwrcnt <= 6'd58;
  end else begin
    pwrcnt <= pwrcnt - 6'h01;
  end

  if (disable_syncfreq) begin
    pwr_clk3p3 <= 1'b0;
    pwr_clk1p2 <= 1'b0;
  end else begin
    if (pwrcnt == 6'h00) pwr_clk3p3 <= ~pwr_clk3p3;
    if (pwrcnt == 6'h11) pwr_clk1p2 <= ~pwr_clk1p2;
  end
end

endmodule // ioblock
