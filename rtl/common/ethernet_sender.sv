
module ethernet_sender #
(
      parameter  buf_size_p     = 2048 // byte
    , parameter  send_width_p   = 64
    , localparam packet_size_width_lp = $clog2(buf_size_p) + 1
    , localparam addr_width_lp = $clog2(buf_size_p)
)
(
      input  logic                              clk_i
    , input  logic                              reset_i
    , input  logic                              send_i  // finish writing packet
    , output logic                              ready_o // have space for writing

    , input  logic                              packet_size_v_i
    , input  logic [packet_size_width_lp - 1:0] packet_size_i

    , input  logic [addr_width_lp - 1:0]        buffer_write_addr_i
    , input  logic [1:0]                        buffer_write_op_size_i
    , input  logic [send_width_p-1:0]           buffer_write_data_i
    , input  logic                              buffer_write_v_i

    , output logic [send_width_p-1:0]           tx_axis_tdata_o
    , output logic [send_width_p/8-1:0]       tx_axis_tkeep_o
    , output logic                              tx_axis_tvalid_o
    , output logic                              tx_axis_tlast_o
    , input  logic                              tx_axis_tready_i
    , output logic                              tx_axis_tuser_o

    , output logic [15:0]                       send_count_o
);
    localparam send_ptr_width_lp = $clog2(buf_size_p/(send_width_p/8));
    localparam send_ptr_offset_width_lp = $clog2(send_width_p/8);

    logic [buf_size_p/(send_width_p/8) - 1:0][send_width_p-1:0] buffer_r;

    logic [send_ptr_width_lp - 1:0] send_ptr_r;
    logic [packet_size_width_lp - 1:0] packet_size_r;



    logic [send_width_p/8-1:0] tx_axis_tkeep_li;
    logic                      tx_axis_tlast_li;
    logic                      tx_axis_tuser_li;


    logic                      read_slot_v_lo;
    logic                      read_slot_ready_and_li;
    logic [15:0]               read_size_r_lo; // valid when read_slot_v_o == 1'b1
    logic                      read_v_li;
    logic [addr_width_lp-1:0]  read_addr_li;
    logic [send_width_p-1:0]   read_data_r_lo;

    logic send_ptr_increment;
    logic send_complete;


    logic [send_ptr_width_lp - 1:0] send_ptr_end;
    logic [send_ptr_offset_width_lp - 1 :0] send_remaining;
    logic last_send_f;

    logic write_slot_ready_and_lo;

    logic write_size_v_li;
    logic write_v_li;
    logic write_slot_v_li;

    tx_buffer_memory #(.slot_p(2)
       ,.data_width_p(send_width_p))
      tx_buffer_memory (
        .clk_i(clk_i)
       ,.reset_i(reset_i)

    // MAC side (read width is always data_width_lp)
       ,.read_slot_v_o(read_slot_v_lo)
       ,.read_slot_ready_and_i(read_slot_ready_and_li)
       ,.read_size_r_o(read_size_r_lo) // valid when read_slot_v_o == 1'b1
       ,.read_v_i(read_v_li)
       ,.read_addr_i(read_addr_li)
       ,.read_data_r_o(read_data_r_lo)

    // PL side
       ,.write_slot_v_i(write_slot_v_li)
       ,.write_slot_ready_and_o(write_slot_ready_and_lo)

       ,.write_size_v_i(write_size_v_li)
       ,.write_size_i(packet_size_i)

       ,.write_v_i(write_v_li)
       ,.write_addr_i(buffer_write_addr_i)
       ,.write_data_i(buffer_write_data_i)
       ,.write_op_size_i(buffer_write_op_size_i)
      );


    // used for aligning the control signals with the sycn read value
    bsg_dff_reset_en #(
        .width_p(send_width_p/8+2)
      ) tx_dff (
        .clk_i(clk_i)
       ,.reset_i(reset_i)
       ,.en_i(read_v_li)
       ,.data_i({tx_axis_tkeep_li, tx_axis_tlast_li, tx_axis_tuser_li})
       ,.data_o({tx_axis_tkeep_o, tx_axis_tlast_o, tx_axis_tuser_o})
      );
    bsg_dff_reset_set_clear #(.width_p(1)
      ) tx_axis_tvalid_dff (
        .clk_i(clk_i)
       ,.reset_i(reset_i)
       ,.set_i(read_v_li)
       ,.clear_i(tx_axis_tready_i)
       ,.data_o(tx_axis_tvalid_o)
      );

    logic send_ptr_unwind;
    bsg_counter_clear_up #( // unit: 'send_width_p/8' byte
        .max_val_p(buf_size_p/(send_width_p/8)-1)
       ,.init_val_p(0)
      ) send_counter (
        .clk_i(clk_i)
       ,.reset_i(reset_i)
       ,.clear_i(send_ptr_unwind)
       ,.up_i(send_ptr_increment)
       ,.count_o(send_ptr_r)
      );

    assign tx_axis_tdata_o = read_data_r_lo;
    assign read_addr_li = (addr_width_lp)'(send_ptr_r*(send_width_p/8));

    assign send_ptr_end = (send_ptr_width_lp)'((read_size_r_lo - 1) >> $clog2(send_width_p/8));
    assign send_remaining = read_size_r_lo[$clog2(send_width_p/8)-1:0];
    assign last_send_f = (send_ptr_r == send_ptr_end);

    wire space_available = ~(tx_axis_tvalid_o & ~tx_axis_tready_i);
    always_comb begin
      send_ptr_increment = 1'b0;
      send_ptr_unwind = 1'b0;
      read_v_li = 1'b0;
      read_slot_ready_and_li = 1'b0;
      send_complete = 1'b0;
      if(read_slot_v_lo) begin
        if(space_available) begin
          read_v_li = 1'b1;
          if(~last_send_f) begin
            send_ptr_increment = 1'b1;
          end
          else begin
            send_ptr_unwind = 1'b1;
            read_slot_ready_and_li = 1'b1; // switch to next read slot
            send_complete = 1'b1;
          end
        end
      end
    end
    assign tx_axis_tlast_li = last_send_f;
    assign tx_axis_tuser_li = 1'b0;

