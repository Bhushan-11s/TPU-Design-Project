`timescale 1ns/1ps

// Wrapper around the original 4x4 tile. The original tile RTL is unchanged.
// Each streamed INT32 result is processed as:
// bias add -> ReLU -> fixed-point scale -> signed INT8 saturation.
module systolic_core_4x4_postprocessed (
    input  logic                       clk,
    input  logic                       rst_n,

    input  logic                       load_a,
    input  logic                       load_b,
    input  logic [1:0]                 load_row,
    input  logic [1:0]                 load_col,
    input  logic signed [7:0]          load_data,
    input  logic                       start,

    input  logic                       load_bias,
    input  logic [3:0]                 bias_index,
    input  logic signed [31:0]         bias_data,
    input  logic signed [31:0]         quant_multiplier,
    input  logic        [5:0]          quant_shift,

    output logic                       busy,
    output logic                       done,
    output logic                       result_valid,
    output logic [3:0]                 result_index,
    output logic [1:0]                 result_row,
    output logic [1:0]                 result_col,
    output logic signed [31:0]         result_accumulator,
    output logic signed [7:0]          result_data
);

    logic signed [31:0] bias_mem [0:15];
    logic signed [31:0] core_result_data;
    logic               core_busy;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < 16; i = i + 1)
                bias_mem[i] <= '0;
        end else if (load_bias && !core_busy) begin
            bias_mem[bias_index] <= bias_data;
        end
    end

    systolic_core_4x4 u_core (
        .clk          (clk),
        .rst_n        (rst_n),
        .load_a       (load_a),
        .load_b       (load_b),
        .load_row     (load_row),
        .load_col     (load_col),
        .load_data    (load_data),
        .start        (start),
        .busy         (core_busy),
        .done         (done),
        .result_valid (result_valid),
        .result_index (result_index),
        .result_row   (result_row),
        .result_col   (result_col),
        .result_data  (core_result_data)
    );

    assign busy               = core_busy;
    assign result_accumulator = core_result_data;

    tpu_postprocess_int8 u_postprocess (
        .acc_in           (core_result_data),
        .bias_in          (bias_mem[result_index]),
        .quant_multiplier (quant_multiplier),
        .quant_shift      (quant_shift),
        .data_out         (result_data)
    );

endmodule
