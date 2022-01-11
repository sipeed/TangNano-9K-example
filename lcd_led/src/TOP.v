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
	output	[4:0]	LCD_B,

    output  [5:0]   LED
);


	wire		CLK_SYS;
	wire		CLK_PIX;

    wire        oscout_o;


/*  
    //Use internal clock
    Gowin_OSC chip_osc(
        .oscout(oscout_o) //output oscout
    );
*/

/*
    This program uses external crystal oscillator and PLL to generate 33.33mhz clock to the screen
    If you use our 4.3-inch screen, you need to modify the PLL parameters (tools - > IP core generator) 
    to make CLK_ Pix is between 8-12mhz (according to the specification of the screen)
*/

    Gowin_rPLL chip_pll
    (
        .clkout(CLK_SYS), //output clkout      //200M
        .clkoutd(CLK_PIX), //output clkoutd   //33.33M
        .clkin(XTAL_IN) //input clkin
    );


	VGAMod	D1
	(
		.CLK		(	CLK_SYS     ),
		.nRST		(	Reset_Button),

		.PixelClk	(	CLK_PIX		),
		.LCD_DE		(	LCD_DEN	 	),
		.LCD_HSYNC	(	LCD_HYNC 	),
    	.LCD_VSYNC	(	LCD_SYNC 	),

		.LCD_B		(	LCD_B		),
		.LCD_G		(	LCD_G		),
		.LCD_R		(	LCD_R		)
	);

	assign		LCD_CLK		=	CLK_PIX;



//LED drive
    reg     [31:0]  counter;
    reg     [5:0]   LED;


    always @(posedge XTAL_IN or negedge Reset_Button) begin
    if (!Reset_Button)
        counter <= 24'd0;
    else if (counter < 24'd400_0000)       // 0.5s delay
        counter <= counter + 1;
    else
        counter <= 24'd0;
    end

    always @(posedge XTAL_IN or negedge Reset_Button) begin
    if (!Reset_Button)
        LED <= 6'b111110;       
    else if (counter == 24'd400_0000)       // 0.5s delay
        LED[5:0] <= {LED[4:0],LED[5]};        
    else
        LED <= LED;
    end

endmodule
