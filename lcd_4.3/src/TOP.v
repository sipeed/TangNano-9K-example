module TOP
(
	input			Reset_Button,
    input           User_Button,
    input           XTAL_IN,

	output			LCD_CLK,
	output			LCD_HYNC,
	output			LCD_SYNC,
	output			LCD_DEN,
	output	[4:0]	LCD_R,
	output	[5:0]	LCD_G,
	output	[4:0]	LCD_B
);

    Gowin_rPLL Gowin_rPLL_9Mhz(
        .clkout(LCD_CLK), // 9MHz
        .clkin(XTAL_IN)   //27MHz
    );

	VGA_timing	VGA_timing_inst(
		.PixelClk	(	LCD_CLK		),
		.nRST		(	Reset_Button),

		.LCD_DE		(	LCD_DEN	 	),
		.LCD_HSYNC	(	LCD_HYNC 	),
    	.LCD_VSYNC	(	LCD_SYNC 	),

		.LCD_B		(	LCD_B		),
		.LCD_G		(	LCD_G		),
		.LCD_R		(	LCD_R		)
	);

endmodule