if(send_width_p == 64) begin
    always_comb begin
        if(!last_send_f)
            tx_axis_tkeep_li = '1;
        else begin
            tx_axis_tkeep_li = '0;
            case(send_remaining)
                3'd0:
                    tx_axis_tkeep_li = 8'b1111_1111;
                3'd1:
                    tx_axis_tkeep_li = 8'b0000_0001;
                3'd2:
                    tx_axis_tkeep_li = 8'b0000_0011;
                3'd3:
                    tx_axis_tkeep_li = 8'b0000_0111;
                3'd4:
                    tx_axis_tkeep_li = 8'b0000_1111;
                3'd5:
                    tx_axis_tkeep_li = 8'b0001_1111;
                3'd6:
                    tx_axis_tkeep_li = 8'b0011_1111;
                3'd7:
                    tx_axis_tkeep_li = 8'b0111_1111;
            endcase
        end
    end
end
else if(send_width_p == 32)begin
    always_comb begin
        if(!last_send_f)
            tx_axis_tkeep_li = '1;
        else begin
            tx_axis_tkeep_li = '0;
            case(send_remaining)
                2'd0:
                    tx_axis_tkeep_li = 4'b1111;
                2'd1:
                    tx_axis_tkeep_li = 4'b0001;
                2'd2:
                    tx_axis_tkeep_li = 4'b0011;
                2'd3:
                    tx_axis_tkeep_li = 4'b0111;
            endcase
        end
    end

end


    assign ready_o = write_slot_ready_and_lo;
    always_comb begin
      write_size_v_li = 1'b0;
      write_v_li = 1'b0;
      write_slot_v_li = 1'b0;
      if(write_slot_ready_and_lo) begin
        write_size_v_li = packet_size_v_i;
        write_v_li = buffer_write_v_i;
        write_slot_v_li = send_i;
      end
    end

    bsg_flow_counter #(.els_p((1 << 16) - 1)) send_count (
        .clk_i(clk_i)
       ,.reset_i(reset_i)
       ,.v_i(send_complete)
       ,.ready_i(1'b1)
       ,.yumi_i(1'b0)
       ,.count_o(send_count_o)
    );

    // synopsys translate_off
    always_ff @(posedge clk_i) begin
      if(~reset_i) begin
        assert(~(~write_slot_ready_and_lo & packet_size_v_i))
          else $error("writing size when tx not ready");
        assert(~(~write_slot_ready_and_lo & buffer_write_v_i))
          else $error("writing data when tx not ready");
        assert(~(~write_slot_ready_and_lo & send_i))
          else $error("sending packet when tx not ready");
        assert(send_width_p == 32 || send_width_p == 64)
          else $error("unsupported send_width_p");
      end
    end
    // synopsys translate_on

endmodule
