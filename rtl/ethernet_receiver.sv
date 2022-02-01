module ethernet_receiver
#(
    parameter  recv_width_p = 64  // byte
  , parameter  buf_size_p = 2048 // byte
  , localparam addr_width_lp = $clog2(buf_size_p)
)
(
    input logic                          clk_i
  , input logic                          reset_i
  , input logic                          clear_buffer_i
  , output logic                         ready_o // packet is ready to read

  , input logic [addr_width_lp - 1:0]    buffer_read_addr_i
  , input logic [1:0]                    buffer_read_op_size_i
  , output logic [recv_width_p-1:0]      buffer_read_data_o
  , input logic                          buffer_read_v_i

  , output logic [15:0]                  rx_packet_size_o

  , input logic [recv_width_p-1:0]       rx_axis_tdata_i
  , input logic [recv_width_p/8-1:0]     rx_axis_tkeep_i
  , input logic                          rx_axis_tvalid_i
  , output logic                         rx_axis_tready_o
  , input logic                          rx_axis_tlast_i
  , input logic                          rx_axis_tuser_i

  , output logic [15:0]                  receive_count_o
);
  localparam recv_ptr_width_lp = $clog2(buf_size_p/(recv_width_p/8));

  logic                     read_slot_v_lo;
  logic                     read_slot_ready_and_li;
  logic [15:0]              read_size_r_lo; // valid when read_slot_v_o == 1'b1
  logic                     read_v_li;
  logic [addr_width_lp-1:0] read_addr_li;
  logic [recv_width_p-1:0]read_data_lo;
  logic [1:0]               read_op_size_li;

  logic                     write_slot_v_li;
  logic                     write_slot_ready_and_lo;

  logic                     write_size_v_li;
  logic [15:0]              write_size_li;

  logic                     write_v_li;
  logic [addr_width_lp-1:0] write_addr_li;
  logic [recv_width_p-1:0] write_data_li;

  logic recv_ptr_unwind;
  logic recv_ptr_increment;
  logic [recv_ptr_width_lp-1:0] recv_ptr_r;
  logic receive_complete;

  logic [15:0] packet_size_remaining;


if(recv_width_p == 64) begin
  always_comb begin
    packet_size_remaining = 16'd0;
    case(rx_axis_tkeep_i)
      8'b1111_1111:
        packet_size_remaining = 16'd8;
      8'b0111_1111:
        packet_size_remaining = 16'd7;
      8'b0011_1111:
        packet_size_remaining = 16'd6;
      8'b0001_1111:
        packet_size_remaining = 16'd5;
      8'b0000_1111:
        packet_size_remaining = 16'd4;
      8'b0000_0111:
        packet_size_remaining = 16'd3;
      8'b0000_0011:
        packet_size_remaining = 16'd2;
      8'b0000_0001:
        packet_size_remaining = 16'd1;
    endcase
  end
end
else if(recv_width_p == 32) begin
  always_comb begin
    packet_size_remaining = 16'd0;
    case(rx_axis_tkeep_i)
      4'b1111:
        packet_size_remaining = 16'd4;
      4'b0111:
        packet_size_remaining = 16'd3;
      4'b0011:
        packet_size_remaining = 16'd2;
      4'b0001:
        packet_size_remaining = 16'd1;
    endcase
  end

end

  bsg_counter_clear_up #( // unit: 'recv_width_p/8' byte
      .max_val_p(buf_size_p/(recv_width_p/8)-1)
     ,.init_val_p(0)
    ) recv_counter (
      .clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.clear_i(recv_ptr_unwind)
     ,.up_i(recv_ptr_increment)
     ,.count_o(recv_ptr_r)
    );

  assign ready_o = read_slot_v_lo;

  rx_buffer_memory #(.slot_p(2)
     ,.data_width_p(recv_width_p))
    rx_buffer_memory (
      .clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.read_slot_v_o(read_slot_v_lo)
     ,.read_slot_ready_and_i(read_slot_ready_and_li)
     ,.read_size_r_o(read_size_r_lo) // valid when read_slot_v_o == 1'b1
     ,.read_v_i(read_v_li)
     ,.read_addr_i(read_addr_li)
     ,.read_data_o(read_data_lo)
     ,.read_op_size_i(read_op_size_li)

     ,.write_slot_v_i(write_slot_v_li)
     ,.write_slot_ready_and_o(write_slot_ready_and_lo)

     ,.write_size_v_i(write_size_v_li)
     ,.write_size_i(write_size_li)

     ,.write_v_i(write_v_li)
     ,.write_addr_i(write_addr_li)
     ,.write_data_i(write_data_li)

    );
  bsg_flow_counter #(.els_p((1 << 16) - 1)
  ) receive_count (
    .clk_i(clk_i)
   ,.reset_i(reset_i)
   ,.v_i(receive_complete)
   ,.ready_i(1'b1)
   ,.yumi_i(1'b0)

   ,.count_o(receive_count_o)
  );

  always_comb begin
    rx_packet_size_o = '0;
    read_slot_ready_and_li = 1'b0;
    read_v_li = 1'b0;
    read_addr_li = buffer_read_addr_i;
    buffer_read_data_o = read_data_lo;
    read_op_size_li = buffer_read_op_size_i;
    if(read_slot_v_lo) begin
      rx_packet_size_o = read_size_r_lo;
      read_slot_ready_and_li = clear_buffer_i;
      read_v_li = buffer_read_v_i;
    end
  end

  // synopsys translate_off
  always_ff @(posedge clk_i) begin
    if(~reset_i) begin
      assert(~(~read_slot_v_lo & buffer_read_v_i))
        else $error("reading data when rx not ready");
      assert(~(~read_slot_v_lo & clear_buffer_i))
        else $error("receiving packet when rx not ready");
    end
  end
  // synopsys translate_on

  always_comb begin
    rx_axis_tready_o = 1'b0;
    recv_ptr_unwind = 1'b0;
    recv_ptr_increment = 1'b0;
    write_slot_v_li = 1'b0;
    write_size_li = '0;
    write_size_v_li = 1'b0;
    write_v_li = 1'b0;
    write_addr_li = '0;
    write_data_li = '0;
    receive_complete = 1'b0;
    if(write_slot_ready_and_lo) begin
      rx_axis_tready_o = 1'b1;
      if(rx_axis_tvalid_i) begin
        write_v_li = 1'b1;
        write_addr_li = addr_width_lp'(recv_ptr_r*(recv_width_p/8));
        write_data_li = rx_axis_tdata_i;
        if(rx_axis_tlast_i) begin
          recv_ptr_unwind = 1'b1;
          if(~rx_axis_tuser_i) begin
            // end of good frame
            write_slot_v_li = 1'b1;
            write_size_li = (recv_ptr_r*(recv_width_p/8)) + packet_size_remaining;
            write_size_v_li = 1'b1;
            receive_complete = 1'b1;
          end
        end
        else begin // ~tlast
          recv_ptr_increment = 1'b1;
        end
      end
    end
  end

endmodule
