`timescale 1ns/1ps

// Wrapper around the original 4x4 tile. The original tile RTL is unchanged.
// Each streamed INT32 result is pipelined through the post-processing datapath:
// bias add -> ReLU -> fixed-point scale -> signed INT8 saturation.
//
// The processed byte leaves POST_LATENCY cycles after the core presents a
// result. Metadata (index/row/col), the raw accumulator, and done are delayed
// by the same amount so every output stays aligned with result_data.
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

    // Must match the pipeline depth of tpu_postprocess_int8.
    localparam int POST_LATENCY = 3;

    logic signed [31:0] bias_mem [0:15];

    logic               core_busy;
    logic               core_done;
    logic               core_result_valid;
    logic [3:0]         core_result_index;
    logic [1:0]         core_result_row;
    logic [1:0]         core_result_col;
    logic signed [31:0] core_result_data;

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
        .done         (core_done),
        .result_valid (core_result_valid),
        .result_index (core_result_index),
        .result_row   (core_result_row),
        .result_col   (core_result_col),
        .result_data  (core_result_data)
    );

    tpu_postprocess_int8 u_postprocess (
        .clk              (clk),
        .rst_n            (rst_n),
        .valid_in         (core_result_valid),
        .acc_in           (core_result_data),
        .bias_in          (bias_mem[core_result_index]),
        .quant_multiplier (quant_multiplier),
        .quant_shift      (quant_shift),
        .valid_out        (result_valid),
        .data_out         (result_data)
    );

    // Delay lines that keep metadata, the raw accumulator, valid, and done
    // aligned with the processed byte.
    logic [3:0]              index_pipe [1:POST_LATENCY];
    logic [1:0]              row_pipe   [1:POST_LATENCY];
    logic [1:0]              col_pipe   [1:POST_LATENCY];
    logic signed [31:0]      acc_pipe   [1:POST_LATENCY];
    logic [POST_LATENCY:1]   valid_pipe;
    logic [POST_LATENCY:1]   done_pipe;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 1; i <= POST_LATENCY; i = i + 1) begin
                index_pipe[i] <= '0;
                row_pipe[i]   <= '0;
                col_pipe[i]   <= '0;
                acc_pipe[i]   <= '0;
            end
            valid_pipe <= '0;
            done_pipe  <= '0;
        end else begin
            index_pipe[1] <= core_result_index;
            row_pipe[1]   <= core_result_row;
            col_pipe[1]   <= core_result_col;
            acc_pipe[1]   <= core_result_data;
            valid_pipe[1] <= core_result_valid;
            done_pipe[1]  <= core_done;
            for (int i = 2; i <= POST_LATENCY; i = i + 1) begin
                index_pipe[i] <= index_pipe[i-1];
                row_pipe[i]   <= row_pipe[i-1];
                col_pipe[i]   <= col_pipe[i-1];
                acc_pipe[i]   <= acc_pipe[i-1];
                valid_pipe[i] <= valid_pipe[i-1];
                done_pipe[i]  <= done_pipe[i-1];
            end
        end
    end

    assign result_index       = index_pipe[POST_LATENCY];
    assign result_row         = row_pipe[POST_LATENCY];
    assign result_col         = col_pipe[POST_LATENCY];
    assign result_accumulator = acc_pipe[POST_LATENCY];
    assign done               = done_pipe[POST_LATENCY];

    // Stay busy until the post-processing pipeline has fully drained.
    assign busy = core_busy || (|valid_pipe);

endmodule
