
`include "define.v"

// Parameterized ALU with arithmetic, logic, and comparison operations
// W: Data width, N: Command width
module alu_design #(parameter W = 8, parameter N = 4) ( 
  clock, reset, CE, INP_valid, MODE, CMD, OPA, OPB, CIN, ERR, RES, OV, COUT, G, L, E);
  
  // Control and data inputs
  input clock;
  input reset;
  input CE;                    // Clock enable
  input [1:0] INP_valid;      // Input validity: 01=OPA, 10=OPB, 11=both
  input MODE;                 // 0=Logic mode, 1=Arithmetic mode
  input [N-1:0] CMD;          // Operation command
  input [W-1:0] OPA;          // Operand A
  input [W-1:0] OPB;          // Operand B
  input CIN;                  // Carry input
  
  // Status and result outputs
  output reg ERR;             // Error flag
  output reg [2*W-1:0] RES;   // Result
  output reg OV;              // Overflow flag
  output reg COUT;            // Carry out
  output reg G;               // Greater than flag
  output reg L;               // Less than flag
  output reg E;               // Equal flag

parameter SHIFT_W = $clog2(W);

// Registered inputs for pipelined operation
reg [W-1:0] opa_r, opb_r;
reg [N-1:0] cmd_r;
reg [1:0] valid_r;
reg mode_r, cin_r;

// Combinational computation signals
reg [2*W - 1:0] res_comb, res_t;
reg cout_comb, ov_comb, g_comb, l_comb, e_comb, err_comb;
reg [SHIFT_W-1:0] shift_amount;

// Input register stage
always @(posedge clock or posedge reset) begin
  if (reset) begin
    opa_r   <= 0;
    opb_r   <= 0;
    cmd_r   <= 0;
    valid_r <= 0;
    mode_r  <= 0;
    cin_r   <= 0;
  end else if (CE) begin
    opa_r   <= OPA;
    opb_r   <= OPB;
    cmd_r   <= CMD;
    valid_r <= INP_valid;
    mode_r  <= MODE;
    cin_r   <= CIN;
  end
end

// Combinational logic for ALU operations
always @(*) begin
  // Initialize all outputs
  res_comb  = 0;
  cout_comb = 0;
  ov_comb   = 0;
  g_comb    = 0;
  l_comb    = 0;
  e_comb    = 0;
  err_comb  = 0;
  res_t     = 0;

  if (mode_r) begin // Arithmetic mode
    case (valid_r)
      2'b01: begin // Single operand A operations
        case (cmd_r)
          `INC_A: begin
            res_comb  = opa_r + 1;
            cout_comb = res_comb[W];
          end
          `DEC_A: begin
            res_comb = opa_r - 1;
            ov_comb  = res_comb[W];
          end
          default: err_comb = 1;
        endcase
      end
      2'b10: begin // Single operand B operations
        case (cmd_r)
          `INC_B: begin
            res_comb  = {{W{1'b0}}, opb_r + 1};
            cout_comb = res_comb[W];
          end
          `DEC_B: begin
            res_comb = {{W{1'b0}}, opb_r - 1};
            ov_comb  = res_comb[W];
          end
          default: err_comb = 1;
        endcase
      end
      2'b11: begin // Dual operand operations
        case (cmd_r)
          `ADD: begin
            res_comb = opa_r + opb_r;
            cout_comb = res_comb[W];
          end
          `SUB: begin
            res_comb = opa_r - opb_r;
            ov_comb = (opa_r < opb_r);
          end
          `ADD_CIN: begin
            res_comb = opa_r + opb_r + cin_r;
            cout_comb = res_comb[W];
          end
          `SUB_CIN: begin
            res_comb = opa_r - opb_r - cin_r;
            ov_comb = (opa_r < (opb_r + cin_r));
          end
          `CMP: begin // Unsigned comparison
            if (opa_r == opb_r) begin
              e_comb = 1;
              g_comb = 0;
              l_comb = 0;
            end
            else if (opa_r > opb_r) begin
              e_comb = 0;
              g_comb = 1;
              l_comb = 0;
            end
            else begin
              e_comb = 0;
              g_comb = 0;
              l_comb = 1;
            end
          end
          `MUL_INC:   res_comb = (opa_r + 1) * (opb_r + 1);
          `MUL_SHIFT: res_comb = (opa_r << 1) * opb_r;
          `SADD: begin // Signed addition with overflow detection
                   res_comb = $signed(opa_r) + $signed(opb_r);
                   ov_comb = (($signed(opa_r) > 0 && $signed(opb_r) > 0 && $signed(res_comb[W-1:0]) <= 0) ||
                             ($signed(opa_r) < 0 && $signed(opb_r) < 0 && $signed(res_comb[W-1:0]) >= 0));

                  // Signed comparison flags
                  if ($signed(opa_r) == $signed(opb_r)) begin
                    e_comb = 1;
                    g_comb = 0;
                    l_comb = 0;
                  end
                  else if ($signed(opa_r) > $signed(opb_r)) begin
                    e_comb = 0;
                    g_comb = 1;
                    l_comb = 0;
                  end
                  else begin
                    e_comb = 0;
                    g_comb = 0;
                    l_comb = 1;
                  end
          end
          `SSUB: begin // Signed subtraction with overflow detection
                   res_comb = $signed(opa_r) - $signed(opb_r);
                   ov_comb = (($signed(opa_r) >= 0 && $signed(opb_r) < 0 && $signed(res_comb[W-1:0]) < 0) ||
                             ($signed(opa_r) < 0 && $signed(opb_r) >= 0 && $signed(res_comb[W-1:0]) >= 0));
                   
                   // Signed comparison flags
                   if ($signed(opa_r) == $signed(opb_r)) begin
                     e_comb = 1;
                     g_comb = 0;
                     l_comb = 0;
                   end
                   else if ($signed(opa_r) > $signed(opb_r)) begin
                     e_comb = 0;
                     g_comb = 1;
                     l_comb = 0;
                   end
                   else begin
                     e_comb = 0;
                     g_comb = 0;
                     l_comb = 1;
                  end
          end
          default: err_comb = 1;
        endcase
      end
      default: err_comb = 1;
    endcase
  end else begin // Logic mode

    case (valid_r)
      2'b01: begin // Single operand A logic operations
        case (cmd_r)
          `NOT_A:   res_comb = {{W{1'b0}}, ~opa_r};
          `SHR1_A:  res_comb = {{W{1'b0}}, opa_r >> 1};
          `SHL1_A:  res_comb = {{W{1'b0}}, opa_r << 1};
          default: err_comb = 1;
        endcase
      end
      2'b10: begin // Single operand B logic operations
        case (cmd_r)
          `NOT_B:   res_comb = {{W{1'b0}}, ~opb_r};
          `SHR1_B:  res_comb = {{W{1'b0}}, opb_r >> 1};
          `SHL1_B:  res_comb = {{W{1'b0}}, opb_r << 1};
          default: err_comb = 1;
        endcase
      end
      2'b11: begin // Dual operand logic operations
        case (cmd_r)
          `AND:   res_comb = {{W{1'b0}}, opa_r & opb_r};
          `NAND:  res_comb = {{W{1'b0}}, ~(opa_r & opb_r)};
          `OR:    res_comb = {{W{1'b0}}, opa_r | opb_r};
          `NOR:   res_comb = {{W{1'b0}}, ~(opa_r | opb_r)};
          `XOR:   res_comb = {{W{1'b0}}, opa_r ^ opb_r};
          `XNOR:  res_comb = {{W{1'b0}}, ~(opa_r ^ opb_r)};
          `ROL_A_B: begin // Rotate left A by B positions
            if (|opb_r[W-1:SHIFT_W+1])  // Check for invalid shift amount
              err_comb = 1;
            else begin
              shift_amount = opb_r[SHIFT_W-1:0];
              res_comb = {{W{1'b0}}, (opa_r << shift_amount) | (opa_r >> (W - shift_amount))};
            end
          end
          `ROR_A_B: begin // Rotate right A by B positions
            if (|opb_r[W-1:SHIFT_W+1])  // Check for invalid shift amount
              err_comb = 1;
            else begin
              shift_amount = opb_r[SHIFT_W-1:0];
              res_comb = {{W{1'b0}}, (opa_r >> shift_amount) | (opa_r << (W - shift_amount))};
            end
          end
          default: err_comb = 1;
        endcase
      end
      default: err_comb = 1;
    endcase
  end
end

// Output register stage
always @(posedge clock or posedge reset) begin
  if (reset) begin
    RES  <= 0;
    COUT <= 0;
    OV   <= 0;
    G    <= 0;
    L    <= 0;
    E    <= 0;
    ERR  <= 0;
  end else if (CE) begin
    // Special handling for multiplication operations (pipeline delay)
    if ((cmd_r == `MUL_SHIFT || cmd_r == `MUL_INC) && mode_r) begin
      res_t <= res_comb;
      RES <= res_t;
    end
    else
      RES <= res_comb;

    COUT <= cout_comb;
    OV   <= ov_comb;
    G    <= g_comb;
    L    <= l_comb;
    E    <= e_comb;
    ERR  <= err_comb;
  end
end

endmodule
