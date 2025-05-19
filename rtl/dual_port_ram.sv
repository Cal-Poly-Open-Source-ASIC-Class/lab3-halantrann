`timescale 1ns/1ps

module dual_port_ram(
    input logic clk,
    input logic rst,

    // PORT A
    input logic [31:0] pA_wb_addr_i,
    input logic [31:0] pA_wb_data_i,
    input logic pA_wb_we_i,
    input logic pA_wb_stb_i,
    input logic pA_wb_cyc_i,
    output logic [31:0] pA_wb_data_o,
    output logic pA_wb_stall_o,
    output logic pA_wb_ack_o,

    // PORT B
    input logic [31:0] pB_wb_addr_i,
    input logic [31:0] pB_wb_data_i,
    input logic pB_wb_we_i,
    input logic pB_wb_stb_i,
    input logic pB_wb_cyc_i,
    output logic [31:0] pB_wb_data_o,
    output logic pB_wb_stall_o,
    output logic pB_wb_ack_o
);

    // Memory selection based on address - bit 10 determines bank
    wire pA_mem_sel = pA_wb_addr_i[10];
    wire pB_mem_sel = pB_wb_addr_i[10];

    // Conflict detection - both ports accessing the same memory bank
    wire conflict = (pA_mem_sel == pB_mem_sel) && pA_wb_stb_i && pB_wb_stb_i && pA_wb_cyc_i && pB_wb_cyc_i;
    
    // Port A always wins arbitration on conflict
    wire pA_granted = pA_wb_stb_i && pA_wb_cyc_i;
    wire pB_granted = pB_wb_stb_i && pB_wb_cyc_i && (!conflict);

    // Port B pending transaction (saved on conflict)
    logic pB_pending;
    logic [31:0] pB_pending_addr;
    logic [31:0] pB_pending_data;
    logic pB_pending_we;
    logic pB_pending_mem_sel;

    // Memory control signals
    logic [31:0] mem0_data_in, mem1_data_in;
    logic [31:0] mem0_data_out, mem1_data_out;
    logic [7:0]  mem0_addr, mem1_addr;
    logic [3:0]  mem0_we, mem1_we;
    logic        mem0_en, mem1_en;

    // Request tracking for proper acknowledgment
    logic pA_req_r, pB_req_r;
    logic pA_active_r, pB_active_r;
    logic [31:0] pA_data_r, pB_data_r;
    
    // Memory access control
    always_comb begin
        // Default values
        mem0_en = 1'b0;
        mem1_en = 1'b0;
        mem0_we = 4'b0000;
        mem1_we = 4'b0000;
        mem0_addr = 8'd0;
        mem1_addr = 8'd0;
        mem0_data_in = 32'd0;
        mem1_data_in = 32'd0;

        // Port A access
        if (pA_granted) begin
            if (!pA_mem_sel) begin
                // Access to memory bank 0
                mem0_en = 1'b1;
                mem0_addr = pA_wb_addr_i[9:2];
                mem0_data_in = pA_wb_data_i;
                if (pA_wb_we_i) mem0_we = 4'b1111;
            end else begin
                // Access to memory bank 1
                mem1_en = 1'b1;
                mem1_addr = pA_wb_addr_i[9:2];
                mem1_data_in = pA_wb_data_i;
                if (pA_wb_we_i) mem1_we = 4'b1111;
            end
        end

        // Port B access (only if no conflict)
        if (pB_granted) begin
            if (!pB_mem_sel) begin
                // Access to memory bank 0
                mem0_en = 1'b1;
                mem0_addr = pB_wb_addr_i[9:2];
                mem0_data_in = pB_wb_data_i;
                if (pB_wb_we_i) mem0_we = 4'b1111;
            end else begin
                // Access to memory bank 1
                mem1_en = 1'b1;
                mem1_addr = pB_wb_addr_i[9:2];
                mem1_data_in = pB_wb_data_i;
                if (pB_wb_we_i) mem1_we = 4'b1111;
            end
        end
        
        // Handle pending Port B transaction (when Port A is not active)
        else if (pB_pending && !pA_wb_stb_i) begin
            if (!pB_pending_mem_sel) begin
                // Access to memory bank 0
                mem0_en = 1'b1;
                mem0_addr = pB_pending_addr[9:2];
                mem0_data_in = pB_pending_data;
                if (pB_pending_we) mem0_we = 4'b1111;
            end else begin
                // Access to memory bank 1
                mem1_en = 1'b1;
                mem1_addr = pB_pending_addr[9:2];
                mem1_data_in = pB_pending_data;
                if (pB_pending_we) mem1_we = 4'b1111;
            end
        end
    end

    // Sequential logic for port control and acknowledgment
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pA_wb_stall_o <= 1'b0;
            pB_wb_stall_o <= 1'b0;
            pA_wb_ack_o <= 1'b0;
            pB_wb_ack_o <= 1'b0;
            pA_req_r <= 1'b0;
            pB_req_r <= 1'b0;
            pA_active_r <= 1'b0;
            pB_active_r <= 1'b0;
            pA_data_r <= 32'd0;
            pB_data_r <= 32'd0;
            pB_pending <= 1'b0;
            pB_pending_addr <= 32'd0;
            pB_pending_data <= 32'd0;
            pB_pending_we <= 1'b0;
            pB_pending_mem_sel <= 1'b0;
        end else begin
            // Track new requests
            pA_req_r <= pA_wb_stb_i && pA_wb_cyc_i;
            pB_req_r <= pB_wb_stb_i && pB_wb_cyc_i;
            
            // Set active signals for granted requests
            pA_active_r <= pA_granted;
            
            // Port B can be active either due to direct grant or handling a pending transaction
            pB_active_r <= pB_granted || (pB_pending && !pA_wb_stb_i);
            
            // Generate acknowledgments one cycle after request is granted
            pA_wb_ack_o <= pA_active_r;
            
            // Port B gets acknowledged when actively granted or when a pending transaction completes
            if (pB_active_r && !pB_pending) begin
                // Normal operation - direct grant
                pB_wb_ack_o <= 1'b1;
            end else if (pB_active_r && pB_pending) begin
                // Completing a pending transaction
                pB_wb_ack_o <= 1'b1;
                pB_pending <= 1'b0; // Clear pending flag
            end else begin
                pB_wb_ack_o <= 1'b0;
            end
            
            // Save the Port B transaction when there's a conflict
            if (conflict && pB_wb_stb_i && pB_wb_cyc_i && !pB_pending) begin
                pB_pending <= 1'b1;
                pB_pending_addr <= pB_wb_addr_i;
                pB_pending_data <= pB_wb_data_i;
                pB_pending_we <= pB_wb_we_i;
                pB_pending_mem_sel <= pB_mem_sel;
            end
            
            // Set stall signals
            pA_wb_stall_o <= 1'b0; // Port A given priority 
            
            // Port B stalls on conflict or when it has a pending transaction
            pB_wb_stall_o <= conflict || pB_pending;
            
            // Capture read data for proper output timing
            if (pA_active_r) begin
                if (!pA_mem_sel)
                    pA_data_r <= mem0_data_out;
                else
                    pA_data_r <= mem1_data_out;
            end
            
            if (pB_active_r) begin
                if (pB_pending) begin
                    // Reading from the appropriate bank for a pending transaction
                    if (!pB_pending_mem_sel)
                        pB_data_r <= mem0_data_out;
                    else
                        pB_data_r <= mem1_data_out;
                end else 
                    // Normal operation
                    if (!pB_mem_sel)
                        pB_data_r <= mem0_data_out;
                    else
                        pB_data_r <= mem1_data_out;
            end
        end
    end
    
    // Data output assignment
    assign pA_wb_data_o = pA_data_r;
    assign pB_wb_data_o = pB_data_r;

    // RAM Instantiations
    DFFRAM256x32 mem0 (
        .CLK(clk),
        .EN0(mem0_en),
        .WE0(mem0_we),
        .A0(mem0_addr),
        .Di0(mem0_data_in),
        .Do0(mem0_data_out)
    );

    DFFRAM256x32 mem1 (
        .CLK(clk),
        .EN0(mem1_en),
        .WE0(mem1_we),
        .A0(mem1_addr),
        .Di0(mem1_data_in),
        .Do0(mem1_data_out)
    );

endmodule