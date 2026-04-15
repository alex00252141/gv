/* 
   Source   : vending/vending-bdd-money-underapprox.v
   Synopsis : Tiny under-approximation preserving refund-loss bug pattern
*/

`define SERVICE_OFF     2'b00
`define SERVICE_ON      2'b01
`define SERVICE_BUSY    2'b10

module vendingMoneyUnderApprox(
   p_refund_mismatch,
   clk,
   reset,
   req,
   inValue,
   loseRefund
);

output      p_refund_mismatch;
input       clk;
input       reset;
input       req;
input [1:0] inValue;
input       loseRefund;

reg [1:0] serviceTypeOut;
reg       itemNone;
reg       exchangeReady;
reg       initialized;
reg [1:0] inputValue;
reg [1:0] outExchange;

always @(posedge clk) begin
   if (!reset) begin
      serviceTypeOut <= `SERVICE_ON;
      itemNone       <= 1'b1;
      exchangeReady  <= 1'b0;
      initialized    <= 1'b1;
      inputValue     <= 2'd0;
      outExchange    <= 2'd0;
   end else if (initialized) begin
      case (serviceTypeOut)
         `SERVICE_ON: begin
            if (req) begin
               serviceTypeOut <= `SERVICE_BUSY;
               itemNone       <= 1'b0;
               exchangeReady  <= 1'b0;
               inputValue     <= inValue;
               outExchange    <= 2'd0;
            end
         end
         `SERVICE_OFF: begin
            // One-cycle OFF pulse, then return to ON.
            serviceTypeOut <= `SERVICE_ON;
            itemNone       <= 1'b1;
         end
         default: begin
            if (!exchangeReady) begin
               // Under-approximate to refund mode (no item delivered).
               itemNone      <= 1'b1;
               exchangeReady <= 1'b1;
            end else begin
               // Preserve the concrete bug pattern:
               // the machine can switch to OFF while refund != input.
               serviceTypeOut <= `SERVICE_OFF;
               if (loseRefund) outExchange <= 2'd0;
               else outExchange <= inputValue;
            end
         end
      endcase
   end
end

assign p_refund_mismatch = initialized &&
                           (serviceTypeOut == `SERVICE_OFF) &&
                           itemNone &&
                           (outExchange != inputValue);

endmodule
