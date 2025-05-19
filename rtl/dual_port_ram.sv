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

    // Extract address bits outside always_comb for Icarus compatibility
    wire [7:0] pA_mem_addr = pA_wb_addr_i[9:2];
    wire [7:0] pB_mem_addr = pB_wb_addr_i[9:2];

    // Memory selection based on address - bit 10 determines bank
    wire pA_mem_sel = pA_wb_addr_i[10];
    wire pB_mem_sel = pB_wb_addr_i[10];

    // Conflict detection - both ports accessing the same memory bank
    wire conflict = (pA_mem_sel == pB_mem_sel) && pA_wb_stb_i && pB_wb_stb_i && pA_wb_cyc_i && pB_wb_cyc_i;
    
    // Port A always wins arbitration on conflict
    wire pA_granted = pA_wb_stb_i && pA_wb_cyc_i;
    wire pB_granted = pB_wb_stb_i && pB_wb_cyc_i && (!conflict);

    // Port B pending transaction
    logic pB_pending;
    logic [31:0] pB_pending_addr;
    logic [31:0] pB_pending_data;
    logic pB_pending_we;
    logic pB_pending_mem_sel;
    wire [7:0] pB_pending_addr_short = pB_pending_addr[9:2];

    // Memory control signals
    logic [31:0] mem0_data_in, mem1_data_in;
    logic [31:0] mem0_data_out, mem1_data_out;
    logic [7:0]  mem0_addr, mem1_addr;
    logic [3:0]  mem0_we, mem1_we;
    logic        mem0_en, mem1_en;

    // Tracking for proper acknowledgment
    logic pA_active;
    logic pB_active;
    logic pB_pending_active;

    // Stall signals
    assign pA_wb_stall_o = 1'b0;
    assign pB_wb_stall_o = conflict;

    // Memory access control logic
    always_comb begin
        mem0_en = 1'b0;
        mem1_en = 1'b0;
        mem0_we = 4'b0000;
        mem1_we = 4'b0000;
        mem0_addr = 8'd0;
        mem1_addr = 8'd0;
        mem0_data_in = 32'd0;
        mem1_data_in = 32'd0;
        pA_active = 1'b0;
        pB_active = 1'b0;
        pB_pending_active = 1'b0;

        // Port A
        if (pA_granted) begin
            pA_active = 1'b1;
            if (pA_mem_sel == 1'b0) begin
                mem0_en = 1'b1;
                mem0_addr = pA_mem_addr;
                mem0_data_in = pA_wb_data_i;
                if (pA_wb_we_i) mem0_we = 4'b1111;
            end else begin
                mem1_en = 1'b1;
                mem1_addr = pA_mem_addr;
                mem1_data_in = pA_wb_data_i;
                if (pA_wb_we_i) mem1_we = 4'b1111;
            end
        end

        // Port B
        if (pB_granted) begin
            pB_active = 1'b1;
            if (pB_mem_sel == 1'b0) begin
                mem0_en = 1'b1;
                mem0_addr = pB_mem_addr;
                mem0_data_in = pB_wb_data_i;
                if (pB_wb_we_i) mem0_we = 4'b1111;
            end else begin
                mem1_en = 1'b1;
                mem1_addr = pB_mem_addr;
                mem1_data_in = pB_wb_data_i;
                if (pB_wb_we_i) mem1_we = 4'b1111;
            end
        end
        // Pending B
        else if (pB_pending) begin
            pB_pending_active = 1'b1;
            if (pB_pending_mem_sel == 1'b0) begin
                mem0_en = 1'b1;
                mem0_addr = pB_pending_addr_short;
                mem0_data_in = pB_pending_data;
                if (pB_pending_we) mem0_we = 4'b1111;
            end else begin
                mem1_en = 1'b1;
                mem1_addr = pB_pending_addr_short;
                mem1_data_in = pB_pending_data;
                if (pB_pending_we) mem1_we = 4'b1111;
            end
        end
    end

    // Sequential logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pA_wb_ack_o <= 1'b0;
            pB_wb_ack_o <= 1'b0;
            pB_pending <= 1'b0;
            pB_pending_addr <= 32'd0;
            pB_pending_data <= 32'd0;
            pB_pending_we <= 1'b0;
            pB_pending_mem_sel <= 1'b0;
        end else begin
            pA_wb_ack_o <= pA_active;

            if (pB_active) begin
                pB_wb_ack_o <= 1'b1;
            end else if (pB_pending_active) begin
                pB_wb_ack_o <= 1'b1;
                pB_pending <= 1'b0;
            end else begin
                pB_wb_ack_o <= 1'b0;
            end

            if (conflict && pB_wb_stb_i && pB_wb_cyc_i) begin
                pB_pending <= 1'b1;
                pB_pending_addr <= pB_wb_addr_i;
                pB_pending_data <= pB_wb_data_i;
                pB_pending_we <= pB_wb_we_i;
                pB_pending_mem_sel <= pB_mem_sel;
            end
        end
    end

    // Data outputs
    assign pA_wb_data_o = pA_mem_sel ? mem1_data_out : mem0_data_out;
    assign pB_wb_data_o = pB_pending_active ? 
                          (pB_pending_mem_sel ? mem1_data_out : mem0_data_out) : 
                          (pB_mem_sel ? mem1_data_out : mem0_data_out);

    // Memory modules
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
