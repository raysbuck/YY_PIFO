`timescale 1ns / 1ps

module tb_Original_PIFO;

    parameter int N  = 8;
    parameter int RW = 16;
    parameter int MW = 32;

    logic          clk;
    logic          rst_n;

    logic          i_push;
    logic [RW-1:0] i_push_rank;
    logic [MW-1:0] i_push_metadata;

    logic          i_pop;
    logic          o_pop_valid;
    logic [RW-1:0] o_pop_rank;
    logic [MW-1:0] o_pop_metadata;

    logic          o_full;
    logic          o_empty;
    logic [$clog2(N+1)-1:0] o_count;

    // Instantiate DUT
    Original_PIFO #(
        .N(N),
        .RW(RW),
        .MW(MW)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_push(i_push),
        .i_push_rank(i_push_rank),
        .i_push_metadata(i_push_metadata),
        .i_pop(i_pop),
        .o_pop_valid(o_pop_valid),
        .o_pop_rank(o_pop_rank),
        .o_pop_metadata(o_pop_metadata),
        .o_full(o_full),
        .o_empty(o_empty),
        .o_count(o_count)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test sequence
    initial begin
        // Reset
        rst_n = 0;
        i_push = 0;
        i_push_rank = 0;
        i_push_metadata = 0;
        i_pop = 0;
        #20;
        rst_n = 1;
        #10;

        // Push some values
        push(10, 32'hA);
        push(5,  32'hB);
        push(20, 32'hC);
        push(15, 32'hD);
        
        // At this point, sorted should be: 5, 10, 15, 20
        #10;
        $display("Count: %0d (Expected: 4)", o_count);

        // Pop one
        pop(); // Should get rank 5
        #10;
        
        // Push another
        push(7, 32'hE); // Sorted should be: 7, 10, 15, 20
        #10;

        // Simultaneous Push and Pop
        // Pop 7, Push 12
        i_pop = 1;
        i_push = 1;
        i_push_rank = 12;
        i_push_metadata = 32'hF;
        #10;
        i_pop = 0;
        i_push = 0;
        // Sorted should be: 10, 12, 15, 20
        #10;

        // Empty the PIFO
        while (!o_empty) begin
            pop();
            #10;
        end

        $finish;
    end

    task push(input [RW-1:0] rank, input [MW-1:0] meta);
        begin
            i_push = 1;
            i_push_rank = rank;
            i_push_metadata = meta;
            #10;
            i_push = 0;
            $display("Pushed rank %0d", rank);
        end
    endtask

    task pop();
        begin
            i_pop = 1;
            #10;
            i_pop = 0;
            if (o_pop_valid)
                $display("Popped rank %0d, metadata %h", o_pop_rank, o_pop_metadata);
            else
                $display("Pop failed: PIFO empty");
        end
    endtask

    // Monitor
    initial begin
        $monitor("Time=%0t Count=%0d Full=%b Empty=%b Head_Rank=%0d", 
                 $time, o_count, o_full, o_empty, o_pop_rank);
    end

endmodule
