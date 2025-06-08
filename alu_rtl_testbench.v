`include "alu_rtl_design.v"
`include "define.v"

// Testbench for ALU design verification
module test_bench_alu #(parameter W = 8, parameter N = 4)();

  // Packet width calculations for stimulus and response handling
  localparam TESTCASE_WIDTH = 8 + 2 + 2*W + N + 1 + 1 + 1 + 2*W + 1 + 3 + 1 + 1;
  localparam RESPONSE_WIDTH = TESTCASE_WIDTH + 1 + 1 + 3 + 1 + 2*W + 1;
  localparam RESULT_WIDTH = 2*W + 1 + 3 + 1 + 1;  // RES + COUT + EGL + OVF + ERR

  // Test stimulus and response storage
  reg [TESTCASE_WIDTH-1:0] curr_test_case = 0;
  reg [TESTCASE_WIDTH-1:0] stimulus_mem [0:`no_of_testcase-1];
  reg [RESPONSE_WIDTH-1:0] response_packet;

  integer j;

  // Clock and control signals
  reg CLK, REST, CE;
  event fetch_stimulus;

  // Test inputs
  reg [W-1:0] OPA, OPB;
  reg [N-1:0] CMD;
  reg MODE, CIN;
  reg [7:0] Feature_ID;
  reg [2:0] Comparison_EGL;
  reg [2*W-1:0] Expected_RES;
  reg err, cout, ov;
  reg [1:0] INP_VALID;

  // DUT outputs
  wire [2*W-1:0] RES;
  wire ERR, OFLOW, COUT;
  wire [2:0] EGL;
  wire [RESULT_WIDTH - 1:0] expected_data;
  reg [RESULT_WIDTH - 1:0] exact_data;

  // DUT instantiation
  alu_design #(.W(W), .N(N)) inst_dut (
    .OPA(OPA), .OPB(OPB), .CIN(CIN), .clock(CLK), .CMD(CMD), .CE(CE), .MODE(MODE),
    .COUT(COUT), .OV(OFLOW), .RES(RES), .G(EGL[1]), .E(EGL[2]), .L(EGL[0]), 
    .ERR(ERR), .reset(REST), .INP_valid(INP_VALID)
  );

  integer stim_mem_ptr = 0;

  // Load test stimulus from file
  task read_stimulus(); begin
    #10 $readmemb("stimulus.txt", stimulus_mem);
  end endtask

  // Fetch next test case from stimulus memory
  always @(fetch_stimulus) begin
    curr_test_case = stimulus_mem[stim_mem_ptr];
    $display("----------------------------------------------------");
    $display("");
    $display ("Stimulus data = %0b", stimulus_mem[stim_mem_ptr]);
    stim_mem_ptr = stim_mem_ptr + 1;
  end

  // Clock generation - 120ns period
  initial begin CLK = 0; forever #60 CLK = ~CLK; end

  // Drive test inputs to DUT
  task automatic driver();
    integer idx = TESTCASE_WIDTH - 1;
    begin
      ->fetch_stimulus;
      repeat(2) @(posedge CLK);

      // Unpack test case bits into individual signals
      Feature_ID = curr_test_case[idx -: 8]; idx = idx - 8;
      INP_VALID = curr_test_case[idx -: 2]; idx = idx - 2;
      OPA = curr_test_case[idx -: W]; idx = idx - W;
      OPB = curr_test_case[idx -: W]; idx = idx - W;
      CMD = curr_test_case[idx -: N]; idx = idx - N;
      CIN = curr_test_case[idx]; idx = idx - 1;
      CE = curr_test_case[idx]; idx = idx - 1;
      MODE = curr_test_case[idx]; idx = idx - 1;
      Expected_RES = curr_test_case[idx -: 2*W]; idx = idx - (2*W);
      cout = curr_test_case[idx]; idx = idx - 1;
      Comparison_EGL = curr_test_case[idx -: 3]; idx = idx - 3;
      ov = curr_test_case[idx]; idx = idx - 1;
      err = curr_test_case[idx];

      $display("Driving: Feature_ID=%0d| OPA=%d| OPB=%d| CMD=%0d",Feature_ID, OPA, OPB, CMD);
    end
  endtask

  // Reset DUT to known state
  task dut_reset(); begin
    CE = 1;
    #10 REST = 1;
    #20 REST = 0;
  end endtask

  // Monitor DUT outputs and capture response
  task monitor(); begin
    repeat(6) @(posedge CLK);
    #5 begin
      response_packet[TESTCASE_WIDTH-1:0] = curr_test_case;
      response_packet[TESTCASE_WIDTH +: 7] = {ERR, OFLOW, EGL, COUT};
      response_packet[TESTCASE_WIDTH+7 +: 2*W] = RES;
      exact_data = {RES, COUT, EGL, OFLOW, ERR};

      $display("Monitor: RES=%d| COUT=%0b| EGL=%0b| OFLOW=%0b| ERR=%0b",
               RES, COUT, EGL, OFLOW, ERR);
    end
  end endtask

  // Pack expected results for comparison
  assign expected_data = {Expected_RES, cout, Comparison_EGL, ov, err};

  // Compare expected vs actual results
  task score_board();
    begin
      #5;
      $display("Expected result = %0b | DUT_RESULT = %0b", expected_data, exact_data);
      if(expected_data === exact_data) begin
        $display("Test PASSED");
      end
      else begin
        $display("Test FAILED");
      end
    end
  endtask

  // Main test sequence
  initial begin
    #10;
    $display("\n--- Starting ALU Verification ---");
    dut_reset();
    read_stimulus();
    
    // Execute all test cases
    for(j = 0; j <= `no_of_testcase-1; j = j + 1) begin
      fork
        driver();
        monitor();
      join
      score_board();
    end
   

    #100 $display("\n--- Verification Complete ---");
    $finish();
  end
endmodule
