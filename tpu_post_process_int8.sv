`timescale 1ns/1ps

// Bias, ReLU, fixed-point requantization, and INT8 saturation.
// The block is combinational so it can sit directly on the tile readout path.
module tpu_postprocess_int8 (
    input  logic signed [31:0] acc_in,
    input  logic signed [31:0] bias_in,
    input  logic signed [31:0] quant_multiplier,
    input  logic        [5:0]  quant_shift,

    output logic signed [7:0]  data_out
);

    logic signed [31:0] biased_value;
    logic signed [31:0] relu_value;
    logic signed [63:0] scaled_value;
    logic signed [63:0] shifted_value;

    always_comb begin
        biased_value = acc_in + bias_in;

        if (biased_value < 0)
            relu_value = 32'sd0;
        else
            relu_value = biased_value;

        scaled_value = $signed(relu_value) * $signed(quant_multiplier);

        if (quant_shift >= 6'd63)
            shifted_value = (scaled_value < 0) ? -64'sd1 : 64'sd0;
        else
            shifted_value = scaled_value >>> quant_shift;

        if (shifted_value > 64'sd127)
            data_out = 8'sd127;
        else if (shifted_value < -64'sd128)
            data_out = -8'sd128;
        else
            data_out = shifted_value[7:0];
    end

endmodule
