`timescale 1ps/1ps

module _tb_lcd114_test();

reg clk;
reg resetn;

initial
begin
	clk = 0;
	forever #1 clk = ~clk;
end

initial begin
	resetn = 1;
	#10
	resetn = 0;
	#10
	resetn = 1;
	#2000
	resetn = 0;
	#10
	resetn = 1;
	#2000 $stop;
end

lcd114_test u_lcd114_test(
	.clk(clk),
	.resetn(resetn),

	.ser_tx(),
	.ser_rx(),

	.lcd_resetn(),
	.lcd_clk(),
	.lcd_cs(),
	.lcd_rs(),
	.lcd_data()
);

endmodule
