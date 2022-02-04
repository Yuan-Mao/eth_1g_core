
module ethernet_mmio_decoder #
(
      parameter  buf_size_p           = 2048 // byte
    , parameter  axis_width_p         = 32
    , parameter  gap_delay_p          = 12 // clock cycle
    , parameter  packet_size_width_lp = $clog2(buf_size_p) + 1
    , parameter  addr_width_lp        = $clog2(buf_size_p)
)
(
      input  logic                              clk_i
    , input  logic                              reset_i

    , input  logic [15:0]                       addr_i
    , input  logic                              write_en_i
    , input  logic                              read_en_i

    , input  logic [1:0]                        op_size_i
    , input  logic [axis_width_p-1:0]     write_data_i
    , output logic [axis_width_p-1:0]     read_data_o // sync read
    , output logic [axis_width_p-1:0]     read_data_v_o

    , input  logic [15:0]                       debug_info_i
    , input  logic                              rx_ready_i
    , input  logic                              tx_ready_i
    , input  logic [15:0]                       rx_packet_size_i

    , output logic                              send_o
    , output logic                              clear_buffer_o
    , output logic                              tx_packet_size_v_o
    , output logic [packet_size_width_lp - 1:0] tx_packet_size_o
    , output logic [addr_width_lp - 1:0]        buffer_write_addr_o
    , output logic [1:0]                        buffer_write_op_size_o
    , output logic [axis_width_p-1:0]      buffer_write_data_o
    , output logic                              buffer_write_v_o

      // buffer_read_data_r_i does sync read
    , output logic [addr_width_lp - 1:0]        buffer_read_addr_o
    , output logic                              buffer_read_v_o
    , input  logic [axis_width_p-1:0]     buffer_read_data_r_i

    , output logic                              tx_interrupt_clear_o

    , input  logic                              rx_interrupt_pending_i
    , input  logic                              tx_interrupt_pending_i
    , output logic                              rx_interrupt_enable_o
    , output logic                              rx_interrupt_enable_v_o
    , output logic                              tx_interrupt_enable_o
    , output logic                              tx_interrupt_enable_v_o

    , output logic                              io_decode_error_o
);
/*
 *
 * RX/TX Buffers:
 *
 *   RX Buffer:
 *     0x0000-0x0800
 *   TX Buffer:
 *     0x0800-0x1000
 *
 * Register Map:
 *
 *   Readable Register Map:
 *     0x1000: Index of current received packet  (a.k.a LITEETH_WRITER_SLOT); 8-bit
 *     0x1004: Length of current received packet (a.k.a LITEETH_WRITER_LENGTH); 16, 32-bit
 *     0x1010: RX Event Pending Bit (a.k.a LITEETH_WRITER_EV_PENDING); 8-bit
 *     0x101C: TX Ready Bit         (a.k.a LITEETH_READER_READY); 8-bit
 *     0x1030: TX Event Pending Bit (a.k.a LITEETH_READER_EV_PENDING); 8-bit
 *     0x1050: Debug Info (not compatible with Liteeth); 32-bit
 *
 *   Writable Register Map:
 *     0x1010: RX Event Pending Bit (a.k.a LITEETH_WRITER_EV_PENDING); 8-bit
 *     0x1014: RX Event Enable Bit  (a.k.a LITEETH_WRITER_EV_ENABLE); 8-bit
 *     0x1018: TX Send Bit          (a.k.a LITEETH_READER_START); 8-bit
 *     0x1024: Index of the transmitting packet  (a.k.a LITEETH_READER_SLOT); 8-bit (UNUSED)
 *     0x1028: Length of the transmitting packet (a.k.a LITEETH_READER_LENGTH); 16, 32-bit
 *     0x1030: TX Event Pending Bit (a.k.a LITEETH_READER_EV_PENDING); 8-bit
 *     0x1034: TX Event Enable Bit  (a.k.a LITEETH_READER_EV_ENABLE); 8-bit
 *
 * Note:
 *   * The clear OP for pending bit will immediately take effect right after the next
 *     posedge clk_i, but the internal setting of pending bit has priority over clear.
 *   * There's no RX ready bit. Use RX Event Pending Bit instead.
 * 
 */

    logic buffer_read_v_r;
    logic [axis_width_p-1:0] readable_reg_r, readable_reg_n;
    logic rx_interrupt_clear, tx_interrupt_clear;
    logic tx_idx_r, tx_idx_n; // UNUSED

    bsg_dff_reset
     #(.width_p(axis_width_p + 2))
      register
       (.clk_i(clk_i)
        ,.reset_i(reset_i)
        ,.data_i({readable_reg_n, buffer_read_v_o, tx_idx_n})
        ,.data_o({readable_reg_r, buffer_read_v_r, tx_idx_r})
        );

    always_comb begin
      io_decode_error_o = 1'b0;
      buffer_read_addr_o = '0;
      buffer_read_v_o = 1'b0;

      buffer_write_addr_o = '0;
      buffer_write_op_size_o = '0;
      buffer_write_data_o = '0;
      buffer_write_v_o = 1'b0;

      readable_reg_n = '0;
      send_o = 1'b0;
      tx_idx_n     = tx_idx_r;
      rx_interrupt_clear = 1'b0;
      tx_interrupt_clear = 1'b0;

      rx_interrupt_enable_o = 1'b0;
      rx_interrupt_enable_v_o = 1'b0;
      tx_interrupt_enable_o = 1'b0;
      tx_interrupt_enable_v_o = 1'b0;

      tx_packet_size_o = '0;
      tx_packet_size_v_o = 1'b0;
      casez(addr_i)
        16'h0???: begin
          if(addr_i < 16'h0800) begin
            // RX buffer, r
            if(read_en_i) begin
              buffer_read_addr_o = addr_i[addr_width_lp-1:0];
              buffer_read_v_o = 1'b1;
            end
            if(write_en_i)
              io_decode_error_o = 1'b1;
          end
          else begin
            // TX buffer, w
            if(read_en_i)
              io_decode_error_o = 1'b1;
            if(write_en_i) begin
              buffer_write_addr_o = addr_i[addr_width_lp-1:0];
              buffer_write_op_size_o = op_size_i;
              buffer_write_data_o = write_data_i;
              buffer_write_v_o = 1'b1;
            end
          end
        end
        16'h1000: begin
          // RX current slot index, r, 8-bit
          if(read_en_i)
            readable_reg_n  = '0; // always 0
          if(write_en_i)
            io_decode_error_o = 1'b1;
        end
        16'h1004: begin
          // RX received size, r, 16, 32-bit
          if(read_en_i) begin
            if(rx_ready_i)
              readable_reg_n  = rx_packet_size_i;
          end
          if(write_en_i)
            io_decode_error_o = 1'b1;
        end
        16'h1010: begin
          // RX EV Pending, rw, 8-bit
          if(read_en_i)
            readable_reg_n = rx_interrupt_pending_i;
          if(write_en_i) begin
            if(write_data_i[0] == 'b1) begin
              // Generate a pulse signal for clear
              rx_interrupt_clear = 1'b1;
            end
          end
        end
        16'h1014: begin
          // RX EV Enable, w, 8-bit
          if(read_en_i)
            io_decode_error_o = 1'b1;
          if(write_en_i) begin
            rx_interrupt_enable_o = write_data_i[0];
            rx_interrupt_enable_v_o = 1'b1;
          end
        end
        16'h1018: begin
          // TX Send Bit, w, 8-bit
          if(read_en_i)
            io_decode_error_o = 1'b1;
          if(write_en_i)
            send_o = 1'b1;
        end
        16'h101C: begin
          // TX Ready bit, r, 8-bit
          if(read_en_i)
            readable_reg_n = tx_ready_i;
          if(write_en_i)
            io_decode_error_o = 1'b1;
        end
        16'h1024: begin
          // TX current slot index, w, 8-bit
          if(read_en_i)
            io_decode_error_o = 1'b1;
          if(write_en_i)
            tx_idx_n = write_data_i[0];
        end
        16'h1028: begin
          // TX size, w, 16, 32-bit
          if(read_en_i)
            io_decode_error_o = 1'b1;
          if(write_en_i) begin
            tx_packet_size_o = write_data_i;
            tx_packet_size_v_o = 1'b1;
          end
        end
        16'h1030: begin
          // TX Pending Bit, rw, 8-bit
          if(read_en_i)
            readable_reg_n = tx_interrupt_pending_i;
          if(write_en_i) begin
            if(write_data_i[0] == 'b1) begin
              // Generate a pulse signal for clear
              tx_interrupt_clear = 1'b1;
            end
          end
        end
        16'h1034: begin
          // TX Enable Bit, w, 8-bit
          if(read_en_i)
            io_decode_error_o = 1'b1;
          if(write_en_i) begin
            tx_interrupt_enable_o = write_data_i[0];
            tx_interrupt_enable_v_o = 1'b1;
          end
        end
        16'h1050: begin
          // Debug Info, r, 32-bit
          if(read_en_i)
            readable_reg_n = debug_info_i;
          if(write_en_i)
            io_decode_error_o = 1'b1;
        end

        default: begin
          // Unsupported MMIO
          if(read_en_i || write_en_i)
            io_decode_error_o = 1'b1;
        end
      endcase
      if(read_en_i & write_en_i)
        io_decode_error_o = 1'b1;
    end

    bsg_dff_reset #(.width_p(1)
    ) read_data_v_reg (
      .clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.data_i(read_en_i & ~io_decode_error_o)
     ,.data_o(read_data_v_o)
    );

    // Output can either come from RX buffer or registers
    assign read_data_o = buffer_read_v_r ? buffer_read_data_r_i : readable_reg_r;

    assign clear_buffer_o       = rx_interrupt_clear;
    assign tx_interrupt_clear_o = tx_interrupt_clear;
endmodule
