
module ethernet_controller #
(
      parameter  PLATFORM             = "SIM"
    , parameter  buf_size_p           = 2048 // byte
    , parameter  axis_width_p         = 64
    , localparam packet_size_width_lp = $clog2(buf_size_p) + 1
    , localparam addr_width_lp        = $clog2(buf_size_p)
)
(
      input  logic                    clk_i
    , input  logic                    reset_i
    , input  logic                    clk250_i
    , input  logic                    reset_clk250_i
    , output logic                    reset_clk125_o

    , input  logic [15:0]             addr_i
    , input  logic                    write_en_i
    , input  logic                    read_en_i
    , input  logic [1:0]              op_size_i
    , input  logic [axis_width_p-1:0] write_data_i
    , output logic [axis_width_p-1:0] read_data_o // sync read
    , output logic                    read_data_v_o

    , output logic                    rx_interrupt_pending_o
    , output logic                    tx_interrupt_pending_o

    , input  logic                    rgmii_rx_clk_i
    , input  logic [3:0]              rgmii_rxd_i
    , input  logic                    rgmii_rx_ctl_i
    , output logic                    rgmii_tx_clk_o
    , output logic [3:0]              rgmii_txd_o
    , output logic                    rgmii_tx_ctl_o
);

  logic send_lo;
  logic rx_ready_li;
  logic tx_ready_li;
  logic clear_buffer_lo;
  logic rx_ready_lo;
  logic tx_ready_lo;

  logic                              tx_packet_size_v_lo;
  logic [packet_size_width_lp - 1:0] tx_packet_size_lo;

  logic [addr_width_lp - 1:0]        buffer_write_addr_lo;
  logic [1:0]                        buffer_write_op_size_lo;
  logic [axis_width_p-1:0]           buffer_write_data_lo;
  logic                              buffer_write_v_lo;

  logic [addr_width_lp - 1:0]        buffer_read_addr_lo;
  logic [axis_width_p-1:0]           buffer_read_data_lo;
  logic                              buffer_read_v_lo;

  logic [15:0]                       rx_packet_size_lo;

  logic       tx_error_underflow_lo;
  logic       tx_fifo_overflow_lo;
  logic       tx_fifo_bad_frame_lo;
  logic       tx_fifo_good_frame_lo;
  logic       rx_error_bad_frame_lo;
  logic       rx_error_bad_fcs_lo;
  logic       rx_fifo_overflow_lo;
  logic       rx_fifo_bad_frame_lo;
  logic       rx_fifo_good_frame_lo;
  logic [1:0] speed_lo;

  logic tx_interrupt_clear_lo;
  logic rx_interrupt_enable_lo, rx_interrupt_enable_v_lo;
  logic tx_interrupt_enable_lo, tx_interrupt_enable_v_lo;
  logic rx_interrupt_pending_lo, tx_interrupt_pending_lo;

  wire [15:0] debug_info_li = {
    tx_error_underflow_lo
   ,tx_fifo_overflow_lo
   ,tx_fifo_bad_frame_lo
   ,tx_fifo_good_frame_lo
   ,rx_error_bad_frame_lo
   ,rx_error_bad_fcs_lo
   ,rx_fifo_overflow_lo
   ,rx_fifo_bad_frame_lo
   ,rx_fifo_good_frame_lo
   ,speed_lo
   };

  logic io_decode_error_lo;

  ethernet_mmio_decoder #(
    .buf_size_p(buf_size_p)
   ,.axis_width_p(axis_width_p)
  ) decoder (
    .clk_i(clk_i)
   ,.reset_i(reset_i)

   ,.addr_i(addr_i)
   ,.write_en_i(write_en_i)
   ,.read_en_i(read_en_i)
   ,.op_size_i(op_size_i)
   ,.write_data_i(write_data_i)
   ,.read_data_o(read_data_o)
   ,.read_data_v_o(read_data_v_o)

   ,.debug_info_i(debug_info_li)
   ,.rx_ready_i(rx_ready_lo)
   ,.tx_ready_i(tx_ready_lo)
   ,.rx_packet_size_i(rx_packet_size_lo)

   ,.send_o(send_lo)
   ,.clear_buffer_o(clear_buffer_lo)
   ,.tx_packet_size_v_o(tx_packet_size_v_lo)
   ,.tx_packet_size_o(tx_packet_size_lo)
   ,.buffer_write_addr_o(buffer_write_addr_lo)
   ,.buffer_write_op_size_o(buffer_write_op_size_lo)
   ,.buffer_write_data_o(buffer_write_data_lo)
   ,.buffer_write_v_o(buffer_write_v_lo)

   ,.buffer_read_addr_o(buffer_read_addr_lo)
   ,.buffer_read_v_o(buffer_read_v_lo)
   ,.buffer_read_data_r_i(buffer_read_data_lo)

   ,.tx_interrupt_clear_o(tx_interrupt_clear_lo)

   ,.rx_interrupt_pending_i(rx_interrupt_pending_lo)
   ,.tx_interrupt_pending_i(tx_interrupt_pending_lo)
   ,.rx_interrupt_enable_o(rx_interrupt_enable_lo)
   ,.rx_interrupt_enable_v_o(rx_interrupt_enable_v_lo)
   ,.tx_interrupt_enable_o(tx_interrupt_enable_lo)
   ,.tx_interrupt_enable_v_o(tx_interrupt_enable_v_lo)

   ,.io_decode_error_o(io_decode_error_lo)
  );

  // synopsys translate_off
  always_ff @(negedge clk_i) begin
    if(~reset_i) begin
      assert(io_decode_error_lo == 0) else
        $error("ethernet_controller_core.sv: io decode error\n");
    end
  end
  // synopsys translate_on


  mac_with_buffer #(
    .PLATFORM(PLATFORM)
   ,.buf_size_p(buf_size_p)
   ,.axis_width_p(axis_width_p)
  ) eth (
    .clk_i(clk_i)
   ,.reset_i(reset_i)
   ,.clk250_i(clk250_i)
   ,.reset_clk250_i(reset_clk250_i)
   ,.reset_clk125_o(reset_clk125_o)

   ,.send_i(send_lo)
   ,.tx_ready_o(tx_ready_lo)
   ,.clear_buffer_i(clear_buffer_lo)
   ,.rx_ready_o(rx_ready_lo)

   ,.tx_packet_size_v_i(tx_packet_size_v_lo)
   ,.tx_packet_size_i(tx_packet_size_lo)

   ,.buffer_write_addr_i(buffer_write_addr_lo)
   ,.buffer_write_op_size_i(buffer_write_op_size_lo)
   ,.buffer_write_data_i(buffer_write_data_lo)
   ,.buffer_write_v_i(buffer_write_v_lo)

   ,.buffer_read_addr_i(buffer_read_addr_lo)
   ,.buffer_read_data_o(buffer_read_data_lo)
   ,.buffer_read_v_i(buffer_read_v_lo)

   ,.rx_packet_size_o(rx_packet_size_lo)

   ,.rgmii_rx_clk_i(rgmii_rx_clk_i)
   ,.rgmii_rxd_i(rgmii_rxd_i)
   ,.rgmii_rx_ctl_i(rgmii_rx_ctl_i)
   ,.rgmii_tx_clk_o(rgmii_tx_clk_o)
   ,.rgmii_txd_o(rgmii_txd_o)
   ,.rgmii_tx_ctl_o(rgmii_tx_ctl_o)

   ,.tx_error_underflow_o(tx_error_underflow_lo)
   ,.tx_fifo_overflow_o(tx_fifo_overflow_lo)
   ,.tx_fifo_bad_frame_o(tx_fifo_bad_frame_lo)
   ,.tx_fifo_good_frame_o(tx_fifo_good_frame_lo)
   ,.rx_error_bad_frame_o(rx_error_bad_frame_lo)
   ,.rx_error_bad_fcs_o(rx_error_bad_fcs_lo)
   ,.rx_fifo_overflow_o(rx_fifo_overflow_lo)
   ,.rx_fifo_bad_frame_o(rx_fifo_bad_frame_lo)
   ,.rx_fifo_good_frame_o(rx_fifo_good_frame_lo)

   ,.send_count_o(/* UNUSED */)
   ,.receive_count_o(/* UNUSED */)

   ,.speed_o(speed_lo)
   );


  interrupt_generator interrupt_generator (
    .clk_i(clk_i)
   ,.reset_i(reset_i)
   ,.rx_ready_i(rx_ready_lo)
   ,.tx_ready_i(tx_ready_lo)

   ,.tx_interrupt_clear_i(tx_interrupt_clear_lo)

   ,.rx_interrupt_enable_i(rx_interrupt_enable_lo)
   ,.rx_interrupt_enable_v_i(rx_interrupt_enable_v_lo)
   ,.tx_interrupt_enable_i(tx_interrupt_enable_lo)
   ,.tx_interrupt_enable_v_i(tx_interrupt_enable_v_lo)

   ,.rx_interrupt_pending_o(rx_interrupt_pending_lo)
   ,.tx_interrupt_pending_o(tx_interrupt_pending_lo)

   );

  assign rx_interrupt_pending_o = rx_interrupt_pending_lo;
  assign tx_interrupt_pending_o = tx_interrupt_pending_lo;

endmodule
