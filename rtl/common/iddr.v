/*

Copyright (c) 2016-2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`timescale 1ns / 1ps

/*
 * Generic IDDR module
 */
module iddr #
(
    parameter PLATFORM = "SIM",
    // Width of register in bits
    parameter WIDTH = 1
)
(
    input  wire             clk,

    input  wire [WIDTH-1:0] d,

    output wire [WIDTH-1:0] q1,
    output wire [WIDTH-1:0] q2
);

/*

Provides a consistent input DDR flip flop across multiple FPGA families
              _____       _____       _____       _____       ____
    clk  ____/     \_____/     \_____/     \_____/     \_____/
         _ _____ _____ _____ _____ _____ _____ _____ _____ _____ _
    d    _X_D0__X_D1__X_D2__X_D3__X_D4__X_D5__X_D6__X_D7__X_D8__X_
         _______ ___________ ___________ ___________ ___________ _
    q1   _______X___________X____D0_____X____D2_____X____D4_____X_
         _______ ___________ ___________ ___________ ___________ _
    q2   _______X___________X____D1_____X____D3_____X____D5_____X_

*/

// target ("SIM", "GENERIC", "XILINX", "ALTERA")
parameter TARGET = (PLATFORM == "ZEDBOARD") ? "XILINX" : "";
// IODDR style ("IODDR", "IODDR2")
// Use IODDR for Virtex-4, Virtex-5, Virtex-6, 7 Series, Ultrascale
// Use IODDR2 for Spartan-6
parameter IODDR_STYLE = (PLATFORM == "ZEDBOARD") ? "IODDR" : "";

reg [WIDTH-1:0] delayed_d;

genvar n;

generate

if (TARGET == "XILINX") begin
    for (n = 0; n < WIDTH; n = n + 1) begin : iddr
        if (IODDR_STYLE == "IODDR") begin
            if (PLATFORM == "ZEDBOARD") begin
                // We need this to meet the timing
                //   requirement for RX side of the RGMII signals
                IDELAYE2 #(
                    .DELAY_SRC("IDATAIN")
                   ,.IDELAY_TYPE("FIXED")
                   ,.IDELAY_VALUE(0)
                   ,.REFCLK_FREQUENCY(200.0)
                   ,.SIGNAL_PATTERN("DATA")
                ) idelay2_inst (
                    .CNTVALUEOUT() // UNUSED
                   ,.DATAOUT(delayed_d[n])
                   ,.C(1'b0)
                   ,.CE(1'b0)
                   ,.CINVCTRL(1'b0)
                   ,.CNTVALUEIN('0)
                   ,.DATAIN() // UNUSED
                   ,.IDATAIN(d[n])
                   ,.INC(1'b0)
                   ,.LD(1'b0)
                   ,.LDPIPEEN(1'b0)
                   ,.REGRST(1'b0)
                );
            end else begin
                assign delayed_d[n] = d[n];
            end
                bsg_link_iddr_phy #(.width_p(1))
                  iddr_inst (
                    .clk_i(clk)
                   ,.data_i(delayed_d[n])
                   ,.data_r_o({q2[n], q1[n]})
                  );
        end else if (IODDR_STYLE == "IODDR2") begin
            IDDR2 #(
                .DDR_ALIGNMENT("C0")
            )
            iddr_inst (
                .Q0(q1[n]),
                .Q1(q2[n]),
                .C0(clk),
                .C1(~clk),
                .CE(1'b1),
                .D(d[n]),
                .R(1'b0),
                .S(1'b0)
            );
        end
    end
end else if (TARGET == "ALTERA") begin
    wire [WIDTH-1:0] q1_int;
    reg [WIDTH-1:0] q1_delay;

    altddio_in #(
        .WIDTH(WIDTH),
        .POWER_UP_HIGH("OFF")
    )
    altddio_in_inst (
        .aset(1'b0),
        .datain(d),
        .inclocken(1'b1),
        .inclock(clk),
        .aclr(1'b0),
        .dataout_h(q1_int),
        .dataout_l(q2)
    );

    always @(posedge clk) begin
        q1_delay <= q1_int;
    end

    assign q1 = q1_delay;
end else begin

    bsg_link_iddr_phy #(.width_p(WIDTH))
      iddr_inst (
        .clk_i(clk)
       ,.data_i(d)
       ,.data_r_o({q2, q1})
      );
end

endgenerate

endmodule
