/* 
   Source   : vending/vending-bdd-control-abs.v
   Synopsis : Control-path over-approximation for BDD proving
*/

`define SERVICE_OFF     2'b00
`define SERVICE_ON      2'b01
`define SERVICE_BUSY    2'b10

module vendingControlAbs(
   // Property Output Ports (bad-state monitors)
   p_state_encoding,
   p_off_requires_none,
   p_off_next_on,
   // General I/O Ports
   clk,
   reset,
   // Abstract environment inputs
   reqValid,
   canPay,
   canChange,
   forceIn
);

output p_state_encoding;
output p_off_requires_none;
output p_off_next_on;
input  clk;
input  reset;
input  reqValid;
input  canPay;
input  canChange;
input  forceIn;

reg [1:0] serviceTypeOut;
reg       itemNone;
reg       exchangeReady;
reg       initialized;

reg [1:0] nextServiceType;

always @(*) begin
   nextServiceType = serviceTypeOut;
   case (serviceTypeOut)
      `SERVICE_ON: begin
         if (reqValid) nextServiceType = `SERVICE_BUSY;
      end
      `SERVICE_OFF: begin
         nextServiceType = `SERVICE_ON;
      end
      default: begin
         if (exchangeReady) begin
            nextServiceType = `SERVICE_OFF;
         end
      end
   endcase
end

always @(posedge clk) begin
   if (!reset) begin
      serviceTypeOut <= `SERVICE_ON;
      itemNone       <= 1'b1;
      exchangeReady  <= 1'b0;
      initialized    <= 1'b1;
   end else if (initialized) begin
      case (serviceTypeOut)
         `SERVICE_ON: begin
            if (reqValid) begin
               serviceTypeOut <= `SERVICE_BUSY;
               itemNone       <= 1'b0;
               exchangeReady  <= 1'b0;
            end
         end
         `SERVICE_OFF: begin
            serviceTypeOut <= `SERVICE_ON;
            itemNone       <= 1'b1;
         end
         default: begin
            if (!exchangeReady) begin
               if (canPay) begin
                  exchangeReady <= 1'b1;
               end else if (!forceIn) begin
                  exchangeReady <= 1'b1;
                  itemNone      <= 1'b1;
               end
            end else begin
               if (canChange) begin
                  serviceTypeOut <= `SERVICE_OFF;
               end else begin
                  // Over-approximation keeps the bug-compatible fallback:
                  // no change and return to OFF with no item.
                  itemNone       <= 1'b1;
                  serviceTypeOut <= `SERVICE_OFF;
               end
            end
         end
      endcase
   end
end

assign p_state_encoding    = initialized && (serviceTypeOut == 2'b11);
assign p_off_requires_none = initialized && (serviceTypeOut == `SERVICE_OFF) && !itemNone;
assign p_off_next_on       = initialized && (serviceTypeOut == `SERVICE_OFF) &&
                             (nextServiceType != `SERVICE_ON);

endmodule
