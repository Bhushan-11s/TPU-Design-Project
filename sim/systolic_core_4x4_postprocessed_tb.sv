`timescale 1ns/1ps

module systolic_core_4x4_postprocessed_tb;

    logic clk;
    logic rst_n;
    logic load_a;
    logic load_b;
    logic [1:0] load_row;
    logic [1:0] load_col;
    logic signed [7:0] load_data;
    logic start;
    logic load_bias;
    logic [3:0] bias_index;
    logic signed [31:0] bias_data;
    logic signed [31:0] quant_multiplier;
    logic [5:0] quant_shift;

    logic busy;
    logic done;
    logic result_valid;
    logic [3:0] result_index;
    logic [1:0] result_row;
    logic [1:0] result_col;
    logic signed [31:0] result_accumulator;
    logic signed [7:0] result_data;

    systolic_core_4x4_postprocessed dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .load_a             (load_a),
        .load_b             (load_b),
        .load_row           (load_row),
        .load_col           (load_col),
        .load_data          (load_data),
        .start              (start),
        .load_bias          (load_bias),
        .bias_index         (bias_index),
        .bias_data          (bias_data),
        .quant_multiplier   (quant_multiplier),
        .quant_shift        (quant_shift),
        .busy               (busy),
        .done               (done),
        .result_valid       (result_valid),
        .result_index       (result_index),
        .result_row         (result_row),
        .result_col         (result_col),
        .result_accumulator (result_accumulator),
        .result_data        (result_data)
    );

    always #5 clk = ~clk;

    task automatic write_matrix(
        input logic write_a_value,
        input logic [1:0] row,
        input logic [1:0] col,
        input logic signed [7:0] value
    );
        begin
            @(negedge clk);
            load_a = write_a_value;
            load_b = !write_a_value;
            load_row = row;
            load_col = col;
            load_data = value;
            @(posedge clk);
            #1 begin
                load_a = 1'b0;
                load_b = 1'b0;
            end
        end
    endtask

    task automatic write_bias(
        input logic [3:0] index,
        input logic signed [31:0] value
    );
        begin
            @(negedge clk);
            load_bias = 1'b1;
            bias_index = index;
            bias_data = value;
            @(posedge clk);
            #1 load_bias = 1'b0;
        end
    endtask

    function automatic logic signed [31:0] expected_acc(input logic [3:0] index);
        case (index)
            4'd0: expected_acc = 32'sd15;
            4'd1: expected_acc = 32'sd12;
            4'd2: expected_acc = 32'sd1;
            4'd3: expected_acc = 32'sd12;
            4'd4: expected_acc = 32'sd39;
            4'd5: expected_acc = 32'sd24;
            4'd6: expected_acc = 32'sd9;
            4'd7: expected_acc = 32'sd28;
            4'd8: expected_acc = 32'sd13;
            4'd9: expected_acc = 32'sd24;
            4'd10: expected_acc = -32'sd9;
            4'd11: expected_acc = -32'sd4;
            4'd12: expected_acc = -32'sd2;
            4'd13: expected_acc = -32'sd10;
            4'd14: expected_acc = 32'sd7;
            default: expected_acc = 32'sd1;
        endcase
    endfunction

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        load_a = 1'b0;
        load_b = 1'b0;
        load_bias = 1'b0;
        load_row = '0;
        load_col = '0;
        load_data = '0;
        bias_index = '0;
        bias_data = '0;
        start = 1'b0;
        quant_multiplier = 32'sd3;
        quant_shift = 6'd2;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Small diagonal-style input: the raw result equals the expected bias test.
        write_matrix(1'b1, 0, 0, 8'sd1);
        write_matrix(1'b1, 0, 1, 8'sd2);
        write_matrix(1'b1, 0, 2, 8'sd3);
        write_matrix(1'b1, 0, 3, 8'sd4);
        write_matrix(1'b1, 1, 0, 8'sd5);
        write_matrix(1'b1, 1, 1, 8'sd6);
        write_matrix(1'b1, 1, 2, 8'sd7);
        write_matrix(1'b1, 1, 3, 8'sd8);
        write_matrix(1'b1, 2, 0, -8'sd1);
        write_matrix(1'b1, 2, 1, 8'sd2);
        write_matrix(1'b1, 2, 2, -8'sd3);
        write_matrix(1'b1, 2, 3, 8'sd4);
        write_matrix(1'b1, 3, 0, 8'sd2);
        write_matrix(1'b1, 3, 1, 8'sd0);
        write_matrix(1'b1, 3, 2, 8'sd1);
        write_matrix(1'b1, 3, 3, -8'sd2);

        write_matrix(1'b0, 0, 0, 8'sd1);
        write_matrix(1'b0, 0, 1, 8'sd0);
        write_matrix(1'b0, 0, 2, 8'sd2);
        write_matrix(1'b0, 0, 3, -8'sd1);
        write_matrix(1'b0, 1, 0, 8'sd3);
        write_matrix(1'b0, 1, 1, 8'sd1);
        write_matrix(1'b0, 1, 2, 8'sd0);
        write_matrix(1'b0, 1, 3, 8'sd2);
        write_matrix(1'b0, 2, 0, 8'sd0);
        write_matrix(1'b0, 2, 1, -8'sd2);
        write_matrix(1'b0, 2, 2, 8'sd1);
        write_matrix(1'b0, 2, 3, 8'sd3);
        write_matrix(1'b0, 3, 0, 8'sd2);
        write_matrix(1'b0, 3, 1, 8'sd4);
        write_matrix(1'b0, 3, 2, -8'sd1);
        write_matrix(1'b0, 3, 3, 8'sd0);

        // Biases create ReLU, saturation, and a 40 * 3 >>> 2 = 30 case.
        for (int index = 0; index < 16; index = index + 1)
            write_bias(index[3:0], (index == 10) ? -32'sd20 : 32'sd0);
        write_bias(4'd0, 32'sd1000);
        write_bias(4'd14, 32'sd33);

        @(negedge clk);
        start = 1'b1;
        @(posedge clk);
        #1 start = 1'b0;

        wait (result_valid);
        for (int index = 0; index < 16; index = index + 1) begin
            #1;
            if (result_accumulator !== expected_acc(index[3:0]))
                $fatal(1, "ACC FAILED at %0d", index);
            if (result_index !== index[3:0])
                $fatal(1, "INDEX FAILED: expected %0d received %0d", index, result_index);
            if (result_row !== index[3:2])
                $fatal(1, "ROW FAILED at %0d: expected %0d received %0d", index,
                       index[3:2], result_row);
            if (result_col !== index[1:0])
                $fatal(1, "COLUMN FAILED at %0d: expected %0d received %0d", index,
                       index[1:0], result_col);
            if ((index == 10) || (index == 11) || (index == 12) || (index == 13)) begin
                if (result_data !== 8'sd0)
                    $fatal(1, "RELU FAILED: expected 0, received %0d", $signed(result_data));
            end else if (index == 0) begin
                if (result_data !== 8'sd127)
                    $fatal(1, "SATURATION FAILED at %0d", index);
            end else if (index == 14) begin
                if (result_data !== 8'sd30)
                    $fatal(1, "QUANTIZATION FAILED: expected 30, received %0d",
                           $signed(result_data));
            end else if (index == 1) begin
                if (result_data !== 8'sd99)
                    $fatal(1, "QUANTIZATION FAILED at %0d: expected 99, received %0d",
                           index, $signed(result_data));
            end else if (index == 2) begin
                if (result_data !== 8'sd0)
                    $fatal(1, "QUANTIZATION FAILED at %0d: expected 0, received %0d",
                           index, $signed(result_data));
            end else if (index == 3) begin
                if (result_data !== 8'sd9)
                    $fatal(1, "QUANTIZATION FAILED at %0d: expected 9, received %0d",
                           index, $signed(result_data));
            end else if (index == 4) begin
                if (result_data !== 8'sd29)
                    $fatal(1, "QUANTIZATION FAILED at %0d: expected 29, received %0d",
                           index, $signed(result_data));
            end else if (index == 5) begin
                if (result_data !== 8'sd18)
                    $fatal(1, "QUANTIZATION FAILED at %0d: expected 18, received %0d",
                           index, $signed(result_data));
            end else if (index == 6) begin
                if (result_data !== 8'sd6)
                    $fatal(1, "QUANTIZATION FAILED at %0d: expected 6, received %0d",
                           index, $signed(result_data));
            end else if (index == 7) begin
                if (result_data !== 8'sd21)
                    $fatal(1, "QUANTIZATION FAILED at %0d: expected 21, received %0d",
                           index, $signed(result_data));
            end else if (index == 8) begin
                if (result_data !== 8'sd9)
                    $fatal(1, "QUANTIZATION FAILED at %0d: expected 9, received %0d",
                           index, $signed(result_data));
            end else if (index == 9) begin
                if (result_data !== 8'sd18)
                    $fatal(1, "QUANTIZATION FAILED at %0d: expected 18, received %0d",
                           index, $signed(result_data));
            end else if (index == 15) begin
                if (result_data !== 8'sd0)
                    $fatal(1, "QUANTIZATION FAILED at %0d: expected 0, received %0d",
                           index, $signed(result_data));
            end
            @(posedge clk);
        end

        wait (done);
        $display("POSTPROCESSING TEST PASSED: bias, ReLU, quantization, saturation");
        $finish;
    end

endmodule
