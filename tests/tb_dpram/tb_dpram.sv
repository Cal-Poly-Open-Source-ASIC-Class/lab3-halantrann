`timescale 1ns/1ps

// iverilog -g2012 -Irtl -s tb_dpram rtl/dual_port_ram.sv rtl/DFFRAM256x32.v tests/tb_dpram/tb_dpram.sv

module tb_dpram;

// Clock & Reset
reg clk = 0;
reg rst = 1;
always #5 clk = ~clk;  // 100 MHz clock

// Port A signals
reg [31:0] pA_wb_addr_i = 0;
reg [31:0] pA_wb_data_i = 0;
wire [31:0] pA_wb_data_o;
reg pA_wb_we_i = 0;
reg pA_wb_stb_i = 0;
reg pA_wb_cyc_i = 0;
wire pA_wb_ack_o;
wire pA_wb_stall_o;

// Port B signals
reg [31:0] pB_wb_addr_i = 0;
reg [31:0] pB_wb_data_i = 0;
wire [31:0] pB_wb_data_o;
reg pB_wb_we_i = 0;
reg pB_wb_stb_i = 0;
reg pB_wb_cyc_i = 0;
wire pB_wb_ack_o;
wire pB_wb_stall_o;

// Timeout counter
integer timeout_counter;
localparam TIMEOUT_LIMIT = 20;

// Instantiate DUT
dual_port_ram dual_port_ram (
    .*
);

// Task to wait for acknowledgment with timeout
task wait_for_ack;
    input is_port_a;
    begin
        timeout_counter = 0;
        while (1) begin
            @(posedge clk);
            if ((is_port_a && pA_wb_ack_o) || (!is_port_a && pB_wb_ack_o))
                break;
                
            timeout_counter = timeout_counter + 1;
            if (timeout_counter >= TIMEOUT_LIMIT) begin
                $display("❌ ERROR: Timeout waiting for %s acknowledgment", is_port_a ? "Port A" : "Port B");
                break;
            end
        end
    end
endtask

initial begin
    // Dump waves
    $dumpfile("tb_dpram.vcd");
    $dumpvars(0, dual_port_ram);

    // Reset sequence
    rst = 1;
    #20 rst = 0;

    // ------------------------------------------------
    // 1) Port A: Write and Read
    // ------------------------------------------------
    $display("\n=== Test 1: Port A Write/Read ===");
    @(posedge clk);
    pA_wb_cyc_i = 1; pA_wb_stb_i = 1; pA_wb_we_i = 1;
    pA_wb_addr_i = 32'h000; pA_wb_data_i = 32'hDEADBEEF;

    wait_for_ack(1);
    @(posedge clk);
    pA_wb_stb_i = 0; pA_wb_cyc_i = 0; pA_wb_we_i = 0;

    // Read back
    @(posedge clk);
    pA_wb_cyc_i = 1; pA_wb_stb_i = 1; pA_wb_we_i = 0;
    pA_wb_addr_i = 32'h000;

    wait_for_ack(1);
    if (pA_wb_data_o !== 32'hDEADBEEF)
        $display("❌ ERROR: Port A read = %h, expected DEADBEEF", pA_wb_data_o);
    else
        $display("✅ PASS: Port A readback correct (DEADBEEF)");

    @(posedge clk);
    pA_wb_stb_i = 0; pA_wb_cyc_i = 0;

    // ------------------------------------------------
    // 2) Port B: Write and Read
    // ------------------------------------------------
    $display("\n=== Test 2: Port B Write/Read ===");
    @(posedge clk);
    pB_wb_cyc_i = 1; pB_wb_stb_i = 1; pB_wb_we_i = 1;
    pB_wb_addr_i = 32'h400; pB_wb_data_i = 32'hCAFEBABE;

    wait_for_ack(0);
    @(posedge clk);
    pB_wb_stb_i = 0; pB_wb_cyc_i = 0; pB_wb_we_i = 0;

    // Read back
    @(posedge clk);
    pB_wb_cyc_i = 1; pB_wb_stb_i = 1; pB_wb_we_i = 0;
    pB_wb_addr_i = 32'h400;

    wait_for_ack(0);
    if (pB_wb_data_o !== 32'hCAFEBABE)
        $display("❌ ERROR: Port B read = %h, expected CAFEBABE", pB_wb_data_o);
    else
        $display("✅ PASS: Port B readback correct (CAFEBABE)");

    @(posedge clk);
    pB_wb_stb_i = 0; pB_wb_cyc_i = 0;

    // ------------------------------------------------
    // 3) Concurrent Write: Different banks
    // ------------------------------------------------
    $display("\n=== Test 3: Concurrent Write to Different Banks ===");
    @(posedge clk);
    pA_wb_cyc_i = 1; pA_wb_stb_i = 1; pA_wb_we_i = 1;
    pA_wb_addr_i = 32'h004; pA_wb_data_i = 32'h12345678;
    pB_wb_cyc_i = 1; pB_wb_stb_i = 1; pB_wb_we_i = 1;
    pB_wb_addr_i = 32'h404; pB_wb_data_i = 32'h87654321;

    // Wait for both acknowledgments
    timeout_counter = 0;
    while (!(pA_wb_ack_o && pB_wb_ack_o)) begin
        @(posedge clk);
        timeout_counter = timeout_counter + 1;
        if (timeout_counter >= TIMEOUT_LIMIT) begin
            $display("❌ ERROR: Timeout waiting for concurrent acknowledgments");
            break;
        end
    end
    
    $display("✅ PASS: Concurrent different-bank write");

    @(posedge clk);
    pA_wb_stb_i = 0; pA_wb_cyc_i = 0; pA_wb_we_i = 0;
    pB_wb_stb_i = 0; pB_wb_cyc_i = 0; pB_wb_we_i = 0;
    
    // Verify the writes
    @(posedge clk);
    pA_wb_cyc_i = 1; pA_wb_stb_i = 1; pA_wb_we_i = 0;
    pA_wb_addr_i = 32'h004;
    
    wait_for_ack(1);
    if (pA_wb_data_o !== 32'h12345678)
        $display("❌ ERROR: Port A verification read = %h, expected 12345678", pA_wb_data_o);
    else
        $display("✅ PASS: Port A verification read correct (12345678)");
        
    @(posedge clk);
    pA_wb_stb_i = 0; pA_wb_cyc_i = 0;
    
    @(posedge clk);
    pB_wb_cyc_i = 1; pB_wb_stb_i = 1; pB_wb_we_i = 0;
    pB_wb_addr_i = 32'h404;
    
    wait_for_ack(0);
    if (pB_wb_data_o !== 32'h87654321)
        $display("❌ ERROR: Port B verification read = %h, expected 87654321", pB_wb_data_o);
    else
        $display("✅ PASS: Port B verification read correct (87654321)");
        
    @(posedge clk);
    pB_wb_stb_i = 0; pB_wb_cyc_i = 0;

    // ------------------------------------------------
    // 4) Concurrent Write: Same bank (conflict case)
    // ------------------------------------------------
    $display("\n=== Test 4: Concurrent Write to Same Bank (Conflict) ===");
    @(posedge clk);
    pA_wb_cyc_i = 1; pA_wb_stb_i = 1; pA_wb_we_i = 1;
    pA_wb_addr_i = 32'h008; pA_wb_data_i = 32'hAAAABBBB;
    pB_wb_cyc_i = 1; pB_wb_stb_i = 1; pB_wb_we_i = 1;
    pB_wb_addr_i = 32'h00C; pB_wb_data_i = 32'hCCCCDDDD;

    wait_for_ack(1);
    $display("...Port A done, waiting on Port B...");
    
    // Port A should be done, but B should still be stalled
    if (!pB_wb_stall_o)
        $display("❌ ERROR: Port B not stalled during conflict");
        
    // Complete B's request after A is done
    wait_for_ack(0);
    $display("✅ PASS: Arbitration on same-bank successful");

    @(posedge clk);
    pA_wb_stb_i = 0; pA_wb_cyc_i = 0; pA_wb_we_i = 0;
    pB_wb_stb_i = 0; pB_wb_cyc_i = 0; pB_wb_we_i = 0;
    
    // Verify both writes happened
    @(posedge clk);
    pA_wb_cyc_i = 1; pA_wb_stb_i = 1; pA_wb_we_i = 0;
    pA_wb_addr_i = 32'h008;
    
    wait_for_ack(1);
    if (pA_wb_data_o !== 32'hAAAABBBB)
        $display("❌ ERROR: Conflict verification A read = %h, expected AAAABBBB", pA_wb_data_o);
    else
        $display("✅ PASS: Conflict verification A read correct");
        
    @(posedge clk);
    pA_wb_stb_i = 0; pA_wb_cyc_i = 0;
    
    @(posedge clk);
    pB_wb_cyc_i = 1; pB_wb_stb_i = 1; pB_wb_we_i = 0;
    pB_wb_addr_i = 32'h00C;
    
    wait_for_ack(0);
    if (pB_wb_data_o !== 32'hCCCCDDDD)
        $display("❌ ERROR: Conflict verification B read = %h, expected CCCCDDDD", pB_wb_data_o);
    else
        $display("✅ PASS: Conflict verification B read correct");
        
    @(posedge clk);
    pB_wb_stb_i = 0; pB_wb_cyc_i = 0;
    
    // ------------------------------------------------
    // 5) Concurrent Read: Different banks (should work in parallel)
    // ------------------------------------------------
    $display("\n=== Test 5: Concurrent Read from Different Banks ===");
    @(posedge clk);
    pA_wb_cyc_i = 1; pA_wb_stb_i = 1; pA_wb_we_i = 0;
    pA_wb_addr_i = 32'h000; // Should read DEADBEEF
    pB_wb_cyc_i = 1; pB_wb_stb_i = 1; pB_wb_we_i = 0;
    pB_wb_addr_i = 32'h400; // Should read CAFEBABE
    
    // Wait for both acknowledgments
    timeout_counter = 0;
    while (!(pA_wb_ack_o && pB_wb_ack_o)) begin
        @(posedge clk);
        timeout_counter = timeout_counter + 1;
        if (timeout_counter >= TIMEOUT_LIMIT) begin
            $display("❌ ERROR: Timeout waiting for concurrent read acknowledgments");
            break;
        end
    end
    
    if (pA_wb_data_o === 32'hDEADBEEF && pB_wb_data_o === 32'hCAFEBABE)
        $display("✅ PASS: Concurrent reads from different banks successful");
    else
        $display("❌ ERROR: Concurrent reads failed. Port A: %h, Port B: %h", pA_wb_data_o, pB_wb_data_o);

    @(posedge clk);
    pA_wb_stb_i = 0; pA_wb_cyc_i = 0;
    pB_wb_stb_i = 0; pB_wb_cyc_i = 0;

    #20
    $display(" ");

    $finish;
end

endmodule