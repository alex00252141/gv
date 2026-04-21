`timescale 1ns/1ps

module vending_ln_tb;
    reg clk;
    reg reset;
    reg [1:0] coinInNTD_50;
    reg [1:0] coinInNTD_10;
    reg [1:0] coinInNTD_5;
    reg [1:0] coinInNTD_1;
    reg [1:0] itemTypeIn;

    wire [2:0] coinOutNTD_50;
    wire [2:0] coinOutNTD_10;
    wire [2:0] coinOutNTD_5;
    wire [2:0] coinOutNTD_1;
    wire [1:0] itemTypeOut;
    wire [1:0] serviceTypeOut;

    integer in_fd;
    integer out_fd;
    integer rc;
    integer cycle;
    integer stim_reset;
    integer stim_coin50;
    integer stim_coin10;
    integer stim_coin5;
    integer stim_coin1;
    integer stim_item;

    reg [1023:0] stim_path;
    reg [1023:0] out_path;

    vendingMachine dut (
        .clk(clk),
        .reset(reset),
        .coinInNTD_50(coinInNTD_50),
        .coinInNTD_10(coinInNTD_10),
        .coinInNTD_5(coinInNTD_5),
        .coinInNTD_1(coinInNTD_1),
        .itemTypeIn(itemTypeIn),
        .coinOutNTD_50(coinOutNTD_50),
        .coinOutNTD_10(coinOutNTD_10),
        .coinOutNTD_5(coinOutNTD_5),
        .coinOutNTD_1(coinOutNTD_1),
        .itemTypeOut(itemTypeOut),
        .serviceTypeOut(serviceTypeOut)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        if (!$value$plusargs("stim=%s", stim_path)) begin
            $display("TB_ERROR missing +stim=<path>");
            $finish(1);
        end
        if (!$value$plusargs("out=%s", out_path)) begin
            $display("TB_ERROR missing +out=<path>");
            $finish(1);
        end

        in_fd = $fopen(stim_path, "r");
        if (in_fd == 0) begin
            $display("TB_ERROR cannot open stimulus file: %0s", stim_path);
            $finish(1);
        end

        out_fd = $fopen(out_path, "w");
        if (out_fd == 0) begin
            $display("TB_ERROR cannot open output file: %0s", out_path);
            $finish(1);
        end

        reset        = 1'b1;
        coinInNTD_50 = 2'd0;
        coinInNTD_10 = 2'd0;
        coinInNTD_5  = 2'd0;
        coinInNTD_1  = 2'd0;
        itemTypeIn   = 2'd0;
        cycle        = 0;

        while (!$feof(in_fd)) begin
            rc = $fscanf(in_fd, "%d %d %d %d %d %d\n",
                         stim_reset, stim_coin50, stim_coin10, stim_coin5, stim_coin1, stim_item);
            if (rc == 6) begin
                @(negedge clk);
                reset        = stim_reset;
                coinInNTD_50 = stim_coin50;
                coinInNTD_10 = stim_coin10;
                coinInNTD_5  = stim_coin5;
                coinInNTD_1  = stim_coin1;
                itemTypeIn   = stim_item;

                @(posedge clk);
                #1;
                $fdisplay(out_fd, "%0d %0d %0d %0d %0d %0d %0d",
                          cycle, serviceTypeOut, itemTypeOut,
                          coinOutNTD_50, coinOutNTD_10, coinOutNTD_5, coinOutNTD_1);
                cycle = cycle + 1;
            end else if (!$feof(in_fd)) begin
                $display("TB_ERROR malformed stimulus line before cycle %0d", cycle);
                $finish(1);
            end
        end

        $fclose(in_fd);
        $fclose(out_fd);
        $display("TB_DONE cycles=%0d", cycle);
        $finish;
    end
endmodule
