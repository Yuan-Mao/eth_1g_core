
`include "bsg_defines.v"

module rx_buffer_memory # (
    parameter  slot_p        = 2
  , parameter  data_width_p  = 64
  , localparam els_lp        = 2048
  , localparam addr_width_lp = $clog2(els_lp)
  , localparam read_mask_width_lp = data_width_p
  , localparam size_width_lp = 16
)
(
    input  logic clk_i
  , input  logic reset_i

    // PL side
  , output logic                     read_slot_v_o
  , input  logic                     read_slot_ready_and_i
  , output logic [size_width_lp-1:0] read_size_r_o // valid when read_slot_v_o == 1'b1
  , input  logic                     read_v_i
  , input  logic [addr_width_lp-1:0] read_addr_i
  , output logic [data_width_p-1:0]  read_data_o
  , input  logic [1:0]               read_op_size_i

    // MAC side (write width is always data_width_p)
  , input  logic                     write_slot_v_i
  , output logic                     write_slot_ready_and_o

  , input  logic                     write_size_v_i
  , input  logic [size_width_lp-1:0] write_size_i

  , input  logic                     write_v_i
  , input  logic [addr_width_lp-1:0] write_addr_i
  , input  logic [data_width_p-1:0]  write_data_i
);

    logic [data_width_p-1:0]         read_data_lo;
    logic [read_mask_width_lp-1:0]   read_mask_li;
    logic [data_width_p-1:0]         masked_read_data;

    logic misaligned_access;
    logic full_o;
    logic empty_o;

    logic [1:0]                prev_read_op_size_r;
    logic [addr_width_lp-1:0]  prev_read_addr_r;

    localparam lsb_lp = $clog2(data_width_p / 8);

    bsg_dff_reset_en #(.width_p(2)
      ) prev_read_op_size_reg (
        .clk_i(clk_i)
       ,.reset_i(reset_i)
       ,.en_i(read_v_i)
       ,.data_i(read_op_size_i)
       ,.data_o(prev_read_op_size_r)
      );
    bsg_dff_reset_en #(.width_p(addr_width_lp)
      ) prev_read_addr_reg (
        .clk_i(clk_i)
       ,.reset_i(reset_i)
       ,.en_i(read_v_i)
       ,.data_i(read_addr_i)
       ,.data_o(prev_read_addr_r)
      );
    // Decoding logic
if (data_width_p == 64) begin: p0
    always_comb begin
      read_mask_li = '0;
      masked_read_data = '0;

      read_data_o = read_data_lo;

      case(prev_read_op_size_r)
        2'b00: begin // 1
          for(int t = 0;t < 8;t = t + 1) begin
            if(prev_read_addr_r[2:0] == t) begin
              read_mask_li = 64'('hff << (8 * t));
              masked_read_data = read_data_lo & read_mask_li;
              read_data_o = (data_width_p)'(masked_read_data >> 8 * t);
            end
          end
        end
        2'b01: begin // 2
          for(int t = 0;t < 4;t = t + 1) begin
            if(prev_read_addr_r[2:1] == t) begin
              read_mask_li = 64'('hffff << (2 * 8 * t));
              masked_read_data = read_data_lo & read_mask_li;
              read_data_o = (data_width_p)'(masked_read_data >> (2 * 8 * t));
            end
          end
        end
        2'b10: begin // 4
          for(int t = 0;t < 2;t = t + 1) begin
            if(prev_read_addr_r[2] == t) begin
              read_mask_li = 64'('hffffffff << (4 * 8 * t));
              masked_read_data = read_data_lo & read_mask_li;
              read_data_o = (data_width_p)'(masked_read_data >> (4 * 8 * t));
            end
          end
        end
        2'b11: begin // 8
          read_data_o = read_data_lo;
        end
      endcase
    end
end
else if (data_width_p == 32) begin: p1
    always_comb begin
      read_mask_li = '0;
      masked_read_data = '0;

      read_data_o = read_data_lo;

      case(prev_read_op_size_r)
        2'b00: begin // 1
          for(int t = 0;t < 4;t = t + 1) begin
            if(prev_read_addr_r[1:0] == t) begin
              read_mask_li = 32'('hff << (8 * t));
              masked_read_data = read_data_lo & read_mask_li;
              read_data_o = (data_width_p)'(masked_read_data >> 8 * t);
            end
          end
        end
        2'b01: begin // 2
          for(int t = 0;t < 2;t = t + 1) begin
            if(prev_read_addr_r[1] == t) begin
              read_mask_li = 32'('hffff << (2 * 8 * t));
              masked_read_data = read_data_lo & read_mask_li;
              read_data_o = (data_width_p)'(masked_read_data >> (2 * 8 * t));
            end
          end
        end
        2'b10: begin // 8
          read_data_o = read_data_lo;
        end
      endcase
    end
end
    // misaligned access checking
    always_comb begin
      misaligned_access = 1'b0;
      // write
      if(write_v_i && (write_addr_i[lsb_lp-1:0] != (lsb_lp)'('b0)))
        misaligned_access = 1'b1;

      // read
      if(read_v_i) begin
        case(read_op_size_i)
          2'b01: begin // 2
            if(read_addr_i[0])
              misaligned_access = 1'b1;
          end
          2'b10: begin // 4
            if(read_addr_i[1:0])
              misaligned_access = 1'b1;
          end
          2'b11: begin // 8
            if(read_addr_i[2:0])
              misaligned_access = 1'b1;
          end
        endcase
      end
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

    bsg_fifo_tracker #(.els_p(slot_p)
    )  slot_ptr (
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

    bsg_decode #(.num_out_p(slot_p)
      ) rptr_one_hot (
        .i(rptr_r_lo)
       ,.o(rptr_one_hot_lo)
      );

    bsg_decode #(.num_out_p(slot_p)
      ) wptr_one_hot (
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

    localparam buffer_mem_els_lp = els_lp / (data_width_p / 8);
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
         ,.write_mask_i('1)
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
         ,.els_p(slot_p)
        ) size_mux (
          .data_i(read_size_r_lo)
         ,.sel_one_hot_i(rptr_one_hot_lo)
         ,.data_o(read_size_r_o)
        );

      bsg_mux_one_hot #(
          .width_p(data_width_p)
         ,.els_p(slot_p)
        ) data_mux (
          .data_i(read_data_r_lo)
         ,.sel_one_hot_i(prev_rptr_one_hot_lo)
         ,.data_o(read_data_lo)
        );

    // synopsys translate_off
    always_ff @(negedge clk_i) begin
      if(~reset_i) begin
        assert(read_op_size_i <= $clog2(data_width_p / 8))
            else $error("rx_memory_buffer: invalid runtime read_op_size_i");
        assert(misaligned_access == 0)
            else $error("rx_memory_buffer: misaligned access");
        assert(data_width_p == 32 || data_width_p == 64)
            else $error("rx_memory_buffer: unsupported data width");

      end
    end
    // synopsys translate_on

endmodule
