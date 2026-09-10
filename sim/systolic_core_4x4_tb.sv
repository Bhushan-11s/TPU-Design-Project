`timescale 1ns/1ps

module systolic_core_4x4_tb;

    logic clk;
    logic rst_n;
    logic load_a;
    logic load_b;
    logic [1:0] load_row;
    logic [1:0] load_col;
    logic signed [7:0] load_data;
    logic start;

    logic busy;
    logic done;
    logic result_valid;
    logic [3:0] result_index;
    logic [1:0] result_row;
    logic [1:0] result_col;
    logic signed [31:0] result_data;

    systolic_core_4x4 dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .load_a       (load_a),
        .load_b       (load_b),
        .load_row     (load_row),
        .load_col     (load_col),
        .load_data    (load_data),
        .start        (start),
        .busy         (busy),
        .done         (done),
        .result_valid (result_valid),
        .result_index (result_index),
        .result_row   (result_row),
        .result_col   (result_col),
        .result_data  (result_data)
    );

    always #5 clk = ~clk;

    task automatic write_a(
        input logic [1:0] row,
        input logic [1:0] col,
        input logic signed [7:0] value
    );
        begin
            @(negedge clk);
            load_a = 1'b1;
            load_b = 1'b0;
            load_row = row;
            load_col = col;
            load_data = value;
            @(posedge clk);
            #1 load_a = 1'b0;
        end
    endtask

    task automatic write_b(
        input logic [1:0] row,
        input logic [1:0] col,
        input logic signed [7:0] value
    );
        begin
            @(negedge clk);
            load_a = 1'b0;
            load_b = 1'b1;
            load_row = row;
            load_col = col;
            load_data = value;
            @(posedge clk);
            #1 load_b = 1'b0;
        end
    endtask

    function automatic logic signed [31:0] expected(input logic [3:0] index);
        case (index)
            4'd0: expected = 32'sd15;
            4'd1: expected = 32'sd12;
            4'd2: expected = 32'sd1;
            4'd3: expected = 32'sd12;
            4'd4: expected = 32'sd39;
            4'd5: expected = 32'sd24;
            4'd6: expected = 32'sd9;
            4'd7: expected = 32'sd28;
            4'd8: expected = 32'sd13;
            4'd9: expected = 32'sd24;
            4'd10: expected = -32'sd9;
            4'd11: expected = -32'sd4;
            4'd12: expected = -32'sd2;
            4'd13: expected = -32'sd10;
            4'd14: expected = 32'sd7;
            default: expected = 32'sd1;
        endcase
    endfunction

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        load_a = 1'b0;
        load_b = 1'b0;
        load_row = '0;
        load_col = '0;
        load_data = '0;
        start = 1'b0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // A = [ 1  2  3  4; 5  6  7  8; -1  2 -3  4; 2  0  1 -2 ]
        write_a(0, 0, 8'sd1);
        write_a(0, 1, 8'sd2);
        write_a(0, 2, 8'sd3);
        write_a(0, 3, 8'sd4);
        write_a(1, 0, 8'sd5);
        write_a(1, 1, 8'sd6);
        write_a(1, 2, 8'sd7);
        write_a(1, 3, 8'sd8);
        write_a(2, 0, -8'sd1);
        write_a(2, 1, 8'sd2);
        write_a(2, 2, -8'sd3);
        write_a(2, 3, 8'sd4);
        write_a(3, 0, 8'sd2);
        write_a(3, 1, 8'sd0);
        write_a(3, 2, 8'sd1);
        write_a(3, 3, -8'sd2);

        // B = [ 1 0 2 -1; 3 1 0 2; 0 -2 1 3; 2 4 -1 0 ]
        write_b(0, 0, 8'sd1);
        write_b(0, 1, 8'sd0);
        write_b(0, 2, 8'sd2);
        write_b(0, 3, -8'sd1);
        write_b(1, 0, 8'sd3);
        write_b(1, 1, 8'sd1);
        write_b(1, 2, 8'sd0);
        write_b(1, 3, 8'sd2);
        write_b(2, 0, 8'sd0);
        write_b(2, 1, -8'sd2);
        write_b(2, 2, 8'sd1);
        write_b(2, 3, 8'sd3);
        write_b(3, 0, 8'sd2);
        write_b(3, 1, 8'sd4);
        write_b(3, 2, -8'sd1);
        write_b(3, 3, 8'sd0);

        @(negedge clk);
        start = 1'b1;
        @(posedge clk);
        #1 start = 1'b0;

        wait (result_valid);
        for (int index = 0; index < 16; index = index + 1) begin
            #1;
            if (result_index !== index[3:0])
                $fatal(1, "INDEX FAILED: expected %0d received %0d", index, result_index);
            if (result_data !== expected(index[3:0]))
                $fatal(1, "RESULT FAILED at %0d: expected %0d received %0d", index,
                       expected(index[3:0]), $signed(result_data));
            @(posedge clk);
        end

        wait (done);
        if (busy)
            $fatal(1, "BUSY remained asserted after completion");

        $display("TILE TEST PASSED: all 16 results match A x B");
        $finish;
    end

endmodule
