`timescale 1ns/1ps

// Bias, ReLU, fixed-point requantization, and INT8 saturation.
// Three-stage pipeline for 100 MHz closure: LATENCY cycles from valid_in.
//   Stage 1: bias addition + ReLU
//   Stage 2: fixed-point multiply (maps to a registered DSP slice)
//   Stage 3: arithmetic right shift + signed INT8 saturation
module tpu_postprocess_int8 (
    input  logic                      clk,
    input  logic                      rst_n,

    input  logic                      valid_in,
    input  logic signed [31:0]        acc_in,
    input  logic signed [31:0]        bias_in,
    input  logic signed [31:0]        quant_multiplier,
    input  logic        [5:0]         quant_shift,

    output logic                      valid_out,
    output logic signed [7:0]         data_out
);

    // Cycles from valid_in/data_in to valid_out/data_out.
    localparam int LATENCY = 3;

    // Stage 1: bias addition and ReLU.
    logic               valid_s1;
    logic signed [31:0] relu_s1;
    logic signed [31:0] mult_s1;
    logic        [5:0]  shift_s1;

    logic signed [31:0] biased_comb;

    always_comb biased_comb = acc_in + bias_in;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_s1 <= 1'b0;
            relu_s1  <= '0;
            mult_s1  <= '0;
            shift_s1 <= '0;
        end else begin
            valid_s1 <= valid_in;
            relu_s1  <= (biased_comb < 0) ? 32'sd0 : biased_comb;
            mult_s1  <= quant_multiplier;
            shift_s1 <= quant_shift;
        end
    end

    // Stage 2: fixed-point multiply.
    logic               valid_s2;
    logic signed [63:0] scaled_s2;
    logic        [5:0]  shift_s2;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_s2  <= 1'b0;
            scaled_s2 <= '0;
            shift_s2  <= '0;
        end else begin
            valid_s2  <= valid_s1;
            scaled_s2 <= $signed(relu_s1) * $signed(mult_s1);
            shift_s2  <= shift_s1;
        end
    end

    // Stage 3: arithmetic right shift and INT8 saturation.
    logic signed [63:0] shifted_comb;

    always_comb begin
        if (shift_s2 >= 6'd63)
            shifted_comb = (scaled_s2 < 0) ? -64'sd1 : 64'sd0;
        else
            shifted_comb = scaled_s2 >>> shift_s2;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            data_out  <= '0;
        end else begin
            valid_out <= valid_s2;
            if (shifted_comb > 64'sd127)
                data_out <= 8'sd127;
            else if (shifted_comb < -64'sd128)
                data_out <= -8'sd128;
            else
                data_out <= shifted_comb[7:0];
        end
    end

endmodule
