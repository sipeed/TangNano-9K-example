module TOP
(
	input			Reset_Button,
    input           XTAL_IN,

	output			LCD_CLK,
	output			LCD_HYNC,
	output			LCD_SYNC,
	output			LCD_DEN,
	output	[4:0]	LCD_R,
	output	[5:0]	LCD_G,
	output	[4:0]	LCD_B,
    input           User_Button,
    output  [5:0]   LED,
    output  [4:0]   SPILCD_LED,
    output  [3:0]   TF_LED
);




	wire		CLK_SYS;
	wire		CLK_PIX;

    wire        oscout_o;


/* //使用内部时钟
    Gowin_OSC chip_osc(
        .oscout(oscout_o) //output oscout
    );
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
		.nRST		(	Reset_Button		),

		.PixelClk	(	CLK_PIX		),
		.LCD_DE		(	LCD_DEN	 	),
		.LCD_HSYNC	(	LCD_HYNC 	),
    	.LCD_VSYNC	(	LCD_SYNC 	),

		.LCD_B		(	LCD_B		),
		.LCD_G		(	LCD_G		),
		.LCD_R		(	LCD_R		)
	);

	assign		LCD_CLK		=	CLK_PIX;





/*LED///////////////////////////////////////////////////////////////////////////*/

    reg     [31:0]  counter;
/*    reg     [5:0]   LED;
    reg     [4:0]   SPILCD_LED;
    reg     [3:0]   TF_LED;*/

    reg     [5:0]   temp1;
    reg     [4:0]   temp2;
    reg     [3:0]   temp3;    

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
        temp1 <= 6'b111110;       
    else if (counter == 24'd400_0000)       // 0.5s delay
        temp1[5:0] <= {temp1[4:0],temp1[5]};        
    else
        temp1 <= temp1;
    end

    always @(posedge XTAL_IN or negedge Reset_Button) begin
    if (!Reset_Button)
        temp2 <= 5'b11110;
    else if (counter == 24'd400_0000)       // 0.5s delay
        temp2[4:0] <= {temp2[3:0],temp2[4]};
    else
        temp2 <= temp2;
    end

    always @(posedge XTAL_IN or negedge Reset_Button) begin
    if (!Reset_Button)
        temp3 <=4'b1110;
    else if (counter == 24'd400_0000)       // 0.5s delay
        temp3[3:0] <= {temp3[2:0],temp3[3]};
    else
        temp3 <= temp3;
    end

    assign LED = temp1;
    assign SPILCD_LED = temp2;
    assign TF_LED = temp3;

/*    LED LED_test
    (
        .XTAL_IN    (   27M_clk     ),
        .Reset_Button  (   Button_rst_n),
        .LED        (   LED        ),
    );
*/



endmodule
