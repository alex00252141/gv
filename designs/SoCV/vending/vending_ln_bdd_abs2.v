/*
  BDD abstraction v2 for vending-machine proof.

  Goals:
  - Keep the core control protocol (ON -> BUSY -> OFF -> ON).
  - Keep "never eat money" style value conservation checks.
  - Aggressively reduce state-space to make BDD proof tractable.

  Abstraction:
  - Single request bit (reqValid), single item type (cost = 1 token).
  - Single coin bucket with 2-bit token count (0..3), saturating storage.
*/

`define SERVICE_OFF  2'b00
`define SERVICE_ON   2'b01
`define SERVICE_BUSY 2'b10

module vendingMachineBddAbs2 (
    input        clk,
    input        reset,
    input        reqValid,
    input  [1:0] coinIn,
    // bad-state monitors for AG(~bad*)
    output           bad_state_encoding,
    output           bad_output_protocol,
    output           bad_refund_value,
    output           bad_success_value,
    output           bad_storage_conservation,
    // regular functional outputs
    output reg [1:0] coinOut,
    output reg       itemOut,         // 0: none, 1: item delivered
    output reg [1:0] serviceTypeOut
);

    reg [1:0] storedCoins;
    reg [1:0] prevStoredCoins;
    reg [1:0] reqCoins;

    reg [1:0] changeTarget;
    reg       changeFeasible;
    reg [1:0] changeOut;

    localparam [1:0] COST_ITEM = 2'd1;

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

    always @(posedge clk) begin
        if (!reset) begin
            coinOut        <= 2'd0;
            itemOut        <= 1'b0;
            serviceTypeOut <= `SERVICE_ON;

            storedCoins    <= 2'd1;
            prevStoredCoins <= 2'd1;
            reqCoins       <= 2'd0;
        end else begin
            case (serviceTypeOut)
                `SERVICE_ON: begin
                    coinOut        <= 2'd0;
                    itemOut        <= 1'b0;
                    serviceTypeOut <= `SERVICE_ON;

                    if (reqValid) begin
                        prevStoredCoins <= storedCoins;
                        reqCoins        <= coinIn;
                        storedCoins     <= satAdd2(storedCoins, coinIn);
                        serviceTypeOut  <= `SERVICE_BUSY;
                    end
                end

                `SERVICE_BUSY: begin
                    if (reqCoins < COST_ITEM) begin
                        // Too few coins: refund and rollback.
                        storedCoins     <= prevStoredCoins;
                        coinOut         <= reqCoins;
                        itemOut         <= 1'b0;
                        serviceTypeOut  <= `SERVICE_OFF;
                    end else begin
                        changeTarget = reqCoins - COST_ITEM;
                        // Feasible iff enough stored coins after insertion.
                        if (storedCoins >= changeTarget) begin
                            changeFeasible = 1'b1;
                            changeOut      = changeTarget;
                        end else begin
                            changeFeasible = 1'b0;
                            changeOut      = 2'd0;
                        end

                        if (changeFeasible) begin
                            storedCoins     <= storedCoins - changeOut;
                            coinOut         <= changeOut;
                            itemOut         <= 1'b1;
                            serviceTypeOut  <= `SERVICE_OFF;
                        end else begin
                            // Cannot make change: refund and rollback.
                            storedCoins     <= prevStoredCoins;
                            coinOut         <= reqCoins;
                            itemOut         <= 1'b0;
                            serviceTypeOut  <= `SERVICE_OFF;
                        end
                    end
                end

                default: begin // SERVICE_OFF
                    coinOut        <= 2'd0;
                    itemOut        <= 1'b0;
                    serviceTypeOut <= `SERVICE_ON;
                end
            endcase
        end
    end

    wire [1:0] postInsertCoins = satAdd2(prevStoredCoins, reqCoins);

    assign bad_state_encoding =
        (serviceTypeOut != `SERVICE_OFF) &&
        (serviceTypeOut != `SERVICE_ON)  &&
        (serviceTypeOut != `SERVICE_BUSY);

    assign bad_output_protocol =
        (serviceTypeOut != `SERVICE_OFF) &&
        ((coinOut != 2'd0) || itemOut);

    // Refund branch must return exactly what was inserted.
    assign bad_refund_value =
        (serviceTypeOut == `SERVICE_OFF) &&
        (!itemOut) &&
        (coinOut != reqCoins);

    // Success branch must satisfy item+change = input.
    assign bad_success_value =
        (serviceTypeOut == `SERVICE_OFF) &&
        itemOut &&
        ((coinOut + COST_ITEM) != reqCoins);

    // Inventory conservation:
    // refund: storage rollback; success: storage + change = post-insertion storage.
    assign bad_storage_conservation =
        (serviceTypeOut == `SERVICE_OFF) &&
        (
            ((!itemOut) && (storedCoins != prevStoredCoins)) ||
            (itemOut && ((storedCoins + coinOut) != postInsertCoins))
        );

endmodule
