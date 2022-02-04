
`include "bsg_defines.v"

/*
 *
 *   This modules implements a FIFO used for buffering Ethernet packets. It can achieve up to 1r1w per
 * cycle. The FIFO consists of slots, and each slot contains an Ethernet packet.
 *   When read_slot_v_o == 1'b1, the read slot is valid; the size and content of the
 * received packet can be read through the corresponding read signals. When the received packet in the
 * read slot is no longer needed, set read_slot_ready_and_i to 1'b1 to free the slot.
 *   When write_slot_ready_and_o == 1'b1, the write slot is valid and the size and content of the
 * incoming packet can be written through the corresponding write signals. After finishing writing it,
 * set write_slot_v_i to 1'b1 to reserve the slot.
 *
 *
 * When slot_p == 2, and a packet has been written in slot 0:
 *
 *                     .____________.   ->  read slot ptr
 *                     |____word____|
 *                     |     .      |
 *                     |     .      |
 *                     |     .      |
 *                     |            |
 *                     |   slot 0   |
 *                     |            |
 *                     |____________|
 *                     |____word____|
 *
 *  write slot ptr ->  .____________.
 *                     |____word____|
 *                     |     .      |
 *                     |     .      |
 *                     |     .      |
 *                     |            |
 *                     |   slot 1   |
 *                     |            |
 *                     |____________|
 *                     |____word____|
 *
 *
 */

module packet_buffer # (
      parameter  slot_p        = 2
    , parameter  data_width_p  = 64
    , localparam els_lp        = 2048
    , localparam addr_width_lp = $clog2(els_lp)
    , localparam write_mask_width_lp = (data_width_p >> 3)
    , localparam size_width_lp = 16
)
(
      input  logic clk_i
    , input  logic reset_i

    /** read side **/
    , output logic                     read_slot_v_o
    , input  logic                     read_slot_ready_and_i

    , output logic [size_width_lp-1:0] read_size_r_o // packet size

    // read data size is always data_width_p
    // read address should be aligned with data_width_p
    // sync read
    , input  logic                     read_v_i
    , input  logic [addr_width_lp-1:0] read_addr_i
    , output logic [data_width_p-1:0]  read_data_o

    /** write side **/
    , input  logic                     write_slot_v_i
    , output logic                     write_slot_ready_and_o

    , input  logic                     write_size_v_i
    , input  logic [size_width_lp-1:0] write_size_i

    , input  logic                     write_v_i
    , input  logic [addr_width_lp-1:0] write_addr_i
    , input  logic [data_width_p-1:0]  write_data_i
    , input  logic [1:0]               write_op_size_i
);

  logic misaligned_access;
  logic full_o;
  logic empty_o;

  logic [7:0]                      write_mask;
  logic [write_mask_width_lp-1:0]  write_mask_li;

  localparam lsb_lp = $clog2(data_width_p >> 3);

  always_comb begin
    write_mask = '0;
    misaligned_access = 1'b0;

    // write
    if(write_v_i) begin
      case(write_op_size_i)
        2'b00: begin // 1
          write_mask = 8'b1 << write_addr_i[2:0];
        end
        2'b01: begin // 2
          if(write_addr_i[0])
            misaligned_access = 1'b1;
          write_mask = 8'b11 << {write_addr_i[2:1], 1'b0};
        end
        2'b10: begin // 4
          if(write_addr_i[1:0])
            misaligned_access = 1'b1;
          write_mask = 8'b1111 << {write_addr_i[2], 2'b00};
        end
        2'b11: begin // 8
          if(write_addr_i[2:0])
            misaligned_access = 1'b1;
          write_mask = 8'b1111_1111;
        end
      endcase
    end

    // read
    if(read_v_i) begin
      if(data_width_p == 64) begin
        if(read_addr_i[2:0])
          misaligned_access = 1'b1;
      end
      else if(data_width_p == 32) begin
        if(read_addr_i[1:0])
          misaligned_access = 1'b1;
      end
    end
  end

if (data_width_p == 64) begin
  assign write_mask_li = write_mask;
end else if (data_width_p == 32) begin
  assign write_mask_li = write_mask[7:4] | write_mask[3:0];
end


  wire readable = ~empty_o;
  wire writable = ~full_o;
  assign read_slot_v_o = readable;
  assign write_slot_ready_and_o = writable;
  wire enq_li = write_slot_v_i & write_slot_ready_and_o;
  wire deq_li = read_slot_v_o & read_slot_ready_and_i;

  logic [`BSG_SAFE_CLOG2(slot_p)-1:0] wptr_r_lo;
  logic [`BSG_SAFE_CLOG2(slot_p)-1:0] rptr_r_lo;
  logic [slot_p-1:0] rptr_one_hot_lo;
  logic [slot_p-1:0] wptr_one_hot_lo;

  bsg_fifo_tracker #(.els_p(slot_p))
   slot_ptr (
      .clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.enq_i(enq_li)
     ,.deq_i(deq_li)

     ,.wptr_r_o(wptr_r_lo)
     ,.rptr_r_o(rptr_r_lo)
     ,.rptr_n_o(/* UNUSED */)

     ,.full_o(full_o)
     ,.empty_o(empty_o)
    );

  bsg_decode #(.num_out_p(slot_p))
   rptr_one_hot (
      .i(rptr_r_lo)
     ,.o(rptr_one_hot_lo)
    );

  bsg_decode #(.num_out_p(slot_p))
   wptr_one_hot (
      .i(wptr_r_lo)
     ,.o(wptr_one_hot_lo)
    );

  logic [slot_p-1:0] prev_rptr_one_hot_lo;
  wire data_reading = read_v_i & readable;
  bsg_dff_reset_en #(.width_p(slot_p)
    ) prev_rptr_one_hot_reg (
      .clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.en_i(data_reading)
     ,.data_i(rptr_one_hot_lo)
     ,.data_o(prev_rptr_one_hot_lo)
    );

  logic [slot_p-1:0][size_width_lp-1:0] read_size_r_lo;
  logic [slot_p-1:0][data_width_p-1:0] read_data_r_lo;

  localparam buffer_mem_els_lp = els_lp / (data_width_p >> 3);
  localparam buffer_mem_addr_width_lp = $clog2(buffer_mem_els_lp);
genvar i;
generate
  for(i = 0;i < slot_p;i = i + 1) begin: slot

    wire per_slot_data_reading = rptr_one_hot_lo[i] & read_v_i & readable;
    wire per_slot_data_writing = wptr_one_hot_lo[i] & write_v_i & writable;

    logic [buffer_mem_addr_width_lp-1:0] selected_addr_lo;
    wire v_li = per_slot_data_reading | per_slot_data_writing;
    wire w_li = per_slot_data_writing;

    bsg_mux_one_hot #(
        .width_p(buffer_mem_addr_width_lp)
       ,.els_p(2)
      ) addr_mux (
        .data_i({read_addr_i[addr_width_lp-1:lsb_lp], write_addr_i[addr_width_lp-1:lsb_lp]})
       ,.sel_one_hot_i({per_slot_data_reading, per_slot_data_writing})
       ,.data_o(selected_addr_lo)
      );

    bsg_mem_1rw_sync_mask_write_byte #(
        .els_p(buffer_mem_els_lp)
       ,.data_width_p(data_width_p)
      ) buffer_mem (
        .clk_i(clk_i)
       ,.reset_i(reset_i)
       ,.v_i(v_li)
       ,.w_i(w_li)
       ,.addr_i(selected_addr_lo)
       ,.data_i(write_data_i)
       ,.write_mask_i(write_mask_li)
       ,.data_o(read_data_r_lo[i])
      );

    wire size_writing = wptr_one_hot_lo[i] & write_size_v_i & writable;
    bsg_dff_reset_en #(.width_p(size_width_lp)
      ) size_dff (
        .clk_i(clk_i)
       ,.reset_i(reset_i)
       ,.en_i(size_writing)
       ,.data_i(write_size_i)
       ,.data_o(read_size_r_lo[i])
    );
  end
endgenerate

  bsg_mux_one_hot #(
    .width_p(size_width_lp)
    ,.els_p(slot_p))
   size_mux (
    .data_i(read_size_r_lo)
    ,.sel_one_hot_i(rptr_one_hot_lo)
    ,.data_o(read_size_r_o)
    );

  bsg_mux_one_hot #(
    .width_p(data_width_p)
    ,.els_p(slot_p))
   data_mux (
    .data_i(read_data_r_lo)
    ,.sel_one_hot_i(prev_rptr_one_hot_lo)
    ,.data_o(read_data_o)
    );

  // synopsys translate_off
  always_ff @(negedge clk_i) begin
    if(~reset_i) begin
      assert(misaligned_access == 0)
          else $error("rx_memory_buffer: misaligned access");
      assert(data_width_p == 32 || data_width_p == 64)
          else $error("rx_memory_buffer: unsupported data width");
    end
  end
  // synopsys translate_on

endmodule
