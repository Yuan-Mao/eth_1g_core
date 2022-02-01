

`include "bsg_defines.v"

module oddr_clock_downsample
  (// reset, data and ready signals synchronous to clk_i
   // no valid signal required (assume valid_i is constant 1)
   input                      reset_i
  ,input                      clk_i
  ,input [1:0]                clk_setting_i
  ,output                     ready_o
   // output clock and data
  ,output logic               clk_r_o
  );
  
  logic odd_r, clk_r, reset_i_r;  
  logic [1:0] clk_setting_r;
  logic       clk_setting_r_2;
  
  // ready to accept new data every two cycles
  assign ready_o = ~odd_r;
  
  // register 2x-wide input data in flops
  always_ff @(posedge clk_i)
    if (~odd_r)
        clk_setting_r <= clk_setting_i;
        
  // odd_r signal (mux select bit)
  always_ff @(posedge clk_i)
    if (reset_i)
        odd_r <= 1'b0;
    else 
        odd_r <= ~odd_r;
  
  always_ff @(negedge clk_i)
    if (odd_r) 
        clk_setting_r_2 <= clk_setting_r[0];
    else 
        clk_setting_r_2 <= clk_setting_r[1];

  always_ff @(negedge clk_i)
    clk_r_o <= clk_setting_r_2;

endmodule

`BSG_ABSTRACT_MODULE(oddr_clock_downsample)
