/*
   Source   : vending_ln.v
   Synopsis : Spec-driven vending machine RTL (LN version)
*/

// Service Types
`define SERVICE_OFF     2'b00
`define SERVICE_ON      2'b01
`define SERVICE_BUSY    2'b10

// Item Types
`define ITEM_NONE       2'b00
`define ITEM_A          2'b01
`define ITEM_B          2'b10
`define ITEM_C          2'b11

module vendingMachine(
    input         clk,
    input         reset,
    input  [1:0]  coinInNTD_50,
    input  [1:0]  coinInNTD_10,
    input  [1:0]  coinInNTD_5,
    input  [1:0]  coinInNTD_1,
    input  [1:0]  itemTypeIn,
    output reg [2:0] coinOutNTD_50,
    output reg [2:0] coinOutNTD_10,
    output reg [2:0] coinOutNTD_5,
    output reg [2:0] coinOutNTD_1,
    output reg [1:0] itemTypeOut,
    output reg [1:0] serviceTypeOut
`ifdef VENDING_ASSERT_PO
    ,
    output reg       assertionFail
`endif
);

    reg [2:0] countNTD_50;
    reg [2:0] countNTD_10;
    reg [2:0] countNTD_5;
    reg [2:0] countNTD_1;

    reg [2:0] countNTD_50_prev;
    reg [2:0] countNTD_10_prev;
    reg [2:0] countNTD_5_prev;
    reg [2:0] countNTD_1_prev;

    reg [1:0] reqCoinNTD_50;
    reg [1:0] reqCoinNTD_10;
    reg [1:0] reqCoinNTD_5;
    reg [1:0] reqCoinNTD_1;
    reg [1:0] reqItemType;
    reg [7:0] reqInputValue;

    reg [7:0] serviceCost;
    reg [7:0] changeTarget;
    reg       changeFound;
    reg [2:0] changeNTD_50;
    reg [2:0] changeNTD_10;
    reg [2:0] changeNTD_5;
    reg [2:0] changeNTD_1;

    integer c50;
    integer c10;
    integer c5;
    integer r50;
    integer r10;
    integer r5;

    function [2:0] satAdd3;
        input [2:0] count;
        input [1:0] addend;
        reg [3:0] sum;
        begin
            sum = {1'b0, count} + {2'b00, addend};
            if (sum > 4'd7) satAdd3 = 3'd7;
            else            satAdd3 = sum[2:0];
        end
    endfunction

    function [7:0] itemCost;
        input [1:0] itemType;
        begin
            case (itemType)
                `ITEM_A: itemCost = 8'd8;
                `ITEM_B: itemCost = 8'd15;
                `ITEM_C: itemCost = 8'd22;
                default: itemCost = 8'd0;
            endcase
        end
    endfunction

    function [7:0] coinsValue;
        input [1:0] in50;
        input [1:0] in10;
        input [1:0] in5;
        input [1:0] in1;
        begin
            coinsValue = (in50 * 8'd50) +
                         (in10 * 8'd10) +
                         (in5  * 8'd5 ) +
                         (in1  * 8'd1 );
        end
    endfunction

    always @(posedge clk) begin
        if (!reset) begin
            coinOutNTD_50   <= 3'd0;
            coinOutNTD_10   <= 3'd0;
            coinOutNTD_5    <= 3'd0;
            coinOutNTD_1    <= 3'd0;
            itemTypeOut     <= `ITEM_NONE;
            serviceTypeOut  <= `SERVICE_ON;
`ifdef VENDING_ASSERT_PO
            assertionFail   <= 1'b0;
`endif

            countNTD_50     <= 3'd2;
            countNTD_10     <= 3'd2;
            countNTD_5      <= 3'd2;
            countNTD_1      <= 3'd2;

            countNTD_50_prev <= 3'd2;
            countNTD_10_prev <= 3'd2;
            countNTD_5_prev  <= 3'd2;
            countNTD_1_prev  <= 3'd2;

            reqCoinNTD_50   <= 2'd0;
            reqCoinNTD_10   <= 2'd0;
            reqCoinNTD_5    <= 2'd0;
            reqCoinNTD_1    <= 2'd0;
            reqItemType     <= `ITEM_NONE;
            reqInputValue   <= 8'd0;
        end else begin
            case (serviceTypeOut)
                `SERVICE_ON: begin
                    coinOutNTD_50  <= 3'd0;
                    coinOutNTD_10  <= 3'd0;
                    coinOutNTD_5   <= 3'd0;
                    coinOutNTD_1   <= 3'd0;
                    itemTypeOut    <= `ITEM_NONE;
                    serviceTypeOut <= `SERVICE_ON;

                    if (itemTypeIn != `ITEM_NONE) begin
                        countNTD_50_prev <= countNTD_50;
                        countNTD_10_prev <= countNTD_10;
                        countNTD_5_prev  <= countNTD_5;
                        countNTD_1_prev  <= countNTD_1;

                        reqCoinNTD_50 <= coinInNTD_50;
                        reqCoinNTD_10 <= coinInNTD_10;
                        reqCoinNTD_5  <= coinInNTD_5;
                        reqCoinNTD_1  <= coinInNTD_1;
                        reqItemType   <= itemTypeIn;
                        reqInputValue <= coinsValue(coinInNTD_50, coinInNTD_10, coinInNTD_5, coinInNTD_1);

                        countNTD_50 <= satAdd3(countNTD_50, coinInNTD_50);
                        countNTD_10 <= satAdd3(countNTD_10, coinInNTD_10);
                        countNTD_5  <= satAdd3(countNTD_5, coinInNTD_5);
                        countNTD_1  <= satAdd3(countNTD_1, coinInNTD_1);

                        serviceTypeOut <= `SERVICE_BUSY;
                    end
                end

                `SERVICE_BUSY: begin
                    serviceCost = itemCost(reqItemType);

                    if (reqInputValue < serviceCost) begin
                        countNTD_50 <= countNTD_50_prev;
                        countNTD_10 <= countNTD_10_prev;
                        countNTD_5  <= countNTD_5_prev;
                        countNTD_1  <= countNTD_1_prev;

                        coinOutNTD_50 <= {1'b0, reqCoinNTD_50};
                        coinOutNTD_10 <= {1'b0, reqCoinNTD_10};
                        coinOutNTD_5  <= {1'b0, reqCoinNTD_5};
                        coinOutNTD_1  <= {1'b0, reqCoinNTD_1};
                        itemTypeOut   <= `ITEM_NONE;
                        serviceTypeOut <= `SERVICE_OFF;
                    end else begin
                        changeTarget = reqInputValue - serviceCost;
                        changeFound  = 1'b0;
                        changeNTD_50 = 3'd0;
                        changeNTD_10 = 3'd0;
                        changeNTD_5  = 3'd0;
                        changeNTD_1  = 3'd0;

                        begin : SEARCH_CHANGE
                            for (c50 = 7; c50 >= 0; c50 = c50 - 1) begin
                                if ((c50 <= countNTD_50) && ((c50 * 50) <= changeTarget)) begin
                                    r50 = changeTarget - (c50 * 50);
                                    for (c10 = 7; c10 >= 0; c10 = c10 - 1) begin
                                        if ((c10 <= countNTD_10) && ((c10 * 10) <= r50)) begin
                                            r10 = r50 - (c10 * 10);
                                            for (c5 = 7; c5 >= 0; c5 = c5 - 1) begin
                                                if ((c5 <= countNTD_5) && ((c5 * 5) <= r10)) begin
                                                    r5 = r10 - (c5 * 5);
                                                    if (r5 <= countNTD_1) begin
                                                        changeFound  = 1'b1;
                                                        changeNTD_50 = c50[2:0];
                                                        changeNTD_10 = c10[2:0];
                                                        changeNTD_5  = c5[2:0];
                                                        changeNTD_1  = r5[2:0];
                                                        disable SEARCH_CHANGE;
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end

                        if (changeFound) begin
                            countNTD_50 <= countNTD_50 - changeNTD_50;
                            countNTD_10 <= countNTD_10 - changeNTD_10;
                            countNTD_5  <= countNTD_5 - changeNTD_5;
                            countNTD_1  <= countNTD_1 - changeNTD_1;

                            coinOutNTD_50 <= changeNTD_50;
                            coinOutNTD_10 <= changeNTD_10;
                            coinOutNTD_5  <= changeNTD_5;
                            coinOutNTD_1  <= changeNTD_1;
                            itemTypeOut   <= reqItemType;
                            serviceTypeOut <= `SERVICE_OFF;
                        end else begin
                            countNTD_50 <= countNTD_50_prev;
                            countNTD_10 <= countNTD_10_prev;
                            countNTD_5  <= countNTD_5_prev;
                            countNTD_1  <= countNTD_1_prev;

                            coinOutNTD_50 <= {1'b0, reqCoinNTD_50};
                            coinOutNTD_10 <= {1'b0, reqCoinNTD_10};
                            coinOutNTD_5  <= {1'b0, reqCoinNTD_5};
                            coinOutNTD_1  <= {1'b0, reqCoinNTD_1};
                            itemTypeOut   <= `ITEM_NONE;
                            serviceTypeOut <= `SERVICE_OFF;
                        end
                    end
                end

                default: begin  // SERVICE_OFF
                    coinOutNTD_50  <= 3'd0;
                    coinOutNTD_10  <= 3'd0;
                    coinOutNTD_5   <= 3'd0;
                    coinOutNTD_1   <= 3'd0;
                    itemTypeOut    <= `ITEM_NONE;
                    serviceTypeOut <= `SERVICE_ON;
                end
            endcase
        end
    end

`ifndef SYNTHESIS
`define VENDING_ASSERT(cond, msg)                                                    \
    if ((cond) !== 1'b1) begin                                                       \
`ifdef VENDING_ASSERT_PO                                                              \
        assertionFail = 1'b1;                                                         \
`endif                                                                                \
        $display("ASSERT_FAIL %s time=%0t", msg, $time);                             \
`ifndef VENDING_ASSERT_NO_FATAL                                                       \
        $fatal(1);                                                                    \
`endif                                                                                \
    end

    reg       a_seen_reset;
    reg       a_prev_valid;
    reg       a_prev_reset;
    reg [1:0] a_prev_service;
    reg [1:0] a_prev_item_in;
    reg [1:0] a_prev_coin50;
    reg [1:0] a_prev_coin10;
    reg [1:0] a_prev_coin5;
    reg [1:0] a_prev_coin1;
    reg [2:0] a_prev_count50;
    reg [2:0] a_prev_count10;
    reg [2:0] a_prev_count5;
    reg [2:0] a_prev_count1;

    integer outValue;

    initial begin
        a_seen_reset  = 1'b0;
        a_prev_valid  = 1'b0;
        a_prev_reset  = 1'b1;
        a_prev_service = `SERVICE_ON;
        a_prev_item_in = `ITEM_NONE;
        a_prev_coin50  = 2'd0;
        a_prev_coin10  = 2'd0;
        a_prev_coin5   = 2'd0;
        a_prev_coin1   = 2'd0;
        a_prev_count50 = 3'd2;
        a_prev_count10 = 3'd2;
        a_prev_count5  = 3'd2;
        a_prev_count1  = 3'd2;
    end

    always @(negedge clk) begin
        if (!reset) a_seen_reset = 1'b1;

        if (a_seen_reset) begin
            // Basic legal encoding checks.
            `VENDING_ASSERT((serviceTypeOut == `SERVICE_OFF) ||
                            (serviceTypeOut == `SERVICE_ON)  ||
                            (serviceTypeOut == `SERVICE_BUSY),
                            "illegal serviceTypeOut encoding")
            `VENDING_ASSERT((itemTypeOut == `ITEM_NONE) ||
                            (itemTypeOut == `ITEM_A)    ||
                            (itemTypeOut == `ITEM_B)    ||
                            (itemTypeOut == `ITEM_C),
                            "illegal itemTypeOut encoding")

            // Stored coin count is 3-bit capacity [0..7].
            `VENDING_ASSERT(countNTD_50 <= 3'd7, "countNTD_50 out of range")
            `VENDING_ASSERT(countNTD_10 <= 3'd7, "countNTD_10 out of range")
            `VENDING_ASSERT(countNTD_5  <= 3'd7, "countNTD_5 out of range")
            `VENDING_ASSERT(countNTD_1  <= 3'd7, "countNTD_1 out of range")
            `VENDING_ASSERT(!$isunknown({serviceTypeOut, itemTypeOut,
                                         coinOutNTD_50, coinOutNTD_10, coinOutNTD_5, coinOutNTD_1,
                                         countNTD_50, countNTD_10, countNTD_5, countNTD_1,
                                         reqCoinNTD_50, reqCoinNTD_10, reqCoinNTD_5, reqCoinNTD_1,
                                         reqItemType, reqInputValue}),
                            "unknown (X/Z) observed on critical state/output signals")

            // Reset values.
            if (!reset) begin
                `VENDING_ASSERT(serviceTypeOut == `SERVICE_ON, "reset serviceTypeOut mismatch")
                `VENDING_ASSERT(itemTypeOut == `ITEM_NONE, "reset itemTypeOut mismatch")
                `VENDING_ASSERT((coinOutNTD_50 == 3'd0) && (coinOutNTD_10 == 3'd0) &&
                                (coinOutNTD_5 == 3'd0)  && (coinOutNTD_1 == 3'd0),
                                "reset coinOut mismatch")
                `VENDING_ASSERT((countNTD_50 == 3'd2) && (countNTD_10 == 3'd2) &&
                                (countNTD_5 == 3'd2)  && (countNTD_1 == 3'd2),
                                "reset stored-count mismatch")
            end

            // Transition protocol checks (based on previous sampled cycle).
            if (a_prev_valid && a_prev_reset) begin
                if (a_prev_service == `SERVICE_ON) begin
                    if (a_prev_item_in == `ITEM_NONE) begin
                        `VENDING_ASSERT(serviceTypeOut == `SERVICE_ON,
                                        "SERVICE_ON + no-request should stay SERVICE_ON")
                        `VENDING_ASSERT((countNTD_50 == a_prev_count50) &&
                                        (countNTD_10 == a_prev_count10) &&
                                        (countNTD_5  == a_prev_count5 ) &&
                                        (countNTD_1  == a_prev_count1 ),
                                        "no-request cycle should not change stored counts")
                    end else begin
                        `VENDING_ASSERT(serviceTypeOut == `SERVICE_BUSY,
                                        "SERVICE_ON + request should go SERVICE_BUSY")
                        `VENDING_ASSERT(reqItemType == a_prev_item_in,
                                        "captured request item mismatch")
                        `VENDING_ASSERT((reqCoinNTD_50 == a_prev_coin50) &&
                                        (reqCoinNTD_10 == a_prev_coin10) &&
                                        (reqCoinNTD_5  == a_prev_coin5 ) &&
                                        (reqCoinNTD_1  == a_prev_coin1 ),
                                        "captured request coin vector mismatch")
                        `VENDING_ASSERT(reqInputValue == coinsValue(a_prev_coin50, a_prev_coin10,
                                                                    a_prev_coin5, a_prev_coin1),
                                        "captured request value mismatch")
                        `VENDING_ASSERT((countNTD_50_prev == a_prev_count50) &&
                                        (countNTD_10_prev == a_prev_count10) &&
                                        (countNTD_5_prev  == a_prev_count5 ) &&
                                        (countNTD_1_prev  == a_prev_count1 ),
                                        "previous-count snapshot mismatch")
                        `VENDING_ASSERT((countNTD_50 == satAdd3(a_prev_count50, a_prev_coin50)) &&
                                        (countNTD_10 == satAdd3(a_prev_count10, a_prev_coin10)) &&
                                        (countNTD_5  == satAdd3(a_prev_count5,  a_prev_coin5 )) &&
                                        (countNTD_1  == satAdd3(a_prev_count1,  a_prev_coin1 )),
                                        "post-acceptance stored count update mismatch")
                    end
                end
                if (a_prev_service == `SERVICE_BUSY)
                    `VENDING_ASSERT(serviceTypeOut == `SERVICE_OFF,
                                    "SERVICE_BUSY should transition to SERVICE_OFF")
                if (a_prev_service == `SERVICE_OFF)
                    `VENDING_ASSERT(serviceTypeOut == `SERVICE_ON,
                                    "SERVICE_OFF should transition to SERVICE_ON")
            end

            // During SERVICE_BUSY, output should not yet be visible.
            if (serviceTypeOut == `SERVICE_BUSY) begin
                `VENDING_ASSERT((coinOutNTD_50 == 3'd0) && (coinOutNTD_10 == 3'd0) &&
                                (coinOutNTD_5 == 3'd0)  && (coinOutNTD_1 == 3'd0),
                                "coin outputs should be zero during SERVICE_BUSY")
                `VENDING_ASSERT(itemTypeOut == `ITEM_NONE,
                                "item output should be ITEM_NONE during SERVICE_BUSY")
            end
            if (serviceTypeOut == `SERVICE_ON) begin
                `VENDING_ASSERT((coinOutNTD_50 == 3'd0) && (coinOutNTD_10 == 3'd0) &&
                                (coinOutNTD_5 == 3'd0)  && (coinOutNTD_1 == 3'd0),
                                "coin outputs should be zero during SERVICE_ON")
                `VENDING_ASSERT(itemTypeOut == `ITEM_NONE,
                                "item output should be ITEM_NONE during SERVICE_ON")
            end

            // Transaction-level value conservation on output cycle.
            if (serviceTypeOut == `SERVICE_OFF) begin
                outValue = (coinOutNTD_50 * 50) + (coinOutNTD_10 * 10) +
                           (coinOutNTD_5 * 5) + coinOutNTD_1;
                if (itemTypeOut == `ITEM_NONE) begin
                    `VENDING_ASSERT(outValue == reqInputValue,
                                    "refund value mismatch (itemTypeOut=ITEM_NONE)")
                    `VENDING_ASSERT((coinOutNTD_50 == {1'b0, reqCoinNTD_50}) &&
                                    (coinOutNTD_10 == {1'b0, reqCoinNTD_10}) &&
                                    (coinOutNTD_5  == {1'b0, reqCoinNTD_5 }) &&
                                    (coinOutNTD_1  == {1'b0, reqCoinNTD_1 }),
                                    "refund denomination mismatch")
                    `VENDING_ASSERT((countNTD_50 == countNTD_50_prev) &&
                                    (countNTD_10 == countNTD_10_prev) &&
                                    (countNTD_5  == countNTD_5_prev ) &&
                                    (countNTD_1  == countNTD_1_prev ),
                                    "refund should restore previous stored counts")
                end else begin
                    `VENDING_ASSERT(itemTypeOut == reqItemType,
                                    "successful output item must match requested item")
                    `VENDING_ASSERT(outValue + itemCost(itemTypeOut) == reqInputValue,
                                    "item + change value mismatch")
                    `VENDING_ASSERT((countNTD_50 + coinOutNTD_50 ==
                                     satAdd3(countNTD_50_prev, reqCoinNTD_50)) &&
                                    (countNTD_10 + coinOutNTD_10 ==
                                     satAdd3(countNTD_10_prev, reqCoinNTD_10)) &&
                                    (countNTD_5  + coinOutNTD_5  ==
                                     satAdd3(countNTD_5_prev,  reqCoinNTD_5 )) &&
                                    (countNTD_1  + coinOutNTD_1  ==
                                     satAdd3(countNTD_1_prev,  reqCoinNTD_1 )),
                                    "successful vend denomination conservation mismatch")
                end
            end
        end

        a_prev_valid   = 1'b1;
        a_prev_reset   = reset;
        a_prev_service = serviceTypeOut;
        a_prev_item_in = itemTypeIn;
        a_prev_coin50  = coinInNTD_50;
        a_prev_coin10  = coinInNTD_10;
        a_prev_coin5   = coinInNTD_5;
        a_prev_coin1   = coinInNTD_1;
        a_prev_count50 = countNTD_50;
        a_prev_count10 = countNTD_10;
        a_prev_count5  = countNTD_5;
        a_prev_count1  = countNTD_1;
    end

`undef VENDING_ASSERT
`endif

endmodule
