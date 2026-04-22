/*
  BDD-friendly abstraction for vending_machine verification.
  Purpose: keep control protocol and value conservation semantics while
  reducing arithmetic/state complexity to avoid BDD blow-up.

  Abstraction choices:
  - only ITEM_NONE / ITEM_A are modeled
  - only NTD_5 and NTD_1 coin types are modeled
  - stored coin capacity is 2-bit saturating (0..3)
*/

`define SERVICE_OFF  2'b00
`define SERVICE_ON   2'b01
`define SERVICE_BUSY 2'b10

module vendingMachineBddAbs (
    input        clk,
    input        reset,
    input  [1:0] coinInNTD_5,
    input  [1:0] coinInNTD_1,
    input        itemTypeIn,      // 0: ITEM_NONE, 1: ITEM_A
    output reg [1:0] coinOutNTD_5,
    output reg [1:0] coinOutNTD_1,
    output reg       itemTypeOut,  // 0: ITEM_NONE, 1: ITEM_A
    output reg [1:0] serviceTypeOut,
    // "bad" monitors for AG(~bad_i) proof
    output           bad_illegal_state,
    output           bad_output_protocol,
    output           bad_count_overflow,
    output           bad_refund_value,
    output           bad_success_value,
    output           bad_conservation
);

    // Stored coins (abstracted capacity 0..3)
    reg [1:0] count5, count1;
    reg [1:0] prevCount5, prevCount1;

    // Captured request context
    reg [1:0] reqCoin5, reqCoin1;
    reg       reqItemType;
    reg [4:0] reqInputValue;

    // Local temporaries
    reg [4:0] changeTarget;
    reg       changeFound;
    reg [1:0] ch5, ch1;

    localparam [4:0] COST_A = 5'd2;

    function [1:0] satAdd2;
        input [1:0] a;
        input [1:0] b;
        reg   [2:0] s;
        begin
            s = {1'b0, a} + {1'b0, b};
            if (s > 3) satAdd2 = 2'd3;
            else       satAdd2 = s[1:0];
        end
    endfunction

    function [4:0] inValue;
        input [1:0] c5;
        input [1:0] c1;
        begin
            inValue = (c5 * 5) + c1;
        end
    endfunction

    function [4:0] outValue;
        input [1:0] c5;
        input [1:0] c1;
        begin
            outValue = (c5 * 5) + c1;
        end
    endfunction

    always @(posedge clk) begin
        if (!reset) begin
            coinOutNTD_5  <= 2'd0;
            coinOutNTD_1  <= 2'd0;
            itemTypeOut   <= 1'b0;
            serviceTypeOut <= `SERVICE_ON;

            count5 <= 2'd1;
            count1 <= 2'd1;

            prevCount5 <= 2'd1;
            prevCount1 <= 2'd1;

            reqCoin5     <= 2'd0;
            reqCoin1     <= 2'd0;
            reqItemType  <= 1'b0;
            reqInputValue <= 5'd0;
        end else begin
            case (serviceTypeOut)
                `SERVICE_ON: begin
                    coinOutNTD_5   <= 2'd0;
                    coinOutNTD_1   <= 2'd0;
                    itemTypeOut    <= 1'b0;
                    serviceTypeOut <= `SERVICE_ON;

                    // Accept request only in SERVICE_ON
                    if (itemTypeIn) begin
                        prevCount5 <= count5;
                        prevCount1 <= count1;

                        reqCoin5      <= coinInNTD_5;
                        reqCoin1      <= coinInNTD_1;
                        reqItemType   <= itemTypeIn;
                        reqInputValue <= inValue(coinInNTD_5, coinInNTD_1);

                        count5 <= satAdd2(count5, coinInNTD_5);
                        count1 <= satAdd2(count1, coinInNTD_1);

                        serviceTypeOut <= `SERVICE_BUSY;
                    end
                end

                `SERVICE_BUSY: begin
                    if (reqInputValue < COST_A) begin
                        // Not enough money => refund and roll back storage.
                        count5 <= prevCount5;
                        count1 <= prevCount1;

                        coinOutNTD_5 <= reqCoin5;
                        coinOutNTD_1 <= reqCoin1;
                        itemTypeOut  <= 1'b0;
                        serviceTypeOut <= `SERVICE_OFF;
                    end else begin
                        changeTarget = reqInputValue - COST_A;
                        changeFound  = 1'b0;
                        ch5          = 2'd0;
                        ch1          = 2'd0;

                        // Try exact change with descending number of 5-dollar coins.
                        if ((changeTarget >= 15) && (count5 >= 3) && ((changeTarget - 15) <= count1)) begin
                            changeFound = 1'b1;
                            ch5 = 2'd3;
                            ch1 = changeTarget - 15;
                        end else if ((changeTarget >= 10) && (count5 >= 2) && ((changeTarget - 10) <= count1)) begin
                            changeFound = 1'b1;
                            ch5 = 2'd2;
                            ch1 = changeTarget - 10;
                        end else if ((changeTarget >= 5) && (count5 >= 1) && ((changeTarget - 5) <= count1)) begin
                            changeFound = 1'b1;
                            ch5 = 2'd1;
                            ch1 = changeTarget - 5;
                        end else if (changeTarget <= count1) begin
                            changeFound = 1'b1;
                            ch5 = 2'd0;
                            ch1 = changeTarget;
                        end

                        if (changeFound) begin
                            count5 <= count5 - ch5;
                            count1 <= count1 - ch1;

                            coinOutNTD_5 <= ch5;
                            coinOutNTD_1 <= ch1;
                            itemTypeOut  <= reqItemType;
                            serviceTypeOut <= `SERVICE_OFF;
                        end else begin
                            // Change not possible => refund and roll back storage.
                            count5 <= prevCount5;
                            count1 <= prevCount1;

                            coinOutNTD_5 <= reqCoin5;
                            coinOutNTD_1 <= reqCoin1;
                            itemTypeOut  <= 1'b0;
                            serviceTypeOut <= `SERVICE_OFF;
                        end
                    end
                end

                default: begin // SERVICE_OFF
                    coinOutNTD_5   <= 2'd0;
                    coinOutNTD_1   <= 2'd0;
                    itemTypeOut    <= 1'b0;
                    serviceTypeOut <= `SERVICE_ON;
                end
            endcase
        end
    end

    wire [4:0] outVal = outValue(coinOutNTD_5, coinOutNTD_1);
    wire [1:0] afterInsert5 = satAdd2(prevCount5, reqCoin5);
    wire [1:0] afterInsert1 = satAdd2(prevCount1, reqCoin1);

    // bad_* monitors (1 means property violation)
    assign bad_illegal_state =
        (serviceTypeOut != `SERVICE_OFF) &&
        (serviceTypeOut != `SERVICE_ON)  &&
        (serviceTypeOut != `SERVICE_BUSY);

    assign bad_output_protocol =
        (serviceTypeOut != `SERVICE_OFF) &&
        ((coinOutNTD_5 != 0) || (coinOutNTD_1 != 0) || (itemTypeOut != 0));

    assign bad_count_overflow = (count5 > 3) || (count1 > 3);

    assign bad_refund_value =
        (serviceTypeOut == `SERVICE_OFF) &&
        (itemTypeOut == 0) &&
        (outVal != reqInputValue);

    assign bad_success_value =
        (serviceTypeOut == `SERVICE_OFF) &&
        (itemTypeOut == 1) &&
        ((outVal + COST_A) != reqInputValue);

    assign bad_conservation =
        (serviceTypeOut == `SERVICE_OFF) &&
        (
            // refund: exact rollback expected
            ((itemTypeOut == 0) &&
             ((count5 != prevCount5) || (count1 != prevCount1))) ||
            // success: (count + output) should equal post-insertion storage
            ((itemTypeOut == 1) &&
             ((count5 + coinOutNTD_5 != afterInsert5) ||
              (count1 + coinOutNTD_1 != afterInsert1)))
        );

endmodule
