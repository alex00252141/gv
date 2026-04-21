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

endmodule
