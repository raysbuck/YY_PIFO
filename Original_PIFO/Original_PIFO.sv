/*-----------------------------------------------------------------------------
Module: Original_PIFO.sv
Description: A standard register-shift PIFO (Push-In First-Out) implementation.
             Maintains elements sorted by rank. Supporting N elements.
             Provides single-cycle push and pop operations.
-----------------------------------------------------------------------------*/

module Original_PIFO #(
    parameter int N   = 16,    // Capacity (Number of elements)
    parameter int RW  = 16,    // Rank Width
    parameter int MW  = 32     // Metadata Width
)(
    input  logic          clk,
    input  logic          rst_n,

    // Push Interface
    input  logic          i_push,
    input  logic [RW-1:0] i_push_rank,
    input  logic [MW-1:0] i_push_metadata,

    // Pop Interface
    input  logic          i_pop,
    output logic          o_pop_valid,
    output logic [RW-1:0] o_pop_rank,
    output logic [MW-1:0] o_pop_metadata,

    // Status
    output logic          o_full,
    output logic          o_empty,
    output logic [$clog2(N+1)-1:0] o_count
);

    // Storage for PIFO elements
    logic [N-1:0]          v_reg;               // Valid bits
    logic [N-1:0][RW-1:0]  r_reg;               // Rank registers
    logic [N-1:0][MW-1:0]  m_reg;               // Metadata registers

    // Internal wires for the next state
    logic [N-1:0]          v_next;
    logic [N-1:0][RW-1:0]  r_next;
    logic [N-1:0][MW-1:0]  m_next;

    // Find insertion position
    // We want to insert such that the array remains sorted (ascending rank)
    logic [N-1:0] insert_mask;
    always_comb begin
        insert_mask = '0;
        for (int i = 0; i < N; i++) begin
            if (i_push) begin
                // Find the first position where the new rank is smaller than the current rank
                // or the first invalid position.
                if (!v_reg[i] || (i_push_rank < r_reg[i])) begin
                    insert_mask[i] = 1'b1;
                    break;
                end
            end
        end
    end

    // Helper: Determine if a position is the insertion point
    // Since we break in the mask generation, only one bit is set or none.
    
    // Logic for each slot
    always_comb begin
        v_next = v_reg;
        r_next = r_reg;
        m_next = m_reg;

        case ({i_push, i_pop})
            2'b10: begin // Push only
                for (int i = 0; i < N; i++) begin
                    if (insert_mask[i]) begin
                        // Insert here
                        v_next[i] = 1'b1;
                        r_next[i] = i_push_rank;
                        m_next[i] = i_push_metadata;
                        // Shift remaining down
                        for (int j = i + 1; j < N; j++) begin
                            v_next[j] = v_reg[j-1];
                            r_next[j] = r_reg[j-1];
                            m_next[j] = m_reg[j-1];
                        end
                        break;
                    end
                end
            end

            2'b01: begin // Pop only
                // Shift all up
                for (int i = 0; i < N - 1; i++) begin
                    v_next[i] = v_reg[i+1];
                    r_next[i] = r_reg[i+1];
                    m_next[i] = m_reg[i+1];
                end
                v_next[N-1] = 1'b0;
                r_next[N-1] = '0;
                m_next[N-1] = '0;
            end

            2'b11: begin // Push and Pop simultaneously
                // The head (index 0) is popped.
                // Elements from 1 up to the insertion point shift up.
                // The new element is inserted.
                // Elements after the insertion point stay in place.
                
                // Logic:
                // If insert_mask[0] is set, the new element just replaces the popped head.
                // Otherwise, elements [1...pos] shift up to [0...pos-1], and pos becomes the new element.
                
                for (int i = 0; i < N; i++) begin
                    if (insert_mask[i]) begin
                        // Shift elements before i up by 1 (to fill the pop at index 0)
                        for (int j = 0; j < i; j++) begin
                            v_next[j] = v_reg[j+1];
                            r_next[j] = r_reg[j+1];
                            m_next[j] = m_reg[j+1];
                        end
                        // Insert at i-1 if i > 0, or at 0 if i == 0.
                        // Wait, if i is the insertion point in the original array,
                        // and we pop index 0, the new insertion point is i-1.
                        if (i == 0) begin
                            v_next[0] = 1'b1;
                            r_next[0] = i_push_rank;
                            m_next[0] = i_push_metadata;
                        end else begin
                            v_next[i-1] = 1'b1;
                            r_next[i-1] = i_push_rank;
                            m_next[i-1] = i_push_metadata;
                        end
                        // Elements from i onwards stay in their original positions.
                        // (They shifted up due to pop, but shifted down due to push)
                        break;
                    end
                end
            end

            default: ; // No op
        endcase
    end

    // Sequential logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_reg <= '0;
            r_reg <= '0;
            m_reg <= '0;
        end else begin
            v_reg <= v_next;
            r_reg <= r_next;
            m_reg <= m_next;
        end
    end

    // Output assignments
    assign o_pop_valid    = v_reg[0];
    assign o_pop_rank     = r_reg[0];
    assign o_pop_metadata = m_reg[0];

    assign o_empty = !v_reg[0];
    assign o_full  = v_reg[N-1];

    // Count calculation
    logic [$clog2(N+1)-1:0] count;
    always_comb begin
        count = '0;
        for (int i = 0; i < N; i++) begin
            if (v_reg[i]) count = count + 1;
        end
    end
    assign o_count = count;

endmodule
