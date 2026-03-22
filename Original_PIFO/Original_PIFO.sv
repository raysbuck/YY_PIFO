/*-----------------------------------------------------------------------------
Module: Original_PIFO.sv
Description: Highly optimized register-shift PIFO (Push-In First-Out).
             Uses carry-chain friendly logic for priority encoding to scale 
             performance for large N (up to 4096).
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
    logic [N-1:0]          v_reg;
    logic [N-1:0][RW-1:0]  r_reg;
    logic [N-1:0][MW-1:0]  m_reg;

    // --- 1. Priority Logic (Carry-Chain Friendly) ---
    // cmp[i] is true if the new element could potentially be inserted at or before i
    logic [N-1:0] cmp;
    always_comb begin
        for (int i = 0; i < N; i++) begin
            cmp[i] = (!v_reg[i] || (i_push_rank < r_reg[i]));
        end
    end

    // Standard carry-chain priority encoder logic
    logic [N-1:0] cmp_minus_1;
    assign cmp_minus_1 = cmp - 1'b1;

    // insert_mask has exactly one bit set at the insertion position k
    logic [N-1:0] insert_mask;
    assign insert_mask = i_push ? (cmp & ~cmp_minus_1) : '0;

    // mask_thru_k[i] is true if k <= i.
    logic [N-1:0] mask_thru_k;
    assign mask_thru_k = cmp | cmp_minus_1;
    
    // k_gt_i[i] is true if k > i
    logic [N-1:0] k_gt_i;
    assign k_gt_i = ~mask_thru_k;

    // k_lt_i[i] is true if k < i
    logic [N-1:0] k_lt_i;
    assign k_lt_i = mask_thru_k & ~insert_mask;

    // --- 2. Next State Logic ---
    logic [N-1:0]          v_next;
    logic [N-1:0][RW-1:0]  r_next;
    logic [N-1:0][MW-1:0]  m_next;

    always_comb begin
        v_next = v_reg;
        r_next = r_reg;
        m_next = m_reg;

        for (int i = 0; i < N; i++) begin
            if (i_push && !i_pop) begin
                if (insert_mask[i]) begin
                    v_next[i] = 1'b1;
                    r_next[i] = i_push_rank;
                    m_next[i] = i_push_metadata;
                end else if (k_lt_i[i]) begin
                    v_next[i] = v_reg[i-1];
                    r_next[i] = r_reg[i-1];
                    m_next[i] = m_reg[i-1];
                end
                // else: k > i, stay
            end 
            else if (!i_push && i_pop) begin
                if (i < N - 1) begin
                    v_next[i] = v_reg[i+1];
                    r_next[i] = r_reg[i+1];
                    m_next[i] = m_reg[i+1];
                end else begin
                    v_next[i] = 1'b0;
                    r_next[i] = '0;
                    m_next[i] = '0;
                end
            end
            else if (i_push && i_pop) begin
                if (i < N - 1 && k_gt_i[i+1]) begin
                    v_next[i] = v_reg[i+1];
                    r_next[i] = r_reg[i+1];
                    m_next[i] = m_reg[i+1];
                end else if (i < N - 1 && insert_mask[i+1]) begin
                    v_next[i] = 1'b1;
                    r_next[i] = i_push_rank;
                    m_next[i] = i_push_metadata;
                end else if (insert_mask[i] && i == 0) begin
                    v_next[i] = 1'b1;
                    r_next[i] = i_push_rank;
                    m_next[i] = i_push_metadata;
                end else begin
                    v_next[i] = v_reg[i];
                    r_next[i] = r_reg[i];
                    m_next[i] = m_reg[i];
                end
            end
        end
    end

    // Sequential
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

    // --- 3. Status Logic ---
    logic [$clog2(N+1)-1:0] count_reg;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) count_reg <= '0;
        else begin
            if (i_push && !i_pop && !o_full)  count_reg <= count_reg + 1'b1;
            else if (!i_push && i_pop && !o_empty) count_reg <= count_reg - 1'b1;
        end
    end

    assign o_count = count_reg;
    assign o_empty = !v_reg[0];
    assign o_full  = v_reg[N-1];

    assign o_pop_valid    = v_reg[0];
    assign o_pop_rank     = r_reg[0];
    assign o_pop_metadata = m_reg[0];

endmodule
