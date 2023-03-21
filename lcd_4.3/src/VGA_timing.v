module VGA_timing
(
    input                   PixelClk,
    input                   nRST,

    output                  LCD_DE,
    output                  LCD_HSYNC,
    output                  LCD_VSYNC,

	output          [4:0]   LCD_B,
	output          [5:0]   LCD_G,
	output          [4:0]   LCD_R
);
	
    // Horizen count to Hsync, then next Horizen line.

    parameter       H_Pixel_Valid    = 16'd480; 
    parameter       H_FrontPorch     = 16'd50;
    parameter       H_BackPorch      = 16'd30;  

    parameter       PixelForHS       = H_Pixel_Valid + H_FrontPorch + H_BackPorch;

    parameter       V_Pixel_Valid    = 16'd272; 
    parameter       V_FrontPorch     = 16'd20;  
    parameter       V_BackPorch      = 16'd5;    

    parameter       PixelForVS       = V_Pixel_Valid + V_FrontPorch + V_BackPorch;

    // Horizen pixel count

    reg         [15:0]  H_PixelCount;
    reg         [15:0]  V_PixelCount;

    always @(  posedge PixelClk or negedge nRST  )begin
        if( !nRST ) begin
            V_PixelCount      <=  16'b0;    
            H_PixelCount      <=  16'b0;
            end
        else if(  H_PixelCount == PixelForHS ) begin
            V_PixelCount      <=  V_PixelCount + 1'b1;
            H_PixelCount      <=  16'b0;
            end
        else if(  V_PixelCount == PixelForVS ) begin
            V_PixelCount      <=  16'b0;
            H_PixelCount      <=  16'b0;
            end
        else begin
            V_PixelCount      <=  V_PixelCount ;
            H_PixelCount      <=  H_PixelCount + 1'b1;
        end
    end

    // SYNC-DE MODE

    assign  LCD_DE =    ( H_PixelCount >= H_BackPorch ) && ( H_PixelCount <= H_Pixel_Valid + H_BackPorch ) &&
                        ( V_PixelCount >= V_BackPorch ) && ( V_PixelCount <= V_Pixel_Valid + V_BackPorch ) && PixelClk;

    // color bar
    localparam          Colorbar_width   =   H_Pixel_Valid / 16;

    assign  LCD_R     = ( H_PixelCount < ( H_BackPorch +  Colorbar_width * 0  )) ? 5'b00000 :
                        ( H_PixelCount < ( H_BackPorch +  Colorbar_width * 1  )) ? 5'b00001 : 
                        ( H_PixelCount < ( H_BackPorch +  Colorbar_width * 2  )) ? 5'b00010 :    
                        ( H_PixelCount < ( H_BackPorch +  Colorbar_width * 3  )) ? 5'b00100 :    
                        ( H_PixelCount < ( H_BackPorch +  Colorbar_width * 4  )) ? 5'b01000 :    
                        ( H_PixelCount < ( H_BackPorch +  Colorbar_width * 5  )) ? 5'b10000 :  5'b00000;

    assign  LCD_G    =  ( H_PixelCount < ( H_BackPorch +  Colorbar_width * 6  )) ? 6'b000001: 
                        ( H_PixelCount < ( H_BackPorch +  Colorbar_width * 7  )) ? 6'b000010:    
                        ( H_PixelCount < ( H_BackPorch +  Colorbar_width * 8  )) ? 6'b000100:    
                        ( H_PixelCount < ( H_BackPorch +  Colorbar_width * 9  )) ? 6'b001000:    
                        ( H_PixelCount < ( H_BackPorch +  Colorbar_width * 10 )) ? 6'b010000:    
                        ( H_PixelCount < ( H_BackPorch +  Colorbar_width * 11 )) ? 6'b100000:  6'b000000;

    assign  LCD_B    =  ( H_PixelCount < ( H_BackPorch +  Colorbar_width * 12 )) ? 5'b00001 : 
                        ( H_PixelCount < ( H_BackPorch +  Colorbar_width * 13 )) ? 5'b00010 :    
                        ( H_PixelCount < ( H_BackPorch +  Colorbar_width * 14 )) ? 5'b00100 :    
                        ( H_PixelCount < ( H_BackPorch +  Colorbar_width * 15 )) ? 5'b01000 :    
                        ( H_PixelCount < ( H_BackPorch +  Colorbar_width * 16 )) ? 5'b10000 :  5'b00000;

endmodule
