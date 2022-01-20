//==============================================================================================
//
// P25Q32H.v - 32M-BIT CMOS Serial Flash Memory
//
//                           COPYRIGHT 2017 PUYA Semiconductor Co., Ltd.
//----------------------------------------------------------------------------------------------
// Reference Doc: P25Q32H Datasheet, Mar. 1, 2016
// Creation Date: 2017/11/01
// Version      : 0.6
//----------------------------------------------------------------------------------------------
// Version history
// V0.6   update timing in WRSR
// V0.5	  initial release
//----------------------------------------------------------------------------------------------
// Note 1:model can load initial flash data from file when parameter Init_File = "xxx" was defined; 
//        xxx: initial flash data file name;default value xxx = "none", initial flash data is "FF".
// Note 2:power setup time is tVSL = 70_000 ns, so after power up, chip can be enable.
// Note 3:because it is not checked during the Board system simulation the tCLQX timing is not
//        inserted to the read function flow temporarily.
// Note 4:more than one values (min. typ. max. value) are defined for some AC parameters in the
//        datasheet, but only one of them is selected in the behavior model, e.g. program and
//        erase cycle time is typical value. For the detailed information of the parameters,
//        please refer to datasheet and contact with PUYA.
// Note 5:SFDP data is initialized with all "FF". For SFDP register values detail, please contact 
//        with PUYA.
//============================================================================================== 
// timescale define
//============================================================================================== 
`timescale 1ns / 100ps

// *============================================================================================== 
// * product parameter define
// *============================================================================================== 
    /*----------------------------------------------------------------------*/
    /* all the parameters users may need to change                          */
    /*----------------------------------------------------------------------*/

        `define Vtclqv_h 6   //30pf:8ns, 15pf:6ns
        `define Vtclqv_l 6   //30pf:8ns, 15pf:6ns
        `define File_Name         "fw/fw-flash/build/fw-flash.v"     // Flash data file name for normal array
        `define File_Name_Secu1   "none"     // Flash data file name for security region
        `define File_Name_Secu2   "none"     // Flash data file name for security region
        `define File_Name_Secu3   "none"     // Flash data file name for security region
        `define File_Name_SFDP    "none" //"none"     // Flash data file name for SFDP region
        `define VStatus_Reg14_11    4'b0000  // status register[14:11] are non-volatile bits
        `define VStatus_Reg9_2    8'b00000000  // status register[9:2] are non-volatile bits
        `define VControl_Reg2    1'b0          // control register[2] are non-volatile bits
        `define VControl_Reg7_5    3'b000      // control register[7:5] are non-volatile bits
        `define HighV_Operation   0          // fix to 0
        `define UUID             128'h3355_2244_6677_effe_2358_ff99_2200_5aa5

    /*----------------------------------------------------------------------*/
    /* Define Options                                                       */
    /*----------------------------------------------------------------------*/
                `define HOLD_ENABLE                     //HOLD# ENABLE
                `define HIGH_PERFORMANCE_DEFAULT        //High Performance Mode default


    /*----------------------------------------------------------------------*/
    /* Define controller STATE                                              */
    /*----------------------------------------------------------------------*/
        `define         STANDBY_STATE           0
        `define         CMD_STATE               1
        `define         BAD_CMD_STATE           2

module P25Q32H( SCLK, 
                CSb, 
                SI, 
                SO, 
                WPb, 
                SIO3 );

// *============================================================================================== 
// * Declaration of ports (input, output, inout)
// *============================================================================================== 
    input  SCLK;    // Signal of Clock Input
    input  CSb;      // Chip select (Low active)
    inout  SI;      // Serial Input/Output SIO0
    inout  SO;      // Serial Input/Output SIO1
    inout  WPb;      // Serial Input/Output SIO2
    inout  SIO3;    // Serial Input/Output SIO3

// *============================================================================================== 
// * Declaration of parameter (parameter)
// *============================================================================================== 
    /*----------------------------------------------------------------------*/
    /* Density STATE parameter                                              */                  
    /*----------------------------------------------------------------------*/
    parameter   A_MSB           = 21,            
                TOP_Add         = 22'h3fffff,
                A_MSB_OTP       = 9,                
                Secur_TOP_Add   = 10'h3ff,
                Sector_MSB      = 9,     // total 1024 sectors = 2^10
                A_MSB_SFDP      = 8,
                SFDP_TOP_Add    = 9'h1ff,
                Buffer_Num      = 256,
                Page_MSB        = 13,        // Total 16384 page x 256 bytes = 2^14 x 256
                Block_MSB       = 5,    // 2^6 = 64
                Block_NUM       = 64;
    parameter   HOLD_EN         = 1;

    /*----------------------------------------------------------------------*/
    /* Define ID Parameter                                                  */
    /*----------------------------------------------------------------------*/
    parameter   ID_PUYA         = 8'h85,
                ID_Device       = 8'h15,
                Memory_Type     = 8'h60,
                Memory_Density  = 8'h16;

    /*----------------------------------------------------------------------*/
    /* Define Initial Memory File Name                                      */
    /*----------------------------------------------------------------------*/
    parameter   Init_File       = `File_Name;      // initial flash data
    parameter   Init_File_Secu1 = `File_Name_Secu1; // initial flash data for security
    parameter   Init_File_Secu2 = `File_Name_Secu2; // initial flash data for security
    parameter   Init_File_Secu3 = `File_Name_Secu3; // initial flash data for security
    parameter   Init_File_SFDP  = `File_Name_SFDP;  // initial flash data for SFDP

    /*----------------------------------------------------------------------*/
    /* AC Characters Parameter                                              */
    /*----------------------------------------------------------------------*/
    parameter   tSHQZ           = 8,            // CSb High to SO Float Time [ns]
                tCLQV_H         = `Vtclqv_h,    // Clock Low to Output Valid in High Performance Mode
                tCLQV_L         = `Vtclqv_l,    // Clock Low to Output Valid in Low Power Mode
                tCLQX           = 0,            // Output hold time
                tW_L            = 12_000_000,    // Write Status time in Low Power Mode
                tW_H            = 12_000_000,    // Write Status time in High Performance Mode
                tW_same         = 1_000,        // Write Status/Control time is 1us if data is same
                tW_zero         = 3_000_000,    // Write Status/Control time is 3ms if previous data is zero
                tREADY2_P       = 30_000,       // hardware reset recovery time for pgm
                tREADY2_SE      = 30_000,       // hardware reset recovery time for sector ers
                tREADY2_BE      = 30_000,       // hardware reset recovery time for block ers
                tREADY2_CE      = 30_000,       // hardware reset recovery time for chip ers
                tREADY2_R       = 30_000,       // hardware reset recovery time for read
                tREADY2_D       = 30_000,       // hardware reset recovery time for instruction decoding phase
                tREADY2_W       = 12_000_000,    // hardware reset recovery time for WRSR
                tVSL            = 10,       // Time delay to chip select allowed
                tVSL1           = 70_000,       // time delay used to chip select allowed of High Voltage operation
                tVhv            = 250,          // time delay used to chip select allowed of High Voltage operation
                tVhv2           = 0,            // time delay used to chip select allowed of High Voltage operation
                tRDP_H          = 8_000,        // Deep Power Down Mode to Stand By Mode time in High Performance Mode
                tRDP_L          = 8_000,        // Deep Power Down Mode to Stand By Mode time in Low Power Mode
                tBP_Vhv         = 2_000_000,    // Byte program time when High Voltage Operation is enabled
                tBP_H           = 2_000_000,    // Byte program time in High Performance Mode 
                tBP_L           = 2_000_000,    // Byte program time in Low Power Mode 
                tPP_Vhv         = 2_000_000,    // Program time when High Voltage Operation is enabled
                tPP_H           = 2_000_000,    // Program time in High Performance Mode 
                tPP_L           = 2_000_000,    // Program time in Low Power Mode 
                tSE_Vhv         = 6_000_000,    // Sector erase time when High Voltage Operation is enabled 
                tSE_H           = 6_000_000,    // Sector erase time in High Performance Mode  
                tSE_L           = 6_000_000,    // Sector erase time in Low Power Mode  
                tBE_Vhv         = 6_000_000,    // Block erase time when High Voltage Operation is enabled
                tBE_H           = 6_000_000,    // Block erase time in High Performance Mode 
                tBE_L           = 6_000_000,    // Block erase time in Low Power Mode 
                tBE32_Vhv       = 6_000_000,    // Block 32KB erase time when High Voltage Operation is enabled
                tBE32_H         = 6_000_000,    // Block 32KB erase time in High Performance Mode 
                tBE32_L         = 6_000_000,    // Block 32KB erase time in Low Power Mode 
                tCE_Vhv         = 6,            // Chip erase time when High Voltage Operation is enabled
                                                // unit is ms instead of ns
                tCE_H           = 6,            // Chip erase time in High Performance Mode 
                                                // unit is ms instead of ns
                tCE_L           = 6,            // Chip erase time in Low Power Mode 
                                                // unit is ms instead of ns
                tHHQX           = 10,           // HOLD to Output Low-z
                tHLQZ           = 10,           // HOLD to Output High-z
                tCRDP           = 20,           // CS# Toggling Time before Release from Deep Power-Down Mode 
                tDPDD           = 3_000,        // Delay Time for Release from Deep Power-Down Mode once entering DP Mode
                tWMS            = 20_000;       // Write Status Register Cycle Time for Mode Switching

    parameter   tPGM_CHK        = 100,          // 2 us
                tERS_CHK        = 100;          // 100 us
    parameter   tESL_L          = 30_000,       // delay after erase suspend command in Low Power Mode
                tESL_H          = 30_000,       // delay after erase suspend command in High Performance Mode
                tPSL_L          = 30_000,       // delay after erase suspend command in Low Power Mode
                tPSL_H          = 30_000,       // delay after erase suspend command in High Performance Mode
                tPRS            = 300,          // latency between program resume and next suspend
                tERS            = 300;          // latency between erase resume and next suspend

    /*----------------------------------------------------------------------*/
    /* Internal counter parameter                                           */
    /*----------------------------------------------------------------------*/
    parameter  Clock            = 50;           // Internal clock cycle = 100ns


    specify
        specparam   tSCLK_H   = 8.3, 	// Clock Cycle Time [ns] in High Performance Mode
                    fSCLK_H   = 120, 	// Clock Frequence except READ instruction in High Performance Mode
                    tSCLK_L   = 9.6, 	// Clock Cycle Time [ns] in Low Power Mode
                    fSCLK_L   = 104, 	// Clock Frequence except READ instruction in Low Power Mode
                    tRSCLK    = 18.2,	// Clock Cycle Time for READ instruction
                    fRSCLK    = 55,  	// Clock Frequence for READ instruction
                    tCH_H     = 4.5, 	// Clock High Time (min) [ns] in High Performance Mode
                    tCL_H     = 4.5, 	// Clock Low  Time (min) [ns] in High Performance Mode
                    tCH_L     = 4.5, 	// Clock High Time (min) [ns] in Low Power Mode
                    tCL_L     = 4.5, 	// Clock Low  Time (min) [ns] in Low Power Mode
                    tCH_R     = 5.5, 	// Clock High Time (min) [ns] for normal read
                    tCL_R     = 5.5, 	// Clock Low  Time (min) [ns] for normal read
                    tSLCH     = 5,   	// CS# Active Setup Time (relative to SCLK) (min) [ns]
                    tCHSL     = 5,   	// CS# Not Active Hold Time (relative to SCLK)(min) [ns]
                    tSHSL_R   = 15,  	// CSb High Time for read instruction (min) [ns]
                    tSHSL_W   = 30,  	// CSb High Time for write instruction (min) [ns]
                    tDVCH     = 2,   	// SI Setup Time (min) [ns]
                    tCHDX     = 3,   	// SI Hold  Time (min) [ns]
                    tCHSH     = 5,   	// CS# Active Hold Time (relative to SCLK) (min) [ns]
                    tSHCH     = 5,   	// CS# Not Active Setup Time (relative to SCLK) (min) [ns]
                    tWHSL     = 10,  	// Write Protection Setup Time                
                    tSHWL     = 10,  	// Write Protection Hold  Time   
                    tTSCLK_H  = 8.3, 	// Clock Cycle Time for 2XI/O READ + 4 Dummy in High Performance Mode
                    fTSCLK_H  = 120, 	// Clock Frequence for 2XI/O READ + 4 Dummy in High Performance Mode
                    tTSCLK_L  = 9.6,	// Clock Cycle Time for 2XI/O READ + 4 Dummy in Low Power Mode
                    fTSCLK_L  = 104,  	// Clock Frequence for 2XI/O READ + 4 Dummy in Low Power Mode
                    tTSCLK1_H = 8.3, 	// Clock Cycle Time for 1I/2O READ in High Performance Mode
                    fTSCLK1_H = 120, 	// Clock Frequence for 1I/2O READ in High Performance Mode
                    tTSCLK1_L = 9.6,	// Clock Cycle Time for 1I/2O READ in Low Power Mode
                    fTSCLK1_L = 104,  	// Clock Frequence for 1I/2O READ in Low Power Mode
                    tQSCLK_H  = 8.3, 	// Clock Cycle Time for 4XI/O READ + 6 Dummy in High Performance Mode
                    fQSCLK_H  = 120, 	// Clock Frequence for 4XI/O READ + 6 Dummy in High Performance Mode
                    tQSCLK_L  = 9.6,	// Clock Cycle Time for 4XI/O READ + 6 Dummy in Low Power Mode
                    fQSCLK_L  = 104,  	// Clock Frequence for 4XI/O READ + 6 Dummy in Low Power Mode
                    tQSCLK1_H = 8.3, 	// Clock Cycle Time for 1I/4O READ in High Performance Mode
                    fQSCLK1_H = 120, 	// Clock Frequence for 1I/4O READ in High Performance Mode
                    tQSCLK1_L = 9.6,	// Clock Cycle Time for 1I/4O READ in Low Power Mode
                    fQSCLK1_L = 104,  	// Clock Frequence for 1I/4O READ in Low Power Mode
                    t4PP_H    = 8.3, 	// Clock Time for 4PP program in High Performance Mode
                    f4PP_H    = 120, 	// Clock Frequency for 4PP program in High Performance Mode
                    t4PP_L    = 9.6,	// Clock Time for 4PP program in Low Power Mode
                    f4PP_L    = 104,  	// Clock Frequency for 4PP program in Low Power Mode
                    tHLCH     = 8,   	// HOLD#  Setup Time (relative to SCLK) (min) [ns]
                    tCHHH     = 8,   	// HOLD#  Hold  Time (relative to SCLK) (min) [ns]
                    tHHCH     = 8,   	// HOLD  Setup Time (relative to SCLK) (min) [ns]
                    tCHHL     = 8,   	// HOLD  Hold  Time (relative to SCLK) (min) [ns]
                    tDP       = 3_000,  // CSb high to deep power-down mode
                    tRES1     = 30_000,
                    tSCLK_WRSR  = 8.3,	// Clock Cycle Time [ns] when issuing WRSR for performance mode switch
                    fSCLK_WRSR  = 120,	// Clock Frequence when issuing WRSR for performance mode switch
                    tSCLK_WRCR  = 8.3,	// Clock Cycle Time [ns] when issuing WRCR for performance mode switch
                    fSCLK_WRCR  = 120,	// Clock Frequence when issuing WRCR for performance mode switch
                    tRLRH       = 1_000,        // hardware reset pulse
                    tRS         = 15,           // reset setup time
                    tRH         = 15,           // reset hold time
                    tRHSL       = 1_000;        // RESET# high before CS# low


     endspecify

    /*----------------------------------------------------------------------*/
    /* Define Command Parameter                                             */
    /*----------------------------------------------------------------------*/
    parameter   WREN        = 8'h06, // WriteEnable   
                WRDI        = 8'h04, // WriteDisable  
                RDID        = 8'h9f, // ReadID    
                RDSR        = 8'h05, // ReadStatus        
                RDSR2       = 8'h35, // ReadStatus, new cmd       
                WRSR        = 8'h01, // WriteStatus
                RDCR        = 8'h15, // read configuration register   
                WRCR        = 8'h11, // write configuration register, in P25Q32, change to h11 instead of h31 in P25Q8/Q16 device
                READ1X      = 8'h03, // ReadData          
                FASTREAD1X  = 8'h0b, // FastReadData  
                SE          = 8'h20, // SectorErase   
                BE32        = 8'h52, // 32k block erase
                BE64        = 8'hd8, // BlockErase
                CE1         = 8'h60, // ChipErase         
                CE2         = 8'hc7, // ChipErase         
                PP          = 8'h02, // PageProgram 
                DPP         = 8'ha2, // Dual PageProgram, new
                QPP         = 8'h32, // Quad PageProgram, new
                DP          = 8'hb9, // DeepPowerDown
                RES         = 8'hab, // ReadElectricID 
                REMS        = 8'h90, // ReadElectricManufacturerDeviceID
                READ2X      = 8'hbb, // 2X Read 
                READ4X      = 8'heb, // 4XI/O Read;
                SFDP_READ   = 8'h5a, // enter SFDP read mode
                DREAD       = 8'h3b, // Fastread dual output;
                QREAD       = 8'h6b, // Fastread quad output 1I/4O
                NOP         = 8'h00, // no operation
                RSTEN       = 8'h66, // reset enable
                RST         = 8'h99, // reset memory
                SUSP        = 8'hb0,
                SUSP1       = 8'h75,
                RESU        = 8'h30,
                RESU1       = 8'h7a,
                // new added cmd
                DREMS       = 8'h92,  // Dual read manufacture id
                QREMS       = 8'h94,  // Quad read manufacture id
                ERSCUR      = 8'h44,  // erase security
                PRSCUR      = 8'h42,  // program security
                RDSCUR      = 8'h48,  // read security
                PE          = 8'h81,  // page erase
                RUID        = 8'h4b,  // page erase
                RSEN        = 8'hff,  // release from ehanced read mode
                VWREN       = 8'h50,  // release from ehanced read mode
                ASI         = 8'h25,  // active status interrupt
                // ---- 32m special command , these are new commands
                ENQPI       = 8'h38,
                DISQPI      = 8'hff,
                WORDREAD    = 8'he7,  
                OCTALREAD   = 8'he3,
                SBLK        = 8'h36,
                SBULK       = 8'h39,
                RDBLOCK     = 8'h3c,
                RDBLOCK2    = 8'h3d,
                GBLK        = 8'h7e,
                GBULK       = 8'h98,
                WRSR2       = 8'h31,
                BURSTRD     = 8'h0c,  // Burst read with wrap, qpi only
                SETRDPA     = 8'hc0,  // Set read dummy and wrap, qpi only

                // end new cmd
                SBL         = 8'h77;
                 
    /*----------------------------------------------------------------------*/
    /* Declaration of internal-signal                                       */
    /*----------------------------------------------------------------------*/
    reg  [23:0]	 	Data00=24'h00_00_00;
    reg  [23:0]	 	DataFF=24'hFF_FF_FF;
    reg  [7:0]           ARRAY[0:TOP_Add];  // memory array
    reg  [15:0]          Status_Reg;        // Status Register
    reg  [15:0]          VStatus_Reg;        // volatile Status Register
    reg  [7:0]           CMD_BUS;
    reg  [23:0]          SI_Reg;            // temp reg to store serial in
    //reg  [7:0]           Dummy_A[0:255];    // page size
    reg  [7:0]           Dummy_A[0:1023];    // page size
    reg  [A_MSB:0]       Address;           
    reg  [7:0]           M7_0;          // new, M7_0[5:4]=2'b10 --> continuous read mode 
    reg  [Sector_MSB:0]  Sector;
    reg  [Block_MSB:0]   Block;
    reg  [Block_MSB+1:0] Block2;
    reg  [Page_MSB:0]    Page;
    reg  [2:0]           STATE;
    reg  [7:0]           SFDP_ARRAY[0:SFDP_TOP_Add];
    reg  [7:0]           Control_Reg;
    reg  [62:1]          Block_Lock_Reg;
    reg  [15:0]          Block0_SL_Reg;
    reg  [15:0]          Block63_SL_Reg;
    
    reg     QPI_Mode;          // P25Q32 QPI Mode
    reg     Set_QPI_Mode;
    reg     Chip_EN;
    reg     DP_Mode;        // deep power down mode
    reg     Read_Mode;
    reg     Read_1XIO_Mode;
    reg     Read_1XIO_Chk;

    reg     tWRSR_Chk;
    reg     tWRCR_Chk;
    reg     tDP_Chk;
    reg     tRES1_Chk;

    reg     RDID_Mode;
    reg     RUID_Mode;
    reg     RDSR_Mode;
    reg     RDSR2_Mode;
    reg     RDSCUR_Mode;
    reg     PRSCUR_Mode;
    reg     ERSCUR_Mode;
    reg     FastRD_1XIO_Mode;   
    reg     PP_1XIO_Mode;
    reg     DPP_1XIO_Mode;
    reg     QPP_1XIO_Mode;
    reg     SE_4K_Mode;
    reg     PE_Mode;
    reg     BE_Mode;
    reg     BE32K_Mode;
    reg     BE64K_Mode;
    reg     CE_Mode;
    reg     WRSR_Mode;
    reg     WRSR2_Mode;
    reg     WRCR_Mode;
    reg     RES_Mode;
    reg     REMS_Mode;
    reg     DREMS_Mode;
    reg     QREMS_Mode;
    reg     RDCR_Mode;
    reg     SCLK_EN;
    reg     SO_OUT_EN;   // for SO
    reg     SI_IN_EN;    // for SI
    reg     SFDP_Mode;
    reg     RST_CMD_EN;
    reg     EN_Burst;
    reg     W4Read_Mode;
    reg     Fast4x_Mode;
    reg     Susp_Ready;
    reg     Susp_Trig;
    reg     Resume_Trig;
    reg     During_Susp_Wait;
    reg     ERS_CLK;                  // internal clock register for erase timer
    reg     PGM_CLK;                  // internal clock register for program timer
    reg     WR2Susp;
    reg     HOLD_OUT_B;

    reg     RDP_EN;
    reg     ASI_Mode;
    reg     tCRDP_Check_EN;

    wire    CS_INT;
    wire    WP_B_INT;
    wire    RESETB_INT;
    wire    HOLD_B_INT;
    wire    SCLK;
    wire    ISCLK; 
    wire    WIP;
    wire    ESB;
    wire    PSB;
    wire    EPSUSP;
    wire    WEL;
    wire    SRWD;
    // new status register
    wire    [4:0] SREG_BP;
    wire    SREG_LB3;   // OTP 3 write protect, one time, change permanently
    wire    SREG_LB2;   // OTP 2 write protect, one time, change permanently
    wire    SREG_LB1;   // OTP 1 write protect, one time, change permanently
    wire    SREG_QE;
    wire    SREG_CMP;
    wire    [1:0] SREG_SRP;
    wire    SREG_SUS1;
    wire    SREG_SUS2;
    wire    CR_HOLD_RESET;
    wire    [1:0] CR_DRV;
    wire    CR_QP;
    wire    CR_WPS; 
    // -- end new status register definition

    wire    Dis_CE, Dis_WRSR;  
    wire    Norm_Array_Mode;
    wire    Low_Power_Mode;
    wire    Pgm_Mode;
    wire    Ers_Mode;

    event   DEBUG_FSM_EVENT;
    event   ERSCUR_Event; //new
    event   PRSCUR_Event; //new
    event   Resume_Event; 
    event   Susp_Event; 
    event   WRSR_Event; 
    event   WRSR2_Event; 
    event   WRCR_Event; 
    event   BE_Event;
    event   BE32K_Event;
    event   SE_4K_Event;
    event   PE_Event;
    event   CE_Event;
    event   PP_Event;
    event   RST_Event;
    event   RST_EN_Event;
    event   HDRST_Event;

    integer i;
    integer j;
    integer Bit; 
    integer Bit_Tmp; 
    integer Start_Add;
    integer End_Add;
    integer tWRSR;
    integer tWRCR;
    integer Burst_Length;
//    time    tRES;
    time    ERS_Time;
    reg Read_SHSL;
    wire Write_SHSL;

    reg  [7:0]           Secur_ARRAY1[0:Secur_TOP_Add]; // Secured OTP 
    reg  [7:0]           Secur_ARRAY2[0:Secur_TOP_Add]; // Secured OTP 
    reg  [7:0]           Secur_ARRAY3[0:Secur_TOP_Add]; // Secured OTP 

    //reg     Secur_Mode;     // enter secured mode
    reg     Read_2XIO_Mode;
    reg     Read_2XIO_Chk;
    reg     Byte_PGM_Mode;          
    reg     SI_OUT_EN;   // for SI
    reg     SO_IN_EN;    // for SO
    reg     SIO0_Reg;
    reg     SIO1_Reg;
    reg     SIO2_Reg;
    reg     SIO3_Reg;
    reg     SIO0_Out_Reg;
    reg     SIO1_Out_Reg;
    reg     SIO2_Out_Reg;
    reg     SIO3_Out_Reg;
    reg     Read_4XIO_Mode;
    reg     READ4X_Mode;
    reg     READ2X_Mode;
    reg     Read_4XIO_Chk;
    reg     FastRD_2XIO_Mode;
    reg     FastRD_4XIO_Mode;
    reg     FastRD_2XIO_Chk;
    reg     FastRD_4XIO_Chk;
    reg [7:0]    RSEN_SI_Reg;  // release read enhanced mode cmd register
    reg     BurstRead_Mode;  // Burst Read with Wrap mode
    reg [1:0] Param_wrap_length;
    reg [1:0] Param_dummy_clock;

    // new cmds
    reg     WordRead_Mode;
    reg     OctalRead_Mode;

    reg     During_Enter_DP;
    reg     PP_4XIO_Mode;
    reg     PP_4XIO_Load;
    reg     DPP_1XIO_Load;
    reg     PP_4XIO_Chk;
    reg     DPP_1XIO_Chk;
    reg     EN4XIO_Read_Mode;
    reg     EN2XIO_Read_Mode;
    reg     Set_4XIO_Enhance_Mode;   
    reg     Set_2XIO_Enhance_Mode;   
    reg     WP_OUT_EN;   // for WPb pin
    reg     SIO3_OUT_EN; // for SIO3 pin
    reg     WP_IN_EN;    // for WPb pin
    reg     SIO3_IN_EN;  // for SIO3 pin
    //reg[15:0] SBL_cmd;    // for SBL cmd
    //reg      SBL_Mode;

    reg     vwrite_enable_flag;
    //reg     ENQUAD;
    reg     During_RST_REC;
    wire    HPM_RD;
    wire    SIO3;

    wire [31:0]    tCLQV;
    wire [31:0]    tRDP; //  Deep Power Down Mode to Stand By Mode time
    wire [31:0]    tBP;  //  Byte program time
    wire [31:0]    tPP;  // Program time
    wire [31:0]    tSE;  // Sector erase time  
    wire [31:0]    tBE;  // Block erase time
    wire [31:0]    tW;   // write status time
    wire [31:0]    tBE32;        // Block erase time
    wire [31:0]    tCE;  // unit is ms instead of ns  
    wire [31:0]    tESL; // delay after erase suspend command
    wire [31:0]    tPSL; // delay after erase suspend command
    assign tCLQV = Low_Power_Mode ? tCLQV_L : tCLQV_H;
    assign tW = Low_Power_Mode ? tW_L : tW_H;
    assign tRDP = Low_Power_Mode ? tRDP_L : tRDP_H;
    assign tBP = (`HighV_Operation && WPb===1) ? tBP_Vhv : ( Low_Power_Mode ? tBP_L : tBP_H );
    assign tPP = (`HighV_Operation && WPb===1) ? tPP_Vhv : ( Low_Power_Mode ? tPP_L : tPP_H );
    assign tSE = (`HighV_Operation && WPb===1) ? tSE_Vhv : ( Low_Power_Mode ? tSE_L : tSE_H );
    assign tBE = (`HighV_Operation && WPb===1) ? tBE_Vhv : ( Low_Power_Mode ? tBE_L : tBE_H );
    assign tBE32 = (`HighV_Operation && WPb===1) ? tBE32_Vhv : ( Low_Power_Mode ? tBE32_L : tBE32_H );
    assign tCE = (`HighV_Operation && WPb===1) ? tCE_Vhv : ( Low_Power_Mode ? tCE_L : tCE_H );
    assign tESL = Low_Power_Mode ? tESL_L : tESL_H ;
    assign tPSL = Low_Power_Mode ? tPSL_L : tPSL_H ;

    wire [31:0] ERS_Count_SE;
    wire [31:0] ERS_Count_BE;
    wire [31:0] ERS_Count_BE32K;
    wire [31:0] Echip_Count;
    assign ERS_Count_SE = tSE / (Clock*2) / 500;     // Internal clock cycle = 50us
    assign ERS_Count_BE = tBE / (Clock*2) / 500;     // Internal clock cycle = 50us
    assign ERS_Count_BE32K = tBE32 / (Clock*2) / 500;     // Internal clock cycle = 50us
    assign Echip_Count  = tCE  / (Clock*2) * 2000; 

    assign CR_HOLD_RESET = Control_Reg[7];
    assign CR_DRV        = Control_Reg[6:5];
    assign CR_QP         = Control_Reg[4];
    assign CR_WPS        = Control_Reg[2];



    /*----------------------------------------------------------------------*/
    /* initial variable value                                               */
    /*----------------------------------------------------------------------*/
    initial begin
        
        Chip_EN         = 1'b0;
        Status_Reg      = {1'b0, `VStatus_Reg14_11,1'b0, `VStatus_Reg9_2, 2'b00};
        Control_Reg     = {`VControl_Reg7_5, 1'b0, 1'b0, 1'b0, 2'b00};
        READ4X_Mode     = 1'b0;
        READ2X_Mode     = 1'b0;
        reset_sm;
    end   

    initial begin
    	Sector	=Data00[Sector_MSB:0];          
    	Block	=Data00[Block_MSB:0];    
    	Block2	=Data00[Block_MSB+1:0];
    	Page	=Data00[Page_MSB:0];
    end
       

    task reset_sm; 
        begin
            #0;

            Status_Reg[15]  = 1'b0;   // SUS1 is volatile
            Status_Reg[10]  = 1'b0;   // SUS2 is volatile
            Control_Reg[4]  = 1'b0;   // Control_Reg[4].QP is volatile
            Block_Lock_Reg  = 62'h3fffffff_ffffffff;
            Block0_SL_Reg   = 16'hffff;
            Block63_SL_Reg  = 16'hffff;
            Param_wrap_length = 2'b00;
            Param_dummy_clock = 2'b00;
            During_Enter_DP = 1'b0;
            QPI_Mode        = 1'b0;
            Set_QPI_Mode    = 1'b0;
            //SBL_cmd         = 0;
            //SBL_Mode        = 0;
            vwrite_enable_flag = 0;
            RSEN_SI_Reg     = 0;
            VStatus_Reg     = {1'b0, Status_Reg[14:11] ,1'b0, Status_Reg[9:2], 2'b00};
            ASI_Mode        = 1'b0;
            During_RST_REC  = 1'b0;
            SIO0_Reg        = 1'b1;
            SIO1_Reg        = 1'b1;
            SIO2_Reg        = 1'b1;
            SIO3_Reg        = 1'b1;
            SIO0_Out_Reg    = SIO0_Reg;
            SIO1_Out_Reg    = SIO1_Reg;
            SIO2_Out_Reg    = SIO2_Reg;
            SIO3_Out_Reg    = SIO3_Reg;
            RST_CMD_EN      = 1'b0;
            //ENQUAD          = 1'b0;
            SO_OUT_EN       = 1'b0; // SO output enable
            SI_IN_EN        = 1'b0; // SI input enable
            CMD_BUS         = 8'b0000_0000;
            Address         = 0;
            M7_0            = 0;
            i               = 0;
            j               = 0;
            Bit             = 0;
            Bit_Tmp         = 0;
            Start_Add       = 0;
            End_Add         = 0;
            DP_Mode         = 1'b0;
            SCLK_EN         = 1'b1;
            Read_Mode       = 1'b0;
            Read_1XIO_Mode  = 1'b0;
            Read_1XIO_Chk   = 1'b0;
            tDP_Chk         = 1'b0;
            tWRSR_Chk       = 1'b0;
            tWRCR_Chk       = 1'b0;
            tRES1_Chk       = 1'b0;

            RDID_Mode       = 1'b0;
            RUID_Mode       = 1'b0;
            RDSR_Mode       = 1'b0;
            RDSR2_Mode       = 1'b0;
            RDSCUR_Mode     = 1'b0;
            ERSCUR_Mode     = 1'b0;
            PRSCUR_Mode     = 1'b0;
            RDCR_Mode       = 1'b0;
            WRCR_Mode       = 1'b0;
            PP_1XIO_Mode    = 1'b0;
            DPP_1XIO_Mode    = 1'b0;
            QPP_1XIO_Mode    = 1'b0;
            SE_4K_Mode      = 1'b0;
            PE_Mode         = 1'b0;
            BE_Mode         = 1'b0;
            BE32K_Mode      = 1'b0;
            BE64K_Mode      = 1'b0;
            CE_Mode         = 1'b0;
            WRSR_Mode       = 1'b0;
            WRSR2_Mode      = 1'b0;
            WRCR_Mode       = 1'b0;
            RES_Mode        = 1'b0;
            REMS_Mode       = 1'b0;
            DREMS_Mode      = 1'b0;
            QREMS_Mode      = 1'b0;
            Read_SHSL       = 1'b0;
            FastRD_1XIO_Mode  = 1'b0;
            FastRD_2XIO_Mode  = 1'b0;
            FastRD_4XIO_Mode  = 1'b0;
            SI_OUT_EN       = 1'b0; // SI output enable
            SO_IN_EN        = 1'b0; // SO input enable
            //Secur_Mode      = 1'b0;
            Read_2XIO_Mode  = 1'b0;
            Read_2XIO_Chk   = 1'b0;
            FastRD_2XIO_Chk = 1'b0;
            FastRD_4XIO_Chk = 1'b0;

            Byte_PGM_Mode   = 1'b0;
            WP_OUT_EN       = 1'b0; // for WPb pin output enable
            SIO3_OUT_EN     = 1'b0; // for SIO3 pin output enable
            WP_IN_EN        = 1'b0; // for WPb pin input enable
            SIO3_IN_EN      = 1'b0; // for SIO3 pin input enable
            HOLD_OUT_B      = 1'b1;                                                   
            Read_4XIO_Mode  = 1'b0;
            W4Read_Mode     = 1'b0;
            Fast4x_Mode     = 1'b0;
            Read_4XIO_Chk   = 1'b0;
            PP_4XIO_Mode    = 1'b0;
            PP_4XIO_Load    = 1'b0;
            PP_4XIO_Chk     = 1'b0;
            DPP_1XIO_Chk     = 1'b0;
            DPP_1XIO_Load    = 1'b0;
            EN4XIO_Read_Mode  = 1'b0;
            EN2XIO_Read_Mode  = 1'b0;
            Set_4XIO_Enhance_Mode = 1'b0;
            Set_2XIO_Enhance_Mode = 1'b0;
            SFDP_Mode         = 1'b0;
            WordRead_Mode     = 1'b0;
            OctalRead_Mode     = 1'b0;
            EN_Burst          = 1'b0;
            Burst_Length      = 8;
            Susp_Ready        = 1'b1;
            Susp_Trig         = 1'b0;
            Resume_Trig       = 1'b0;
            During_Susp_Wait  = 1'b0;
            ERS_CLK           = 1'b0;
            PGM_CLK           = 1'b0;
            WR2Susp           = 1'b0;
            RDP_EN            = 1'b1;
            tCRDP_Check_EN    = 1'b1;
            BurstRead_Mode    = 1'b0; 
        end
    endtask // reset_sm
    
    /*----------------------------------------------------------------------*/
    /* initial flash data                                                   */
    /*----------------------------------------------------------------------*/
    initial 
    begin : memory_initialize
        for ( i = 0; i <=  TOP_Add; i = i + 1 )
            ARRAY[i] = 8'hff; 
        if ( Init_File != "none" )
            $readmemh(Init_File,ARRAY) ;
        for( i = 0; i <=  Secur_TOP_Add; i = i + 1 ) begin
            Secur_ARRAY1[i]=8'hff;
            Secur_ARRAY2[i]=8'hff;
            Secur_ARRAY3[i]=8'hff;
        end
        if ( Init_File_Secu1 != "none" )
            $readmemh(Init_File_Secu1,Secur_ARRAY1) ;
        if ( Init_File_Secu2 != "none" )
            $readmemh(Init_File_Secu2,Secur_ARRAY2) ;
        if ( Init_File_Secu3 != "none" )
            $readmemh(Init_File_Secu3,Secur_ARRAY3) ;
        for( i = 0; i <=  SFDP_TOP_Add; i = i + 1 ) begin
            SFDP_ARRAY[i] = 8'hff;
        end
        if ( Init_File_SFDP != "none" )
            $readmemh(Init_File_SFDP,SFDP_ARRAY) ;
        // define SFDP code
    end

// *============================================================================================== 
// * Input/Output bus operation 
// *==============================================================================================
    assign ISCLK      = ( SCLK_EN == 1'b1 ) ? SCLK : 1'b0;
    //assign CS_INT     = ( During_RST_REC == 1'b0 && RESETB_INT == 1'b1 && Chip_EN ) ? CSb : 1'b1;
    assign CS_INT     = CR_HOLD_RESET ? 1'b1 :( ( During_RST_REC == 1'b0 && RESETB_INT == 1'b1 && Chip_EN ) ? CSb : 1'b1);
    assign WP_B_INT   = !SREG_QE ? WPb : 1'b1;
    //assign RESETB_INT = CR_HOLD_RESET  ? ((!SREG_QE && CS_INT == 1'b0) ? ((SIO3 === 1'b1 || SIO3 === 1'b0) ? SIO3 : 1'b1) : 1'b1) : 1'b1;
    assign RESETB_INT = CR_HOLD_RESET  ? (!SREG_QE  ? ((SIO3 === 1'b1 || SIO3 === 1'b0) ? SIO3 : 1'b1) : 1'b1) : 1'b1;
    assign HOLD_B_INT = !CR_HOLD_RESET ? ((!SREG_QE && CS_INT == 1'b0) ? ((SIO3 === 1'b1 || SIO3 === 1'b0) ? SIO3 : 1'b1) : 1'b1) : 1'b1; 
    assign SO         = ASI_Mode ? WIP : (SO_OUT_EN && HOLD_B_INT) ? SIO1_Out_Reg : 1'bz ;
    assign SI         = (SI_OUT_EN && HOLD_B_INT) ? SIO0_Out_Reg : 1'bz ;
    assign WPb         = (WP_OUT_EN && HOLD_B_INT) ? SIO2_Out_Reg : 1'bz ;
    assign SIO3       = (SIO3_OUT_EN && HOLD_B_INT) ? SIO3_Out_Reg : 1'bz ;

    /*----------------------------------------------------------------------*/
    /*  When  Hold Condtion Operation;                                      */
    /*----------------------------------------------------------------------*/
    always @ ( HOLD_B_INT or negedge SCLK) begin
        if ( HOLD_B_INT == 1'b0 && SCLK == 1'b0) begin
            SCLK_EN =1'b0;
        end
        else if ( HOLD_B_INT == 1'b1 && SCLK == 1'b0) begin
            SCLK_EN =1'b1;
        end
    end

    always @ ( negedge HOLD_B_INT ) begin
            HOLD_OUT_B<= #tHLQZ 1'b0;
    end

    always @ ( posedge HOLD_B_INT ) begin
            HOLD_OUT_B<= #tHHQX 1'b1;
    end

    /*----------------------------------------------------------------------*/
    /* output buffer                                                        */
    /*----------------------------------------------------------------------*/
    always @( SIO3_Reg or SIO2_Reg or SIO1_Reg or SIO0_Reg ) begin
        if ( SIO3_OUT_EN && WP_OUT_EN && SO_OUT_EN && SI_OUT_EN ) begin
            SIO3_Out_Reg <= #tCLQV SIO3_Reg;
            SIO2_Out_Reg <= #tCLQV SIO2_Reg;
            SIO1_Out_Reg <= #tCLQV SIO1_Reg;
            SIO0_Out_Reg <= #tCLQV SIO0_Reg;
        end
        else if ( SO_OUT_EN && SI_OUT_EN ) begin
            SIO1_Out_Reg <= #tCLQV SIO1_Reg;
            SIO0_Out_Reg <= #tCLQV SIO0_Reg;
        end
        else if ( SO_OUT_EN ) begin
            SIO1_Out_Reg <= #tCLQV SIO1_Reg;
        end
    end

// *============================================================================================== 
// * Finite State machine to control Flash operation
// *============================================================================================== 
    /*----------------------------------------------------------------------*/
    /* power on                                                             */
    /*----------------------------------------------------------------------*/
    initial begin 
        if ( `HighV_Operation && WPb === 1 ) begin
            Chip_EN   <= #(tVSL1+tVhv+tVhv2) 1'b1;// Time delay to chip select allowed in High Voltage operation
        end
        else begin
            Chip_EN   <= #tVSL 1'b1;// Time delay to chip select allowed 
        end
    end
    
    /*----------------------------------------------------------------------*/
    /* Command Decode                                                       */
    /*----------------------------------------------------------------------*/
    assign EPSUSP   = SREG_SUS1 | SREG_SUS2 ; //ESB | PSB ;
    assign WIP      = Status_Reg[0] ;
    assign WEL      = Status_Reg[1] ;
    //assign SRWD     = Status_Reg[7] ;
    // new logic for SRWD - status register write disable bit, non-volatile
    assign SREG_SRP = VStatus_Reg[8:7];
    wire   sreg_hd_protect = !SREG_SRP[1] && SREG_SRP[0] && !WP_B_INT ;  // 0  1  0
    wire   sreg_powersupply_lock = SREG_SRP[1] && !SREG_SRP[0] ;   // 1 0 x
    wire   sreg_otp_lock = SREG_SRP[1] && SREG_SRP[0];
    assign SRWD     = sreg_hd_protect || sreg_powersupply_lock || sreg_otp_lock;
    assign SREG_QE  = VStatus_Reg[9];
    assign SREG_CMP = VStatus_Reg[14];
    assign SREG_BP  = VStatus_Reg[6:2];
    assign Dis_CE   = !((!SREG_CMP && (SREG_BP[2:0]==3'b000)) || (SREG_CMP && (SREG_BP[2:0]==3'b111))); // disable chip erase
    assign SREG_LB3  = VStatus_Reg[13];
    assign SREG_LB2  = VStatus_Reg[12];
    assign SREG_LB1  = VStatus_Reg[11];
    assign SREG_SUS1 = Status_Reg[15];
    assign SREG_SUS2 = Status_Reg[10];

    assign HPM_RD   = EN4XIO_Read_Mode == 1'b1 || EN2XIO_Read_Mode == 1'b1 ;  
    assign Norm_Array_Mode = ~(PRSCUR_Mode || ERSCUR_Mode); //Secur_Mode;
    assign Dis_WRSR = (WP_B_INT == 1'b0 && SRWD == 1'b1); // || (!Norm_Array_Mode);

    assign Low_Power_Mode = 1'b0;
    assign Pgm_Mode = PP_1XIO_Mode ||  PP_4XIO_Mode || DPP_1XIO_Mode || QPP_1XIO_Mode || PRSCUR_Mode;
    assign Ers_Mode = SE_4K_Mode || BE_Mode || ERSCUR_Mode || PE_Mode;
     
    always @ ( negedge CS_INT ) begin
        SI_IN_EN = 1'b1; 
        if ( QPI_Mode ) begin
            SO_IN_EN    = 1'b1;
            SI_IN_EN    = 1'b1;
            WP_IN_EN    = 1'b1;
            SIO3_IN_EN  = 1'b1;
        end
        if ( EN4XIO_Read_Mode == 1'b1 ) begin
            //$display( $time, " Enter READX4 Function ..." );
            Read_SHSL = 1'b1;
            STATE   <= `CMD_STATE;
            Read_4XIO_Mode = 1'b1; 
        end
        if ( EN2XIO_Read_Mode == 1'b1 ) begin
            //$display( $time, " Enter READX4 Function ..." );
            Read_SHSL = 1'b1;
            STATE   <= `CMD_STATE;
            Read_2XIO_Mode = 1'b1; 
        end


        if ( HPM_RD == 1'b0 ) begin
            Read_SHSL <= #1 1'b0;   
        end
        #1;
        tDP_Chk = 1'b0;
        tRES1_Chk = 1'b0;
    end

    always @ ( posedge ISCLK or posedge CS_INT ) begin
        #0;  
        if ( CS_INT == 1'b0 ) begin
            if ( QPI_Mode ) begin
                Bit_Tmp = Bit_Tmp + 4;
                Bit     = Bit_Tmp - 1;
            end
            else begin
              Bit_Tmp = Bit_Tmp + 1;
              Bit     = Bit_Tmp - 1;
            end
            if ( SI_IN_EN == 1'b1 && SO_IN_EN == 1'b1 && WP_IN_EN == 1'b1 && SIO3_IN_EN == 1'b1 ) begin
                SI_Reg[23:0] = {SI_Reg[19:0], SIO3, WPb, SO, SI};
            end 
            else  if ( SI_IN_EN == 1'b1 && SO_IN_EN == 1'b1 ) begin
                SI_Reg[23:0] = {SI_Reg[21:0], SO, SI};
            end
            else begin 
                SI_Reg[23:0] = {SI_Reg[22:0], SI};
            end

            //if ( (EN4XIO_Read_Mode == 1'b1 && ((Bit == 5 && !ENQUAD) || (Bit == 23 && ENQUAD))) ) begin
            //if ( (EN4XIO_Read_Mode == 1'b1 && ((Bit == 5 ) || (Bit == 23 ))) ) begin
            //if ( EN4XIO_Read_Mode == 1'b1  ) SBL_cmd = {SBL_cmd[14:0], SI};
            //if ( (EN4XIO_Read_Mode == 1'b1 && (Bit == 7 ) && SBL_cmd[7:0] == 8'h77) ) begin
            //    CMD_BUS = SBL; // This is SBL cmd instead of Address
            //    SBL_Mode = 1'b1;
            //    STATE = `CMD_STATE;
            //end

            if ( (EN4XIO_Read_Mode == 1'b1) && ((Bit == 5 && !QPI_Mode ) || (Bit == 23 && QPI_Mode))) begin
                Address = SI_Reg[A_MSB:0];
                load_address(Address);
            end  

            // 2XIO Read not supported in QPI mode
            if ( (EN2XIO_Read_Mode == 1'b1) && (Bit == 11 && !QPI_Mode)  ) begin
                Address = SI_Reg[A_MSB:0];
                load_address(Address);
            end  

            if (HPM_RD) begin
                            RSEN_SI_Reg  = {RSEN_SI_Reg[6:0], SI};  
            end

        end     
  
        if ( Bit == 7 && CS_INT == 1'b0 && ~HPM_RD ) begin
            STATE = `CMD_STATE;
            CMD_BUS = SI_Reg[7:0];
            // $display( $time,"SI_Reg[7:0]= %h ", SI_Reg[7:0] );
            if ( During_RST_REC )
                $display ($time," During reset recovery time, there is command. \n");
        end
        if ( During_RST_REC )
            $display ($time," During reset recovery time, there is command. \n");

        //if ( (EN4XIO_Read_Mode && (Bit == 1 || (ENQUAD && Bit==7))) && CS_INT == 1'b0
        if ( (EN4XIO_Read_Mode && (Bit == 1 || (Bit==7))) && CS_INT == 1'b0
             && HPM_RD && (SI_Reg[7:0]== RSTEN || SI_Reg[7:0]== RST)) begin
            CMD_BUS = SI_Reg[7:0];
            //$display( $time,"SI_Reg[7:0]= %h ", SI_Reg[7:0] );
        end
        if ( (EN2XIO_Read_Mode && (Bit == 3 || (Bit==13))) && CS_INT == 1'b0
             && HPM_RD && (SI_Reg[7:0]== RSTEN || SI_Reg[7:0]== RST)) begin
            CMD_BUS = SI_Reg[7:0];
            $display( $time,"SI_Reg[7:0]= %h ", SI_Reg[7:0] );
        end

        //if (HPM_RD && (Bit==7) && (RSEN_SI_Reg==8'hff))
        //    CMD_BUS = 8'hff;


        if ( CS_INT == 1'b1 && RST_CMD_EN &&
             //( (Bit+1)%8 == 0 || (EN4XIO_Read_Mode && !ENQUAD && (Bit+1)%2 == 0) ) ) begin
             ( (Bit+1)%8 == 0 || (EN4XIO_Read_Mode && (Bit+1)%2 == 0) ) ) begin
            RST_CMD_EN <= #1 1'b0;
        end

        if ( CS_INT == 1'b1 && ASI_Mode == 1'b1) begin
            	ASI_Mode = 1'b0;
		end

        //if ( CS_INT == 1'b1 && CMD_BUS == SBL) begin
        //    SBL_Mode = 1'b0;
        //    #1 CMD_BUS = 8'hEB;
        //end

        
        // set mode to QPI mode
        if ( CS_INT == 1'b1 ) begin
            if ( Set_QPI_Mode ) QPI_Mode = 1'b1;
            else QPI_Mode = 1'b0;
        end

        case ( STATE )
            `STANDBY_STATE: 
                begin
                end
        
            `CMD_STATE: 
                begin
                    case ( CMD_BUS ) 
                    WREN: 
                        begin
                            //if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !EPSUSP) begin
                            if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !SREG_SUS2 ) begin // change to support program in erase suspend mode
                                if ( CS_INT == 1'b1 && Bit == 7 ) begin 
                                    // $display( $time, " Enter Write Enable Function ..." );
                                    write_enable;
                                end
                                else if ( Bit > 7 )
                                    STATE <= `BAD_CMD_STATE; 
                            end 
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE; 
                        end
                     VWREN: 
                        begin
                            //if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !EPSUSP) begin
                            if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !EPSUSP) begin // change to support program in erase suspend mode
                                if ( CS_INT == 1'b1 && Bit == 7 ) begin 
                                    // $display( $time, " Enter Write Enable Function ..." );
                                    vwrite_enable_flag = 1;
                                end
                                else if ( Bit > 7 )
                                    STATE <= `BAD_CMD_STATE; 
                            end 
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE; 
                        end
                     
                    WRDI:   
                        begin
                            if ( !DP_Mode && ( !WIP || During_Susp_Wait ) && Chip_EN && ~HPM_RD ) begin
                                if ( CS_INT == 1'b1 && Bit == 7 ) begin 
                                    // $display( $time, " Enter Write Disable Function ..." );
                                    write_disable;
                                end
                                else if ( Bit > 7 )
                                    STATE <= `BAD_CMD_STATE; 
                            end 
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE; 
                        end 

                  RDID:
                      begin
                          //if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !ENQUAD ) begin
                          if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD ) begin
                              //$display( $time, " Enter Read ID Function ..." );
                               Read_SHSL = 1'b1;
                               RDID_Mode = 1'b1;
                           end
                          else if ( Bit == 7 )
                              STATE <= `BAD_CMD_STATE;
                        end

                    RUID:
                      begin
                          //if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !ENQUAD ) begin
                          if ( !DP_Mode && !WIP && !QPI_Mode && Chip_EN && ~HPM_RD && !EPSUSP && !QPI_Mode ) begin
                                Read_SHSL = 1'b1;
                                //if ( Bit == 39 ) RUID_Mode = 1'b1;
                                RUID_Mode = 1'b1;
                           end 
                           else if ( Bit == 7 )
                               STATE <= `BAD_CMD_STATE;                                
                        end

                    RDSR:
                        begin 
                            if ( !DP_Mode && Chip_EN && ~HPM_RD) begin 
                                //$display( $time, " Enter Read Status Function ..." );
                                Read_SHSL = 1'b1;
                                RDSR_Mode = 1'b1 ;
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;        
                        end

                    RDSR2:
                        begin 
                            if ( !DP_Mode && Chip_EN && ~HPM_RD) begin 
                                //$display( $time, " Enter Read Status Function ..." );
                                Read_SHSL = 1'b1;
                                RDSR2_Mode = 1'b1 ;
                            end
                            else if ( Bit == 7 ) begin
                                STATE <= `BAD_CMD_STATE; end       
                        end


                    RDCR:
                        begin
                            //if ( !DP_Mode && Chip_EN && ~HPM_RD && !EPSUSP) begin
                            if ( !DP_Mode && Chip_EN && ~HPM_RD) begin
                                //$display( $time, " Enter Read Status Function ..." );
                                Read_SHSL = 1'b1;
                                RDCR_Mode = 1'b1 ;
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;
                        end

                    WRCR:
                        begin
                            if ( !DP_Mode && !WIP && WEL && Chip_EN && ~HPM_RD && !EPSUSP ) begin
                                if ( CS_INT == 1'b1 && ( Bit == 15 ) ) begin
                                        //$display( $time, " Enter Write Control Register Function ..." ); 
                                        ->WRCR_Event;
                                        WRCR_Mode = 1'b1;
                                end    
                                else if ( CS_INT == 1'b0 && Bit > 15 )begin
                                        tWRCR_Chk = 1'b1;
                                end
                                else if ( CS_INT == 1'b1 && (Bit != 7 ) ) begin
                                    STATE <= `BAD_CMD_STATE;
				    Status_Reg[1] = 1'b0;
				    vwrite_enable_flag = 1'b0;
                                    end
                            end
                            else if ( Bit == 7 ) begin
                                STATE <= `BAD_CMD_STATE;
				Status_Reg[1] = 1'b0;
				vwrite_enable_flag = 1'b0;
                                end
                        end

 

                    WRSR:
                        begin
                            if ( !DP_Mode && !WIP && (WEL||vwrite_enable_flag) && Chip_EN && ~HPM_RD && !EPSUSP ) begin
                                if ( CS_INT == 1'b1 && ( Bit == 15 ) ) begin
                                    if ( Dis_WRSR ) begin 
                                        Status_Reg[1] = 1'b0; 
                                    end
                                    else if (CS_INT == 1'b1 && Bit == 15) begin 
                                        ->WRSR_Event;
                                        WRSR_Mode = 1'b1;
                                    end 
                                end    
                                else if ( CS_INT == 1'b0 && Bit > 7 )begin
                                        tWRSR_Chk = 1'b1;
                                end
                                else if ( CS_INT == 1'b1 && (Bit != 15 ) ) begin
                                    STATE <= `BAD_CMD_STATE;
				    Status_Reg[1] = 1'b0;
				    vwrite_enable_flag = 1'b0;
				    end
                            end
                            else if ( Bit == 15 ) begin
                                STATE <= `BAD_CMD_STATE;
				Status_Reg[1] = 1'b0;
				vwrite_enable_flag = 1'b0;
                                end
                        end

                    WRSR2:
                        begin
                            if ( !DP_Mode && !WIP && (WEL||vwrite_enable_flag) && Chip_EN && ~HPM_RD && !EPSUSP ) begin
                                if ( CS_INT == 1'b1 && ( Bit == 15 ) ) begin
                                    if ( Dis_WRSR ) begin 
                                        Status_Reg[1] = 1'b0; 
                                    end
                                    else if (CS_INT == 1'b1 && Bit == 15) begin 
                                        //$display( $time, " Enter Write Status Function ..." ); 
                                        ->WRSR2_Event;
                                        WRSR2_Mode = 1'b1;
                                    end 
                                end    
                                else if ( CS_INT == 1'b0 && Bit > 7 )begin
                                        tWRSR_Chk = 1'b1;
                                end
                                else if ( CS_INT == 1'b1 && (Bit != 15  ) ) begin
                                    STATE <= `BAD_CMD_STATE;
				    Status_Reg[1] = 1'b0;
				    vwrite_enable_flag = 1'b0;
				    end
                            end
                            else if ( Bit == 7 ) begin
                                STATE <= `BAD_CMD_STATE;
				Status_Reg[1] = 1'b0;
				vwrite_enable_flag = 1'b0;
				end
                        end


                    
                    SBL:
                        begin
                            //if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD ) begin
                            if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && SREG_QE && !QPI_Mode) begin
                                if (Bit == 7) begin
                                    SO_IN_EN = 1'b1;
                                    SIO3_IN_EN = 1'b1;
                                    WP_IN_EN = 1'b1;
                                end

                                if ( CS_INT == 1'b0 && Bit == 15 ) begin
                                   //$display( $time, " Enter Set Burst Length Function ..." );
                                    EN_Burst = !SI_Reg[4];
                                    //if ( SI_Reg[7]==1'b0 && SI_Reg[3:0]==4'b0000 ) begin
                                    if ( EN_Burst ) begin
                                        if ( SI_Reg[6:5]==2'b00 )
                                            Burst_Length = 8;
                                        else if ( SI_Reg[6:5]==2'b01 )
                                            Burst_Length = 16;
                                        else if ( SI_Reg[6:5]==2'b10 )
                                            Burst_Length = 32;
                                        else if ( SI_Reg[6:5]==2'b11 )
                                            Burst_Length = 64;
                                    end
                                    else begin
                                        Burst_Length = 8;
                                    end
                                end
                                else if ( CS_INT == 1'b1 && Bit < 15 || Bit > 15 )
                                    STATE <= `BAD_CMD_STATE;
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;
                        end

                    READ1X: 
                        begin
                            //if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !ENQUAD ) begin
                            if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !QPI_Mode) begin
                                //$display( $time, " Enter Read Data Function ..." );
                                Read_SHSL = 1'b1;
                                if ( Bit == 31 ) begin
                                    Address = SI_Reg [A_MSB:0];
                                    load_address(Address);
                                end
                                Read_1XIO_Mode = 1'b1;
                            end 
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;                                
                        end
                     
                    FASTREAD1X:
                        begin
                            if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD ) begin
                                //$display( $time, " Enter Fast Read Data Function ..." );
                                Read_SHSL = 1'b1;
                                if (( Bit == 31 && !QPI_Mode ) || ( Bit == 31 && QPI_Mode)) begin
                                    Address = SI_Reg [A_MSB:0];
                                    load_address(Address);
                                end
                                if ( QPI_Mode ) begin
                                    Read_4XIO_Mode = 1'b1;
                                    Fast4x_Mode = 1'b1;
                                end
                                else begin
                                  FastRD_1XIO_Mode = 1'b1;
                                end
                            end 
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;                                
                        end
                    PE: 
                        begin
                            if ( !DP_Mode && !WIP && WEL &&  Chip_EN && ~HPM_RD && !EPSUSP ) begin
                                if ( Bit == 31 ) begin
                                    Address = SI_Reg [A_MSB:0];
                                end
                                if ( CS_INT == 1'b1 && Bit == 31 ) begin
                                    ->PE_Event;
                                    PE_Mode = 1'b1;
                                end
                                else if ( CS_INT == 1'b1 && Bit < 31 || Bit > 31 )
                                     STATE <= `BAD_CMD_STATE;
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;
                        end


                    SE: 
                        begin
                            if ( !DP_Mode && !WIP && WEL &&  Chip_EN && ~HPM_RD && !EPSUSP ) begin
                                if ( Bit == 31 ) begin
                                    Address = SI_Reg [A_MSB:0];
                                end
                                if ( CS_INT == 1'b1 && Bit == 31 ) begin
                                    //$display( $time, " Enter Sector Erase Function ..." );
                                    ->SE_4K_Event;
                                    SE_4K_Mode = 1'b1;
                                end
                                else if ( CS_INT == 1'b1 && Bit < 31 || Bit > 31 )
                                     STATE <= `BAD_CMD_STATE;
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;
                        end

                    BE64: 
                        begin
                            if ( !DP_Mode && !WIP && WEL && Chip_EN && ~HPM_RD && !EPSUSP ) begin
                                if ( Bit == 31 ) begin
                                    Address = SI_Reg [A_MSB:0];
                                end
                                if ( CS_INT == 1'b1 && Bit == 31 ) begin
                                    //$display( $time, " Enter Block Erase Function ..." );
                                    ->BE_Event;
                                    BE_Mode = 1'b1;
                                    BE64K_Mode = 1'b1;
                                end 
                                else if ( CS_INT == 1'b1 && Bit < 31 || Bit > 31 )
                                    STATE <= `BAD_CMD_STATE;
                            end 
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;
                        end

                    BE32:
                        begin
                            if ( !DP_Mode && !WIP && WEL && Chip_EN && ~HPM_RD && !EPSUSP ) begin
                                if ( Bit == 31 ) begin
                                    Address = SI_Reg [A_MSB:0];
                                end
                                if ( CS_INT == 1'b1 && Bit == 31 ) begin
                                    //$display( $time, " Enter Block 32K Erase Function ..." );
                                    ->BE32K_Event;
                                    BE_Mode = 1'b1;
                                    BE32K_Mode = 1'b1;
                                end
                                else if ( CS_INT == 1'b1 && Bit < 31 || Bit > 31 )
                                    STATE <= `BAD_CMD_STATE;
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;
                        end

                    SUSP, SUSP1:
                        begin
                            if ( !DP_Mode && /*!Secur_Mode &&*/ Chip_EN && ~HPM_RD && !EPSUSP ) begin
                                if ( CS_INT == 1'b1 && Bit == 7 ) begin
                                    //$display( $time, " Enter Suspend Function ..." );
                                    ->Susp_Event;
                                end
                                else if ( Bit > 7 )
                                    STATE <= `BAD_CMD_STATE;
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;
                        end

                    RESU, RESU1:
                        begin
                            if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && EPSUSP ) begin
                                if ( CS_INT == 1'b1 && Bit == 7 ) begin
                                    //$display( $time, " Enter Resume Function ..." );
                                    //Secur_Mode = 1'b0;
                                    ->Resume_Event;
                                end
                                else if ( Bit > 7 )
                                    STATE <= `BAD_CMD_STATE;
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;
                        end
                      
                    CE1, CE2:
                        begin
                            if ( !DP_Mode && !WIP && WEL && Chip_EN && ~HPM_RD && !EPSUSP) begin
                                if ( CS_INT == 1'b1 && Bit == 7 ) begin
                                    //$display( $time, " Enter Chip Erase Function ..." );
                                    ->CE_Event;
                                    CE_Mode = 1'b1 ;
                                end 
                                else if ( Bit > 7 )
                                    STATE <= `BAD_CMD_STATE;
                            end
                            else if ( Bit == 7 ) 
                                STATE <= `BAD_CMD_STATE;
                        end
                      
                    PP: 
                        begin
                            //if ( !DP_Mode && !WIP && WEL && Chip_EN && ~HPM_RD && !EPSUSP) begin
                            if ( !DP_Mode && !WIP && WEL && Chip_EN && ~HPM_RD && !SREG_SUS2 ) begin  // allow program when suspended erase
                                if ( Bit == 31 ) begin
                                    Address = SI_Reg [A_MSB:0];
                                    load_address(Address);
                                end
                                if (QPI_Mode) PP_4XIO_Load = 1'b1;

                                if ( Bit == 31 && !QPI_Mode ) begin
                                    //$display( $time, " Enter Page Program Function ..." );
                                    if ( CS_INT == 1'b0 ) begin
                                        ->PP_Event;
                                        PP_1XIO_Mode = 1'b1;
                                    end  
                                end else if ( Bit == 31 && QPI_Mode ) begin
                                    if ( CS_INT == 1'b0 ) begin
                                        ->PP_Event;
                                        PP_4XIO_Mode = 1'b1;
                                        PP_4XIO_Load= 1'b1;
                                        //SO_IN_EN    = 1'b1;
                                        //SI_IN_EN    = 1'b1;
                                        //WP_IN_EN    = 1'b1;
                                        //SIO3_IN_EN  = 1'b1;
                                    end
                                end
                                else if ( CS_INT == 1 && (Bit < 31 || ((Bit + 1) % 8 !== 0)))
                                    STATE <= `BAD_CMD_STATE;
                                end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;
                        end

                   DPP: 
                        begin
                            //if ( !DP_Mode && !WIP && WEL && Chip_EN && ~HPM_RD && !EPSUSP) begin
                            if ( !DP_Mode && !WIP && WEL && Chip_EN && ~HPM_RD && !SREG_SUS2 && !QPI_Mode) begin
                                if ( Bit == 31 ) begin
                                    Address = SI_Reg [A_MSB:0];
                                    load_address(Address);
                                    SO_IN_EN    = 1'b1;
                                    SI_IN_EN    = 1'b1;
                                    SO_OUT_EN    = 1'b0;
                                    SI_OUT_EN    = 1'b0;
                                end
                                if ( Bit == 31 ) begin
                                    //$display( $time, " Enter Dual Page Program Function ..." );
                                    if ( CS_INT == 1'b0 ) begin
                                        ->PP_Event;
                                        DPP_1XIO_Mode = 1'b1;
                                    end  
                                end
                                else if ( CS_INT == 1 && (Bit < 31 || ((Bit + 1) % 8 !== 0)))
                                    STATE <= `BAD_CMD_STATE;
                                end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;
                        end

                   QPP: 
                        begin
                            //if ( !DP_Mode && !WIP && WEL && SREG_QE && Chip_EN && ~HPM_RD && !EPSUSP) begin
                            if ( !DP_Mode && !WIP && WEL && SREG_QE && Chip_EN && ~HPM_RD && !SREG_SUS2 && !QPI_Mode) begin
                                if ( Bit == 31 ) begin
                                    Address = SI_Reg [A_MSB:0];
                                    load_address(Address);
                                    SO_IN_EN    = 1'b1;
                                    SI_IN_EN    = 1'b1;
                                    WP_IN_EN    = 1'b1;
                                    SIO3_IN_EN  = 1'b1;
                                    SO_OUT_EN    = 1'b0;
                                    SI_OUT_EN    = 1'b0;
                                    WP_OUT_EN    = 1'b0;
                                    SIO3_OUT_EN  = 1'b0;
                                end
                                if ( Bit == 31 ) begin
                                    //$display( $time, " Enter Dual Page Program Function ..." );
                                    if ( CS_INT == 1'b0 ) begin
                                        ->PP_Event;
                                        QPP_1XIO_Mode = 1'b1;
                                    end  
                                end
                                else if ( CS_INT == 1 && (Bit < 31 || ((Bit + 1) % 8 !== 0)))
                                    STATE <= `BAD_CMD_STATE;
                                end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;
                        end


 

                    SFDP_READ:
                        begin
                            if ( !DP_Mode &&  !WIP && Chip_EN ) begin
                                //$display( $time, " Enter SFDP read mode ..." );
                                if ( Bit == 31 ) begin
                                    Address = SI_Reg [A_MSB:0];
                                    load_address(Address);
                                end
                                if ( Bit == 7 ) begin
                                    SFDP_Mode = 1;
                                    if ( QPI_Mode ) begin
                                        Read_4XIO_Mode = 1'b1;
                                    end
                                    else begin
                                        FastRD_1XIO_Mode = 1'b1;
                                    end
                                    Read_SHSL = 1'b1;
                                end
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;
                        end

                    DP:
                        begin
                            if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !EPSUSP ) begin
                                if ( CS_INT == 1'b1 && Bit == 7 && DP_Mode == 1'b0 ) begin
                                    //$display( $time, " Enter Deep Power Down Function ..." );
                                    tDP_Chk = 1'b1;
                                    DP_Mode = 1'b1;
                                    RDP_EN  = 1'b0;
                                    tCRDP_Check_EN  = 1'b1;
                                end
                                else if ( Bit > 7 )
                                    STATE <= `BAD_CMD_STATE;
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;
                        end

                    RES:
                        begin
                            //if ( !DP_Mode && ( !WIP || During_Susp_Wait ) && Chip_EN && ~HPM_RD ) begin
                            if ( ( !WIP || During_Susp_Wait ) && Chip_EN && ~HPM_RD ) begin
                                if (During_Enter_DP) begin
                                    if (Bit == 7 && !CS_INT) begin
                                        $display("ERROR: RES not allowed during entering deep sleep mode\n");
                                        STATE <= `BAD_CMD_STATE;
                                    end
                                end else begin
                                    RES_Mode = 1'b1;
                                    Read_SHSL = 1'b1;
                                end
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;
                        end


                    REMS:
                        begin
                            if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD ) begin
                                if ( Bit == 31 ) begin
                                    Address = SI_Reg[A_MSB:0] ;
                                end
                                //$display( $time, " Enter Read Electronic Manufacturer & ID Function ..." );
                                Read_SHSL = 1'b1;
                                REMS_Mode = 1'b1;
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;                            
                        end

                    DREMS:
                        begin
                            //if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !ENQUAD ) begin
                            if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !QPI_Mode) begin
                                if ( Bit == 19 ) begin
                                    Address = SI_Reg[7:0] ;
                                end
                                Read_SHSL = 1'b1;
                                DREMS_Mode = 1'b1;
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;                            
                        end
                        
                    QREMS:
                        begin
                            //if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && ENQUAD ) begin
                            if ( !DP_Mode && !WIP && Chip_EN && SREG_QE && ~HPM_RD && !QPI_Mode) begin
                                if ( Bit == 13 ) begin
                                    Address = SI_Reg[7:0] ;
                                end
                                if ( Bit == 15 ) begin
                                    M7_0 = SI_Reg[7:0];
                                end
                                //$display( $time, " Enter Quad Read Electronic Manufacturer & ID Function ... %x\n", Address );
                                Read_SHSL = 1'b1;
                                QREMS_Mode = 1'b1;
                            end
                            else if ( Bit == 7 ) begin
                                STATE <= `BAD_CMD_STATE;                            
                                $display("\n\t ----ERROR: QREMS not decoded -----\n");
                             end
                        end



                    READ2X: 
                        begin 
                            //if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !ENQUAD ) begin
                            if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !QPI_Mode) begin
                                //$display( $time, " Enter READX2 Function ..." );
                                Read_SHSL = 1'b1;
                                if ( Bit == 19 ) begin
                                    Address = SI_Reg [A_MSB:0];
                                    load_address(Address);
                                end
                                Read_2XIO_Mode = 1'b1;
                                READ2X_Mode = 1'b1;
                            end 
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;                                
                        end     

                    RDSCUR: 
                        begin
                            if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !QPI_Mode) begin 
                                // $display( $time, " Enter Read Secur_Register Function ..." );
                                Read_SHSL = 1'b1;
                                RDSCUR_Mode = 1'b1;
                                //Secur_Mode = 1'b1;
                                if ( Bit == 31 ) begin
                                    Address = SI_Reg [A_MSB:0];
                                    load_address(Address);
                                end
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;                                
                        end
                      
                    READ4X:
                        begin
                            //if ( !DP_Mode && !WIP && (Status_Reg[6]|ENQUAD) && Chip_EN && ~HPM_RD ) begin
                            if ( !DP_Mode && !WIP && SREG_QE && Chip_EN && ~HPM_RD ) begin
                                //$display( $time, " Enter READX4 Function ..." );
                                Read_SHSL = 1'b1;
                                if ( (Bit == 13 && !QPI_Mode) || (Bit == 31 && QPI_Mode) ) begin
                                    Address = SI_Reg [A_MSB:0];
                                    load_address(Address);
                                end
                                Read_4XIO_Mode = 1'b1;
                                READ4X_Mode    = 1'b1;
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;                            

                        end

                    WORDREAD:  // word boundary read, must report error if addr[0] not correct, continue execute
                        begin
                            if ( !DP_Mode && !WIP && SREG_QE && !QPI_Mode && Chip_EN && ~HPM_RD && !EPSUSP) begin
                                Read_SHSL = 1'b1;
                                if ( Bit == 13 ) begin
                                    Address = SI_Reg [A_MSB:0];
                                    load_address(Address);
                                    if (Address[0] != 0) $display("!Error: Word Read 8'hE7 - The Address[0] must be 0, while %x set\n", Address);
                                end
                                Read_4XIO_Mode = 1'b1;
                                READ4X_Mode    = 1'b1;
                                WordRead_Mode  = 1'b1;
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;                            
                        end

                    OCTALREAD: // octal boundary read, must report error if addr[0] not correct, continue execute
                        begin
                            if ( !DP_Mode && !WIP && SREG_QE && !QPI_Mode && Chip_EN && ~HPM_RD && !EPSUSP) begin
                                Read_SHSL = 1'b1;
                                if ( Bit == 13 ) begin
                                    Address = SI_Reg [A_MSB:0];
                                    load_address(Address);
                                    if (Address[3:0] != 4'b0000) 
                                        $display("!Error: Octal Read 8'hE3 - The Address[3:0] must be 0, while %x set\n", Address);
                                end
                                Read_4XIO_Mode = 1'b1;
                                READ4X_Mode    = 1'b1;
                                OctalRead_Mode  = 1'b1;
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;                            
                        end

                    DREAD:
                        begin
                            //if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !ENQUAD ) begin
                            if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !QPI_Mode) begin
                                //$display( $time, " Enter Fast Read dual output Function ..." );
                                Read_SHSL = 1'b1;
                                if ( Bit == 31 ) begin
                                    Address = SI_Reg [A_MSB:0];
                                    load_address(Address);
                                end
                                FastRD_2XIO_Mode =1'b1;
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;                            
                        end

                    QREAD:
                        begin
                            //if ( !DP_Mode && !WIP && Status_Reg[6] && Chip_EN && ~HPM_RD && !ENQUAD ) begin
                            if ( !DP_Mode && !WIP && SREG_QE && Chip_EN && ~HPM_RD && !QPI_Mode) begin
                                //$display( $time, " Enter Fast Read quad output Function ..." );
                                Read_SHSL = 1'b1;
                                if ( Bit == 31 ) begin
                                    Address = SI_Reg[A_MSB:0] ;
                                    load_address(Address);
                                end
                                FastRD_4XIO_Mode =1'b1;
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;
                        end

                    PRSCUR: 
                        begin
                            if ( !DP_Mode && !WIP && WEL && Chip_EN && ~HPM_RD && !EPSUSP && !QPI_Mode) begin
                                if ( Bit == 31 ) begin
                                    Address = SI_Reg [A_MSB:0];
                                end

                                if ( Bit == 31 ) begin
                                    //$display( $time, " Enter OTP Program Function ..." );
                                    if ( CS_INT == 1'b0 && (Address[A_MSB:12] == 1 || Address[A_MSB:12] == 2 || Address[A_MSB:12] == 3)) begin
                                        ->PRSCUR_Event;
                                        //Secur_Mode = 1'b1;
                                        PRSCUR_Mode = 1'b1;
                                    end  
                                end
                                else if ( CS_INT == 1 && (Bit < 31 || ((Bit + 1) % 8 !== 0))) begin
                                    STATE <= `BAD_CMD_STATE;
				    Status_Reg[1] = 1'b0;
				    end
                                end
                            else if ( Bit == 7 ) begin
                                STATE <= `BAD_CMD_STATE;
				Status_Reg[1] = 1'b0;
				end
                        end

                    ERSCUR: 
                        begin
                            if ( !DP_Mode && !WIP && WEL && Chip_EN && ~HPM_RD && !EPSUSP && !QPI_Mode) begin
                                if ( Bit == 31 ) begin
                                    Address = SI_Reg [A_MSB:0];
                                    load_address(Address);
                                end

                                if ( Bit == 31 ) begin
                                    //$display( $time, " Enter OTP Erase Function ..." );
                                    if ( CS_INT == 1'b0 ) begin
                                        ->ERSCUR_Event;
                                        //Secur_Mode = 1'b1;
                                        ERSCUR_Mode = 1'b1;
                                    end  
                                end
                                else if ( CS_INT == 1 && (Bit < 31 || Bit > 31))
                                    STATE <= `BAD_CMD_STATE;
                                end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;
                        end

                    RSTEN:
                        begin
                            if ( !DP_Mode && Chip_EN ) begin
                                if ( CS_INT == 1'b1 && (Bit == 7 || (EN4XIO_Read_Mode && Bit == 1)) ) begin
                                    //$display( $time, " Reset enable ..." );
                                    ->RST_EN_Event;
                                end
                                else if ( Bit > 7 )
                                    STATE <= `BAD_CMD_STATE;
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;
                        end

                    RST:
                        begin
                            if ( !DP_Mode && Chip_EN && RST_CMD_EN ) begin
                                if ( CS_INT == 1'b1 && (Bit == 7 || (EN4XIO_Read_Mode && Bit == 1)) ) begin
                                    //$display( $time, " Reset memory ..." );
                                    ->RST_Event;
                                end
                                else if ( Bit > 7 )
                                    STATE <= `BAD_CMD_STATE;
                            end
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;
                        end

                    ASI:  // new cmd, active status interrupt
                        begin
                            if ( !CS_INT && !DP_Mode && Chip_EN && !HPM_RD && !QPI_Mode) begin
                                ASI_Mode = 1'b1;
                            end
                        end

                    ENQPI:
                        begin
                            if ( !DP_Mode && !WIP && Chip_EN && !HPM_RD && SREG_QE && !QPI_Mode && !EPSUSP) begin 
                                if ( Bit == 7 ) begin
                                    Set_QPI_Mode = 1'b1;
                                end
                                else if ( Bit > 7 )
                                    STATE <= `BAD_CMD_STATE;
                            end
                            else if  ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE;
                        end

                    RSEN|DISQPI:
                        begin
                            if ( QPI_Mode ) begin
                                if ( !DP_Mode && !WIP && Chip_EN && !HPM_RD  && !EPSUSP) begin 
                                    if ( Bit == 7 ) begin
                                        Set_QPI_Mode = 1'b0;
                                    end
                                    else if ( Bit > 7 )
                                        STATE <= `BAD_CMD_STATE;
                                end
                                else if ( Bit == 7 ) STATE <= `BAD_CMD_STATE;
                            end
                            else begin
                                if ( !DP_Mode && !WIP && Chip_EN && !EPSUSP) begin
                                    if ( Bit == 7 ) begin
                                        Set_4XIO_Enhance_Mode = 1'b0;
                                        Set_2XIO_Enhance_Mode = 1'b0;
                                    end
                                    else if ( Bit > 7 )
                                        STATE <= `BAD_CMD_STATE;
                                end
                                else if ( Bit == 7 ) STATE <= `BAD_CMD_STATE;
                            end
                        end

                    SETRDPA:  // hc0 set read dummy and wrap for FastRead(h0b), QIO_FastRead(heb), BurstReadWrap(h0c)
                        begin
                            if ( !DP_Mode && !WIP && Chip_EN && !HPM_RD && QPI_Mode && !EPSUSP) begin 
                                    if (Bit == 15) begin
                                         Param_dummy_clock = SI_Reg[5:4];
                                         Param_wrap_length = SI_Reg[1:0];
                                    end
                                    else if (Bit > 15) 
                                         STATE <= `BAD_CMD_STATE;
                            end
                            else if (Bit == 7)
                                STATE <= `BAD_CMD_STATE;
                        end
                    BURSTRD: // h0c
                        begin
                            if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && QPI_Mode && !EPSUSP) begin 
                                Read_SHSL = 1'b1;
                                if ( Bit == 31 ) begin
                                    Address = SI_Reg [A_MSB:0];
                                    load_address(Address);
                                end
                                Read_4XIO_Mode = 1'b1;
                                READ4X_Mode    = 1'b1;
                                BurstRead_Mode = 1'b1;
                            end
                            else if (Bit == 7) 
                                STATE <= `BAD_CMD_STATE;
                        end

                    SBLK: 
                        begin
                            if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !EPSUSP) begin 
                                if ( CS_INT == 1'b1 && Bit == 31 ) begin 
                                    if (CR_WPS == 1'b1) begin
                                        Address = SI_Reg [A_MSB:0];
                                        single_block_lock;
                                    end
                                    else 
                                        $display("!ERROR: WPS=0, individual block lock cmd not executed at time %t\n", $realtime);
                                end
                                else if ( Bit > 31 )
                                    STATE <= `BAD_CMD_STATE; 
                            end 
                            else if ( Bit == 31 )
                                STATE <= `BAD_CMD_STATE; 
                        end

                    SBULK: 
                        begin
                            if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !EPSUSP) begin 
                                if ( CS_INT == 1'b1 && Bit == 31 ) begin 
                                    if (CR_WPS == 1'b1) begin
                                        Address = SI_Reg [A_MSB:0];
                                        single_block_unlock;
                                    end
                                    else
                                        $display("!ERROR: WPS=0, individual block unlock cmd not executed at time %t\n", $realtime);
                                end
                                else if ( Bit > 31 )
                                    STATE <= `BAD_CMD_STATE; 
                            end 
                            else if ( Bit == 31 )
                                STATE <= `BAD_CMD_STATE; 
                        end
                    GBLK: 
                        begin
                            if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !EPSUSP) begin 
                                if ( CS_INT == 1'b1 && Bit == 7 ) begin 
                                    if (CR_WPS == 1'b1) begin
                                        global_block_lock;
                                    end
                                    else
                                        $display("!ERROR: WPS=0, global block lock cmd not executed at time %t\n", $realtime);
                                end
                                else if ( Bit > 7 )
                                    STATE <= `BAD_CMD_STATE; 
                            end 
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE; 
                        end

                    GBULK: 
                        begin
                            if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !EPSUSP) begin 
                                if ( CS_INT == 1'b1 && Bit == 7 ) begin 
                                    if (CR_WPS == 1'b1)
                                        global_block_unlock;
                                    else
                                        $display("!ERROR: WPS=0, global block lock cmd not executed at time %t\n", $realtime);
                                end
                                else if ( Bit > 7 )
                                    STATE <= `BAD_CMD_STATE; 
                            end 
                            else if ( Bit == 7 )
                                STATE <= `BAD_CMD_STATE; 
                        end

                    RDBLOCK, RDBLOCK2: 
                        begin
                            if ( !DP_Mode && !WIP && Chip_EN && ~HPM_RD && !EPSUSP) begin 
                                if ( CS_INT == 1'b0 && Bit == 31 ) begin 
                                    Address = SI_Reg [A_MSB:0];
                                    read_block_lock;
                                    if (CR_WPS == 1'b0)
                                        $display("!ERROR: WPS=0, read block lock cmd is not correct at time %t\n", $realtime);
                                end
                    //            else if ( Bit > 31 )
                    //                STATE <= `BAD_CMD_STATE; 
                            end 
                            else if ( Bit == 31 )
                                STATE <= `BAD_CMD_STATE; 
                        end

                    NOP:
                        begin
                        end

                    default: 
                        begin
                            STATE <= `BAD_CMD_STATE;
                        end
                    endcase
                end
                 
            `BAD_CMD_STATE: 
                begin
                    if (EPSUSP)
                    $display("\n\t------ ERROR: %x not decoded while in suspend mode\n", CMD_BUS);
                end
            
            default: 
                begin
                STATE =  `STANDBY_STATE;
                end
        endcase

    end

    always @ (posedge CS_INT) begin
            SIO0_Reg <= #tSHQZ 1'bx;
            SIO1_Reg <= #tSHQZ 1'bx;
            SIO2_Reg <= #tSHQZ 1'bx;
            SIO3_Reg <= #tSHQZ 1'bx;

            SIO0_Out_Reg <= #tSHQZ 1'bx;
            SIO1_Out_Reg <= #tSHQZ 1'bx;
            SIO2_Out_Reg <= #tSHQZ 1'bx;
            SIO3_Out_Reg <= #tSHQZ 1'bx;
           
            SO_OUT_EN    <= #tSHQZ 1'b0;
            SI_OUT_EN    <= #tSHQZ 1'b0;
            WP_OUT_EN    <= #tSHQZ 1'b0;
            SIO3_OUT_EN  <= #tSHQZ 1'b0;

            #1;
            Bit         = 1'b0;
            Bit_Tmp     = 1'b0;
           
            SO_IN_EN    = 1'b0;
            SI_IN_EN    = 1'b0;
            WP_IN_EN    = 1'b0;
            SIO3_IN_EN  = 1'b0;

            tWRSR_Chk   = 1'b0;
            tWRCR_Chk   = 1'b0;

            WordRead_Mode  = 1'b0;
            OctalRead_Mode  = 1'b0;
            RDID_Mode   = 1'b0;
            RUID_Mode   = 1'b0;
            RDSR_Mode   = 1'b0;
            RDSR2_Mode   = 1'b0;
            RDCR_Mode   = 1'b0;
            RDSCUR_Mode = 1'b0;
            //ERSCUR_Mode = 1'b0;
            //PRSCUR_Mode = 1'b0;
            Read_Mode   = 1'b0;
            RES_Mode    = 1'b0;
            REMS_Mode   = 1'b0;
            DREMS_Mode   = 1'b0;
            QREMS_Mode   = 1'b0;
            SFDP_Mode    = 1'b0;
            Read_1XIO_Mode  = 1'b0;
            Read_2XIO_Mode  = 1'b0;
            Read_4XIO_Mode  = 1'b0;
            BurstRead_Mode  = 1'b0;
            Read_1XIO_Chk   = 1'b0;
            Read_2XIO_Chk   = 1'b0;
            Read_4XIO_Chk   = 1'b0;
            FastRD_2XIO_Chk= 1'b0;
            FastRD_4XIO_Chk= 1'b0;
            FastRD_1XIO_Mode= 1'b0;
            FastRD_2XIO_Mode= 1'b0;
            FastRD_4XIO_Mode= 1'b0;
            PP_4XIO_Load    = 1'b0;
            PP_4XIO_Chk     = 1'b0;
            DPP_1XIO_Chk     = 1'b0;
            DPP_1XIO_Load    = 1'b0;
            STATE <=  `STANDBY_STATE;

            disable read_id;
            disable read_status;
            disable read_status_2;
            disable read_cr;
            disable read_Secur_Register;
            disable read_1xio;
            disable read_2xio;
            disable read_4xio;
            disable fastread_1xio;
            disable fastread_2xio;
            disable fastread_4xio;
            disable read_electronic_id;
            disable read_electronic_manufacturer_device_id;
            disable read_function;
            disable dummy_cycle;
        end

    always @ (posedge CS_INT) begin 

        if ( Set_4XIO_Enhance_Mode) begin
            EN4XIO_Read_Mode = 1'b1;
        end
        else if ( Set_2XIO_Enhance_Mode) begin
            EN2XIO_Read_Mode = 1'b1;
        end
        else begin
            EN4XIO_Read_Mode = 1'b0;
            EN2XIO_Read_Mode = 1'b0;
            W4Read_Mode      = 1'b0;
            Fast4x_Mode      = 1'b0;
            READ4X_Mode      = 1'b0;
            READ2X_Mode      = 1'b0;
        end
    end 


// *==============================================================================================
// * Release from Deep Power-down description
// * ============================================================================================
    realtime T_CS_S, T_CS_E;

    //always @ (negedge CS_INT) begin:release_from_dp 
    //always @ (posedge CS_INT or RES_Mode) begin:release_from_dp 
    always @ (posedge CS_INT ) begin:release_from_dp 
        if(DP_Mode && RES_Mode && !During_Enter_DP) begin
                $display("RElease from dp mode detected\n");
                if( RDP_EN == 0 )begin
                    wait( RDP_EN );
                end
                #tRDP;
                DP_Mode = 0;
        end 
    end

    
    always @(posedge DP_Mode ) begin: disable_release_from_dp_cmd
        During_Enter_DP = 1'b1;
        #tDP;
        During_Enter_DP = 1'b0;
    end
    //always @ (posedge CS_INT) begin 
    //    if(DP_Mode && tCRDP_Check_EN) begin
    //        T_CS_E = $realtime;
    //        if( T_CS_E - T_CS_S < tCRDP ) begin
    //            disable release_from_dp;
    //        end
    //        else begin
    //            tCRDP_Check_EN = 0;
    //        end
    //    end
    //end 

    always @ (negedge RDP_EN) begin
        RDP_EN <= #tDPDD 1;
    end

    always @ (posedge CS_INT) begin 
        if (STATE == `BAD_CMD_STATE) 
            $display("!!!ERROR: CMD %x not decoded\n", CMD_BUS);
    end
    /*----------------------------------------------------------------------*/
    /*  ALL function trig action                                            */
    /*----------------------------------------------------------------------*/
    always @ ( posedge Read_1XIO_Mode
            or posedge FastRD_1XIO_Mode
            or posedge REMS_Mode
            or posedge DREMS_Mode
            or posedge QREMS_Mode
            or posedge RES_Mode
            or posedge Read_2XIO_Mode
            or posedge Read_4XIO_Mode 
            or posedge PP_4XIO_Load 
            or posedge DPP_1XIO_Load 
            or posedge FastRD_2XIO_Mode
            or posedge FastRD_4XIO_Mode
            or posedge RDSCUR_Mode
           ) begin:read_function 
        wait ( ISCLK == 1'b0 );
        if ( Read_1XIO_Mode == 1'b1  )  begin
            Read_1XIO_Chk = 1'b1;
            read_1xio;
        end
        else if ( RDSCUR_Mode == 1'b1 ) begin
            read_Secur_Register;
        end
        else if ( FastRD_1XIO_Mode == 1'b1 ) begin
            fastread_1xio;
        end
        else if ( FastRD_2XIO_Mode == 1'b1 ) begin
            fastread_2xio;
            FastRD_2XIO_Chk = 1'b1;
        end
        else if ( FastRD_4XIO_Mode == 1'b1 ) begin
            FastRD_4XIO_Chk = 1'b1;
            fastread_4xio;
        end   
        else if ( REMS_Mode == 1'b1 ) begin
            read_electronic_manufacturer_device_id;
        end 
        else if ( DREMS_Mode == 1'b1 ) begin
            dual_read_electronic_manufacturer_device_id;
        end 
        else if ( QREMS_Mode == 1'b1 ) begin
            quad_read_electronic_manufacturer_device_id;
        end 
        else if ( RES_Mode == 1'b1 ) begin
            read_electronic_id;
        end
        else if ( Read_2XIO_Mode == 1'b1 ) begin
            Read_2XIO_Chk = 1'b1;
            read_2xio;
        end
        else if ( Read_4XIO_Mode == 1'b1 ) begin
            Read_4XIO_Chk = 1'b1;
            read_4xio;
        end
        else if ( PP_4XIO_Load == 1'b1 ) begin
            PP_4XIO_Chk = 1'b1;
        end
        else if ( DPP_1XIO_Load == 1'b1 ) begin
            DPP_1XIO_Chk = 1'b1;
        end
    end 

    always @ ( RST_EN_Event ) begin
        RST_CMD_EN = #2 1'b1;
    end
    
    always @ ( RST_Event ) begin
        During_RST_REC = 1;
        if ( WRSR_Mode || WRSR2_Mode ) begin
            #(tREADY2_W);
        end
        else if ( WRCR_Mode ) begin
            #(tREADY2_W);
        end
        else if (  PP_4XIO_Mode  || PP_1XIO_Mode  || DPP_1XIO_Mode || QPP_1XIO_Mode || PRSCUR_Mode ) begin
            #(tREADY2_P);
        end
        else if ( SE_4K_Mode ) begin
            #(tREADY2_SE);
        end
        else if (PE_Mode ) begin
            #(tREADY2_P); 
        end
        else if ( BE64K_Mode || BE32K_Mode ) begin
            #(tREADY2_BE);
        end
        else if ( CE_Mode ) begin
            #(tREADY2_CE);
        end
        else if ( Read_SHSL == 1'b1 ) begin
            #(tREADY2_R);
        end
        else begin
            #(tREADY2_D);
        end

        disable write_status;
        disable write_status_2;
        disable block_erase;
        disable block_erase_32k;
        disable sector_erase_4k;
        disable page_erase;
        disable chip_erase;
        disable page_program; // can deleted
        disable otp_program; // can deleted
        disable update_array;
        disable update_otp_array;
        disable read_Secur_Register;
        disable erase_secur_register;
        disable read_id;
        disable read_status;
        disable read_status_2;
        disable read_cr;
        disable suspend_write;
        disable resume_write;
        disable er_timer;
        disable pg_timer;
        disable stimeout_cnt;
        disable rtimeout_cnt;

        disable read_1xio;
        disable read_2xio;
        disable read_4xio;
        disable fastread_1xio;
        disable fastread_2xio;
        disable fastread_4xio;
        disable read_electronic_id;
        disable read_electronic_manufacturer_device_id;
        disable dual_read_electronic_manufacturer_device_id;
        disable quad_read_electronic_manufacturer_device_id;
        disable read_function;
        disable dummy_cycle;
        disable single_block_lock;
        disable single_block_unlock;
        disable global_block_lock;
        disable global_block_unlock;
        disable read_block_lock;

        reset_sm;
        READ4X_Mode = 1'b0;
        READ2X_Mode = 1'b0;
        Status_Reg[1:0] = 2'b0;
    end
// *==============================================================================================
// * Hardware Reset Function description
// * ============================================================================================
    always @ ( negedge RESETB_INT ) begin
        if (RESETB_INT == 1'b0) begin
            disable hd_reset;
            #1;
            -> HDRST_Event;
        end
    end

      always @ ( HDRST_Event ) begin: hd_reset
          if (RESETB_INT == 1'b0) begin
              During_RST_REC = 1;
              if ( WRSR_Mode || WRSR2_Mode ) begin
                  #(tREADY2_W);
              end
              else if ( WRCR_Mode ) begin
                  #(tREADY2_W);
              end
              else if (  PP_4XIO_Mode  || PP_1XIO_Mode  || DPP_1XIO_Mode || QPP_1XIO_Mode || PRSCUR_Mode ) begin
                  #(tREADY2_P);
              end
              else if ( SE_4K_Mode ) begin
                  #(tREADY2_SE);
              end
              else if (PE_Mode ) begin
                  #(tREADY2_P); 
              end
              else if ( BE64K_Mode || BE32K_Mode ) begin
                  #(tREADY2_BE);
              end
              else if ( CE_Mode ) begin
                  #(tREADY2_CE);
              end
              else if ( Read_SHSL == 1'b1 ) begin
                  #(tREADY2_R);
              end
              else begin
                  #(tREADY2_D);
              end

              disable write_status;
              disable write_status_2;
              disable block_erase;
              disable block_erase_32k;
              disable sector_erase_4k;
              disable page_erase;
              disable chip_erase;
              disable page_program; // can deleted
              disable otp_program; // can deleted
              disable update_array;
              disable update_otp_array;
              disable read_Secur_Register;
              disable erase_secur_register;
              disable read_id;
              disable read_status;
              disable read_status_2;
              disable read_cr;
              disable suspend_write;
              disable resume_write;
              disable er_timer;
              disable pg_timer;
              disable stimeout_cnt;
              disable rtimeout_cnt;

              disable read_1xio;
              disable read_2xio;
              disable read_4xio;
              disable fastread_1xio;
              disable fastread_2xio;
              disable fastread_4xio;
              disable read_electronic_id;
              disable read_electronic_manufacturer_device_id;
              disable dual_read_electronic_manufacturer_device_id;
              disable quad_read_electronic_manufacturer_device_id;
              disable read_function;
              disable dummy_cycle;
              disable single_block_lock;
              disable single_block_unlock;
              disable global_block_lock;
              disable global_block_unlock;
              disable read_block_lock;


              reset_sm;
              READ4X_Mode = 1'b0;
              READ2X_Mode = 1'b0;
              Status_Reg[1:0] = 2'b0;
         end
    end
  

    always @ ( posedge Susp_Trig ) begin:stimeout_cnt
        Susp_Trig <= #1 1'b0;
    end

    always @ ( posedge Resume_Trig ) begin:rtimeout_cnt
        Resume_Trig <= #1 1'b0;
    end

    always @ ( posedge W4Read_Mode or posedge Fast4x_Mode ) begin
        READ4X_Mode = 1'b0;
    end

    always @ ( WRSR_Event ) begin
        write_status;
    end

    always @ ( WRSR2_Event ) begin
        write_status_2;
    end

    always @ ( WRCR_Event ) begin
        write_control;
    end

    always @ ( BE_Event ) begin
        block_erase;
    end

    always @ ( BE32K_Event ) begin
        block_erase_32k;
    end

    always @ ( CE_Event ) begin
        chip_erase;
    end
    
    always @ ( PP_Event ) begin:page_program_mode
        page_program( Address );
    end

    always @ ( PRSCUR_Event ) begin: program_otp
        otp_program( Address );
    end
   
    always @ ( SE_4K_Event ) begin
        sector_erase_4k;
    end
    always @ ( PE_Event ) begin
        page_erase;
    end

    always @ ( posedge RDID_Mode ) begin
        read_id;
    end
    always @ ( posedge RUID_Mode ) begin
        read_uuid;
    end

    always @ ( posedge RDSR_Mode ) begin
        read_status;
    end

    always @ ( posedge RDSR2_Mode ) begin
        read_status_2;
    end

    always @ ( posedge RDCR_Mode ) begin
        read_cr;
    end

    always @ ( ERSCUR_Event ) begin
        erase_secur_register;
    end

    always @ ( Susp_Event ) begin
        suspend_write;
    end

    always @ ( Resume_Event ) begin
        resume_write;
    end


// *========================================================================================== 
// * Module Task Declaration
// *========================================================================================== 

    /*----------------------------------------------------------------------*/
    /*  Description: define a wait dummy cycle task                         */
    /*  INPUT                                                               */
    /*      Cnum: cycle number                                              */
    /*----------------------------------------------------------------------*/
    task dummy_cycle;
        input [31:0] Cnum;
        begin
            repeat( Cnum ) begin
                @ ( posedge ISCLK );
            end
        end
    endtask // dummy_cycle

    /*----------------------------------------------------------------------*/
    /*  Description: define a write enable task                             */
    /*----------------------------------------------------------------------*/
    task write_enable;
        begin
            //$display( $time, " Old Status Register = %b", Status_Reg );
            Status_Reg[1] = 1'b1; 
            // $display( $time, " New Status Register = %b", Status_Reg );
        end
    endtask // write_enable
    
    /*----------------------------------------------------------------------*/
    /*  Description: define a write disable task (WRDI)                     */
    /*----------------------------------------------------------------------*/
    task write_disable;
        begin
            //$display( $time, " Old Status Register = %b", Status_Reg );
            Status_Reg[1]  = 1'b0;
            //$display( $time, " New Status Register = %b", Status_Reg );
        end
    endtask // write_disable

    
    /*----------------------------------------------------------------------*/
    /*  Description: define a read id task (RDID)                           */
    /*----------------------------------------------------------------------*/
    task read_id;
        reg  [23:0] Dummy_ID;
        integer Dummy_Count;
        begin
            Dummy_ID    = {ID_PUYA, Memory_Type, Memory_Density};
            Dummy_Count = 0;
            forever begin
                @ ( negedge ISCLK or posedge CS_INT );
                if ( CS_INT == 1'b1 ) begin
                    disable read_id;
                end
                else begin
                     SO_OUT_EN = 1'b1;
                     SO_IN_EN  = 1'b0;
                     SI_IN_EN  = 1'b0;
                     WP_IN_EN  = 1'b0;
                     SIO3_IN_EN= 1'b0;
                    if ( QPI_Mode ) begin
                        SI_OUT_EN    = 1'b1;
                        WP_OUT_EN    = 1'b1;
                        SIO3_OUT_EN  = 1'b1;
                        {SIO3_Reg, SIO2_Reg, SIO1_Reg, SIO0_Reg, Dummy_ID} <= {Dummy_ID, Dummy_ID[23:20]};
                    end else begin
                        {SIO1_Reg, Dummy_ID} <= {Dummy_ID, Dummy_ID[23]};
                    end
                end
            end  // end forever
        end
    endtask // read_id

    /*----------------------------------------------------------------------*/
    /*  Description: define a read id task (RUID)                           */
    /*----------------------------------------------------------------------*/
    task read_uuid;
        reg  [127:0] Dummy_ID;
        integer Dummy_Count;
        begin
            dummy_cycle(32);
            Dummy_ID    = `UUID;
            forever begin
                @ ( negedge ISCLK or posedge CS_INT );
                if ( CS_INT == 1'b1 ) begin
                    disable read_uuid;
                end
                else begin
                    SO_OUT_EN = 1'b1;
                    SO_IN_EN  = 1'b0;
                    SI_IN_EN  = 1'b0;
                    WP_IN_EN  = 1'b0;
                    SIO3_IN_EN= 1'b0;
                    {SIO1_Reg, Dummy_ID} <= {Dummy_ID, Dummy_ID[127]};
                end
            end  // end forever
        end
    endtask // read_uuid

   
    /*----------------------------------------------------------------------*/
    /*  Description: define a read status task (RDSR)                       */
    /*               05        s7~0                                         */
    /*----------------------------------------------------------------------*/
    task read_status;
        reg [7:0] Status_Reg_Int;
        integer Dummy_Count;
        begin
            //Status_Reg_Int = {VStatus_Reg[7:2],Status_Reg[1:0], Status_Reg[15], VStatus_Reg[14:11], Status_Reg[10], VStatus_Reg[9:8]};
            Status_Reg_Int = {VStatus_Reg[7:2],Status_Reg[1:0]};
            if ( QPI_Mode ) 
                 Dummy_Count = 2;
            else Dummy_Count = 8;
            forever begin
                @ ( negedge ISCLK or posedge CS_INT );
                if ( CS_INT == 1'b1 ) begin
                    disable read_status;
                end
                else begin
                    if ( QPI_Mode ) begin
                        SI_OUT_EN   = 1'b1;
                        WP_OUT_EN   = 1'b1;
                        SIO3_OUT_EN = 1'b1;
                    end
                    SO_OUT_EN = 1'b1;
                    SO_IN_EN  = 1'b0;
                    SI_IN_EN  = 1'b0;
                    WP_IN_EN  = 1'b0;
                    SIO3_IN_EN= 1'b0;

                    if ( Dummy_Count ) begin
                        Dummy_Count = Dummy_Count - 1;
                        if (QPI_Mode) begin
                            {SIO3_Reg, SIO2_Reg, SIO1_Reg, SIO0_Reg} <= Dummy_Count ?  
                                                          Status_Reg_Int[7:4] : Status_Reg_Int[3:0];
                        end else
                            SIO1_Reg    <= Status_Reg_Int[Dummy_Count];
                    end
                    else begin
                        Status_Reg_Int = {VStatus_Reg[7:2], Status_Reg[1:0]};
                        if ( QPI_Mode ) begin
                            Dummy_Count = 1;
                            {SIO3_Reg, SIO2_Reg, SIO1_Reg, SIO0_Reg} <= Status_Reg_Int[7:4];
                        end else begin
                            Dummy_Count = 7;
                            SIO1_Reg    <= Status_Reg_Int[Dummy_Count];
                        end
                    end          
                end
            end  // end forever
        end
    endtask // read_status
   
    /*----------------------------------------------------------------------*/
    /*  Description: define a read status task (RDSR2)                      */
    /*               35  s15~8                                              */
    /*----------------------------------------------------------------------*/
    task read_status_2;
        reg [7:0] Status_Reg_Int;
        integer Dummy_Count;
        begin
            //Status_Reg_Int = { Status_Reg[15], VStatus_Reg[14:11], Status_Reg[10], VStatus_Reg[9:8], VStatus_Reg[7:2],Status_Reg[1:0]};
            Status_Reg_Int = { Status_Reg[15], VStatus_Reg[14:11], Status_Reg[10], VStatus_Reg[9:8]};
            if ( QPI_Mode ) 
                Dummy_Count = 2;
            else  Dummy_Count = 8;
            forever begin
                @ ( negedge ISCLK or posedge CS_INT );
                if ( CS_INT == 1'b1 ) begin
                    disable read_status_2;
                end
                else begin
                    if ( QPI_Mode ) begin
                        SI_OUT_EN   = 1'b1;
                        WP_OUT_EN   = 1'b1;
                        SIO3_OUT_EN = 1'b1;
                    end
                    SO_OUT_EN = 1'b1;
                    SO_IN_EN  = 1'b0;
                    SI_IN_EN  = 1'b0;
                    WP_IN_EN  = 1'b0;
                    SIO3_IN_EN= 1'b0;
                    if ( Dummy_Count ) begin
                        Dummy_Count = Dummy_Count - 1;
                        if (QPI_Mode) begin
                            {SIO3_Reg, SIO2_Reg, SIO1_Reg, SIO0_Reg} <= Dummy_Count ?
                                                          Status_Reg_Int[7:4] : Status_Reg_Int[3:0];
                        end else
                            SIO1_Reg    <= Status_Reg_Int[Dummy_Count];
                    end
                    else begin
                        Status_Reg_Int = { Status_Reg[15], VStatus_Reg[14:11], Status_Reg[10], VStatus_Reg[9:8]};
                        if ( QPI_Mode ) begin
                            Dummy_Count = 1;
                            {SIO3_Reg, SIO2_Reg, SIO1_Reg, SIO0_Reg} <= Status_Reg_Int[7:4];
                        end else begin
                            Dummy_Count = 7;
                            SIO1_Reg    <= Status_Reg_Int[Dummy_Count];
                        end
                    end          
                end
            end  // end forever
        end
    endtask // read_status_2


    /*----------------------------------------------------------------------*/
    /*  Description: define a read configuration register task (RDCR)       */
    /*----------------------------------------------------------------------*/
    task read_cr;
        integer Dummy_Count;
        reg[7:0] CR;
        begin
            CR = Control_Reg;
            if ( QPI_Mode ) 
                Dummy_Count = 2;
            else 
                Dummy_Count = 8;
            forever begin
                @ ( negedge ISCLK or posedge CS_INT );
                if ( CS_INT == 1'b1 ) begin
                    disable read_cr;
                end
                else begin
                    if ( QPI_Mode ) begin
                        SI_OUT_EN  = 1'b1;
                        WP_OUT_EN  = 1'b1;
                        SIO3_OUT_EN= 1'b1;
                    end
                    SO_OUT_EN = 1'b1;
                    SO_IN_EN  = 1'b0;
                    SI_IN_EN  = 1'b0;
                    WP_IN_EN  = 1'b0;
                    SIO3_IN_EN= 1'b0;
                    if ( Dummy_Count ) begin
                        Dummy_Count = Dummy_Count - 1;
                        if ( QPI_Mode ) begin
                            {SIO3_Reg, SIO2_Reg, SIO1_Reg, SIO0_Reg} <= Dummy_Count  ? CR[7:4] : CR[3:0];
                        end else
                            SIO1_Reg    <= CR[Dummy_Count];
                    end
                    else begin
                        if ( QPI_Mode ) begin
                            Dummy_Count = 1;
                            {SIO3_Reg, SIO2_Reg, SIO1_Reg, SIO0_Reg} <= CR[7:4];
                        end else begin
                            Dummy_Count = 7;
                            SIO1_Reg    <= CR[Dummy_Count];
                        end
                    end          
                end
            end  // end forever
        end
    endtask // read_cr

    /*----------------------------------------------------------------------*/
    /*  Description: define a write status task                             */
    /*               01 S7-0                                                */
    /*----------------------------------------------------------------------*/
    task write_status;
    reg [7:0] Status_Reg_Up;
        begin
          //$display( $time, " Old Status Register = %b", Status_Reg );
          if (vwrite_enable_flag == 0) begin
              if (WRSR_Mode == 1'b1) begin
                Status_Reg_Up[7:0] = SI_Reg[7:0] ;
              end

              if (WRSR_Mode == 1'b1) begin       //for one byte WRSR write
                    if (Status_Reg[7:2] == 6'b00) 
                        tWRSR = tW_zero;
                    else if (Status_Reg[7:2] == Status_Reg_Up[7:2])
                        tWRSR = tW_same;
                    else 
                        tWRSR = tW;
                    Status_Reg[0]   = 1'b1;
                    #tWRSR;
                    Status_Reg[7:2] =  Status_Reg_Up[7:2];
                    //WIP : write in process Bit
                    Status_Reg[0]   = 1'b0;
                    //WEL:Write Enable Latch
                    Status_Reg[1]   = 1'b0;
                    WRSR_Mode       = 1'b0;
              end    
              VStatus_Reg[7:0] = Status_Reg[7:0];  // update the volatile status bits after wrsr
          end else begin // vwrite_enable_flag = 1
              if (WRSR_Mode == 1'b1) begin
                Status_Reg_Up[7:0] = SI_Reg[7:0] ;
              end

              if (WRSR_Mode == 1'b1) begin       //for one byte WRSR write
                    VStatus_Reg[7:2] =  Status_Reg_Up[7:2];
                    Status_Reg[0]   = 1'b0;
                    Status_Reg[1]   = 1'b0;
                    #1;
                    WRSR_Mode       = 1'b0;
              end    
              vwrite_enable_flag = 0;

          end
        end
    endtask // write_status

    /*----------------------------------------------------------------------*/
    /*  Description: define a write status task                             */
    /*               31 S15-8                                               */
    /*----------------------------------------------------------------------*/
    task write_status_2;
    reg [7:0] Status_Reg_Up;
        begin
          //$display( $time, " Old Status Register = %b", Status_Reg );
          if (vwrite_enable_flag == 0) begin
              if (WRSR2_Mode == 1'b1) begin
                Status_Reg_Up[7:0] = SI_Reg [7:0];
              end

              if (WRSR2_Mode == 1'b1) begin  //for two bytes WRSR write
                    if (Status_Reg[15:8] == 8'b00) 
                        tWRSR = tW_zero;
                    else if ((Status_Reg[14:11] == Status_Reg_Up[6:3]) && (Status_Reg[9:8] == Status_Reg_Up[1:0]))
                        tWRSR = tW_same;
                    else 
                        tWRSR = tW;
                    Status_Reg[0]   = 1'b1;
                    #tWRSR;
                    Status_Reg[9:8] =  Status_Reg_Up[1:0];
                    Status_Reg[14]  =  Status_Reg_Up[6];
                    Status_Reg[13:11] = Status_Reg[13:11] | Status_Reg_Up[5:3];   // LB3~LB1 can not be erased once set
                    //WIP : write in process Bit
                    Status_Reg[0]   = 1'b0;
                    //WEL:Write Enable Latch
                    Status_Reg[1]   = 1'b0;
                    WRSR2_Mode      = 1'b0;
              end
              VStatus_Reg = Status_Reg;  // update the volatile status bits after wrsr
          end else begin // vwrite_enable_flag = 1
              if (WRSR2_Mode == 1'b1) begin
                Status_Reg_Up[7:0] = SI_Reg[7:0] ;
              end

              if (WRSR2_Mode == 1'b1) begin  //for two bytes WRSR write
                    VStatus_Reg[9:8] =  Status_Reg_Up[1:0];
                    VStatus_Reg[14]  =  Status_Reg_Up[6];
                    VStatus_Reg[13:11] = Status_Reg[13:11] | Status_Reg_Up[5:3];   // LB3~LB1 can not be erased once set
                    Status_Reg[0]   = 1'b0;
                    Status_Reg[1]   = 1'b0;
                    #1;
                    WRSR2_Mode      = 1'b0;
              end
              vwrite_enable_flag = 0;

          end
        end
    endtask // write_status_2

 
    /*---------------------------------------------------------------------*/
    /*  Description: define a write control register task                  */
    /*---------------------------------------------------------------------*/
    task write_control;
    reg [7:0] Control_Reg_Up;
        begin
          //$display( $time, " Old control Register = %b", Control_Reg );
          if (WRCR_Mode == 1'b1) begin
            Control_Reg_Up[7:0] = SI_Reg[7:0] ;
          end

          if (WRCR_Mode == 1'b1) begin
                if (Control_Reg_Up == Control_Reg) // same data as previously stored
                    tWRCR = tW_same;
                else if (Control_Reg == 8'b0000_0000) // previous data is all zero
                    tWRCR = tW_zero;
                else if ( Control_Reg ^ Control_Reg_Up == 8'b00001000) // only QP different
                    tWRCR = tW_same;
                else
                    tWRCR = tW;
                Status_Reg[0]   = 1'b1;
                #tWRCR;
                Control_Reg[7:4] =  Control_Reg_Up[7:4];  
                Control_Reg[2] =  Control_Reg_Up[2];
                //WIP : write in process Bit
                Status_Reg[0]   = 1'b0;
                //WEL:Write Enable Latch
                Status_Reg[1]   = 1'b0;
                WRCR_Mode       = 1'b0;
          end    
        end
    endtask // write_control
 
    /*----------------------------------------------------------------------*/
    /*  Description: define a read data task                                */
    /*               03 AD1 AD2 AD3 X                                       */
    /*----------------------------------------------------------------------*/
    task read_1xio;
        integer Dummy_Count, Tmp_Int;
        reg  [7:0]       OUT_Buf;
        begin
            Dummy_Count = 8;
            dummy_cycle(24);
            #1; 
            read_array(Address, OUT_Buf);
            forever begin
                @ ( negedge ISCLK or posedge CS_INT );
                if ( CS_INT == 1'b1 ) begin
                    disable read_1xio;
                end 
                else  begin 
                    Read_Mode   = 1'b1;
                    SO_OUT_EN   = 1'b1;
                    SI_IN_EN    = 1'b0;
                    if ( Dummy_Count ) begin
                        {SIO1_Reg, OUT_Buf} <= {OUT_Buf, OUT_Buf[7]};
                        Dummy_Count = Dummy_Count - 1;
                    end
                    else begin
                        Address = Address + 1;
                        load_address(Address);
                        read_array(Address, OUT_Buf);
                        {SIO1_Reg, OUT_Buf} <= {OUT_Buf, OUT_Buf[7]};
                        Dummy_Count = 7 ;
                    end
                end 
            end  // end forever
        end   
    endtask // read_1xio

    /*----------------------------------------------------------------------*/
    /*  Description: define a fast read data task                           */
    /*               0B AD1 AD2 AD3 X                                       */
    /*----------------------------------------------------------------------*/
    task fastread_1xio;
        integer Dummy_Count, Tmp_Int;
        reg  [7:0]       OUT_Buf;
        begin
            Dummy_Count = 8;
            dummy_cycle(32);
            read_array(Address, OUT_Buf);
            forever begin
                @ ( negedge ISCLK or posedge CS_INT );
                if ( CS_INT == 1'b1 ) begin
                    disable fastread_1xio;
                end 
                else begin 
                    Read_Mode = 1'b1;
                    SO_OUT_EN = 1'b1;
                    SI_IN_EN  = 1'b0;
                    if ( Dummy_Count ) begin
                        {SIO1_Reg, OUT_Buf} <= {OUT_Buf, OUT_Buf[7]};
                        Dummy_Count = Dummy_Count - 1;
                    end
                    else begin
                        Address = Address + 1;
                        load_address(Address);
                        read_array(Address, OUT_Buf);
                        {SIO1_Reg, OUT_Buf} <= {OUT_Buf, OUT_Buf[7]};
                        Dummy_Count = 7 ;
                    end
                end    
            end  // end forever
        end   
    endtask // fastread_1xio

    /*----------------------------------------------------------------------*/
    /*  Description: define a fast read data task                           */
    /*               0B AD1 AD2 AD3 X                                       */
    /*----------------------------------------------------------------------*/
    task read_Secur_Register;
        integer Dummy_Count, Tmp_Int;
        reg  [7:0]       OUT_Buf;
        begin
            Dummy_Count = 8;
            dummy_cycle(32);
            read_array(Address, OUT_Buf);
            forever begin
                @ ( negedge ISCLK or posedge CS_INT );
                if ( CS_INT == 1'b1 ) begin
                    disable read_Secur_Register;
                end 
                else begin 
                    Read_Mode = 1'b1;
                    SO_OUT_EN = 1'b1;
                    SI_IN_EN  = 1'b0;
                    if ( Dummy_Count ) begin
                        {SIO1_Reg, OUT_Buf} <= {OUT_Buf, OUT_Buf[7]};
                        Dummy_Count = Dummy_Count - 1;
                    end
                    else begin
                        Address = Address + 1;
                        load_address(Address);
                        read_array(Address, OUT_Buf);
                        {SIO1_Reg, OUT_Buf} <= {OUT_Buf, OUT_Buf[7]};
                        Dummy_Count = 7 ;
                    end
                end    
            end  // end forever
        end   
    endtask // read_Secur_Register


    /*----------------------------------------------------------------------*/
    /*  Description: define a block erase task                              */
    /*               52 AD1 AD2 AD3                                         */
    /*----------------------------------------------------------------------*/
    task block_erase_32k;
        integer i, i_tmp;
        //time ERS_Time;
        integer Start_Add;
        integer End_Add;
        begin
            Block       =  Address[A_MSB:16];
            Block2      =  Address[A_MSB:15];
            Start_Add   = (Address[A_MSB:15]<<15) + 16'h0;
            End_Add     = (Address[A_MSB:15]<<15) + 16'h7fff;
            //WIP : write in process Bit
            Status_Reg[0] =  1'b1;
            if ( write_protect(Address) == 1'b0 /*&& !Secur_Mode*/ ) begin
               for( i = Start_Add; i <= End_Add; i = i + 1 )
               begin
                   ARRAY[i] = 8'hxx;
               end
               ERS_Time = ERS_Count_BE32K;
               fork
                   er_timer;
                   begin
                       for( i = 0; i < ERS_Time; i = i + 1 ) begin
                           fork
                               begin
                                   @ ( negedge ERS_CLK or posedge Susp_Trig );
                                   disable wpb_checker_be_32k;
                                   if ( Susp_Trig == 1'b1 ) begin
                                       if( Susp_Ready == 0 ) i = i_tmp;
                                       i_tmp = i;
                                       wait( Resume_Trig );
                                       if (WPb !== 1) begin
                                           ERS_Time = tBE32 / (Clock*2) / 500;
                                       end 
                                       //$display ( $time, " Resume BE32K Erase ..." );
                                   end
                               end
                               begin: wpb_checker_be_32k
                                   @ ( negedge WPb );
                                   #0.1;
                                   ERS_Time = tBE32 / (Clock*2) / 500;
                               end
                           join
                       end
                       //#tBE32 ;
                       for( i = Start_Add; i <= End_Add; i = i + 1 )
                       begin
                           ARRAY[i] = 8'hff;
                       end
                       disable er_timer;
                       disable resume_write;
                       Susp_Ready = 1'b1;
                   end
               join
            end
            else begin
                #tERS_CHK;
            end

            //WIP : write in process Bit
            Status_Reg[0] =  1'b0;//WIP
            //WEL : write enable latch
            Status_Reg[1] =  1'b0;//WEL
            BE_Mode = 1'b0;
            BE32K_Mode = 1'b0;
        end
    endtask // block_erase_32k

    /*----------------------------------------------------------------------*/
    /*  Description: define an suspend task                                 */
    /*----------------------------------------------------------------------*/
    task suspend_write;
        begin
            disable resume_write;
            Susp_Ready = 1'b1;

            if ( Pgm_Mode ) begin
                Susp_Trig = 1;
                During_Susp_Wait = 1'b1;
                #tPSL;
                //$display ( $time, " Suspend Program ..." );
                //SREG_SUS2     = 1'b1;//PSB
                Status_Reg[10]= 1'b1;//PSB
                Status_Reg[0] = 1'b0;//WIP
                Status_Reg[1] = 1'b0;//WEL
                WR2Susp = 0;
                During_Susp_Wait = 1'b0;
            end
            else if ( Ers_Mode ) begin
                Susp_Trig = 1;
                During_Susp_Wait = 1'b1;
                #tESL;
                //$display("tESL=%d\n",tESL);
                //$display ( $time, " Suspend Erase ..." );
                //SREG_SUS1     = 1'b1;
                Status_Reg[15]= 1'b1;
                Status_Reg[0] = 1'b0;//WIP
                Status_Reg[1] = 1'b0;//WEL
                WR2Susp = 0;
                During_Susp_Wait = 1'b0;
            end
        end
    endtask // suspend_write

    /*----------------------------------------------------------------------*/
    /*  Description: define an resume task                                  */
    /*----------------------------------------------------------------------*/
    task resume_write;
        begin
            if ( Pgm_Mode ) begin
                Susp_Ready    = 1'b0;
                Status_Reg[0] = 1'b1;//WIP
                Status_Reg[1] = 1'b1;//WEL
                Status_Reg[10] = 1'b0;//PSB
                Resume_Trig   = 1;
                #tPRS;
                Susp_Ready    = 1'b1;
            end
            else if ( Ers_Mode ) begin
                Susp_Ready    = 1'b0;
                Status_Reg[0] = 1'b1;//WIP
                Status_Reg[1] = 1'b1;//WEL
                Status_Reg[15] = 1'b0;//ESB
                Resume_Trig   = 1;
                #tERS;
                Susp_Ready    = 1'b1;
            end
        end
    endtask // resume_write

    /*----------------------------------------------------------------------*/
    /*  Description: define a timer to count erase time                     */
    /*----------------------------------------------------------------------*/
    task er_timer;
        begin
            ERS_CLK = 1'b0;
            forever
                begin
                    #(Clock*500) ERS_CLK = ~ERS_CLK;    // erase timer period is 50us
                end
        end
    endtask // er_timer


    /*----------------------------------------------------------------------*/
    /*  Description: define a block erase task                              */
    /*               D8 AD1 AD2 AD3                                         */
    /*----------------------------------------------------------------------*/
    task block_erase;
        integer i, i_tmp;
        //time ERS_Time;
        integer Start_Add;
        integer End_Add;
        begin
            Block       =  Address[A_MSB:16];
            Block2      =  Address[A_MSB:15];
            Start_Add   = (Address[A_MSB:16]<<16) + 16'h0;
            End_Add     = (Address[A_MSB:16]<<16) + 16'hffff;
            //WIP : write in process Bit
            Status_Reg[0] =  1'b1;
            if ( write_protect(Address) == 1'b0 /*&& !Secur_Mode*/ )begin
               ->DEBUG_FSM_EVENT;
               for( i = Start_Add; i <= End_Add; i = i + 1 )
               begin
                   ARRAY[i] = 8'hxx;
               end
               ERS_Time = ERS_Count_BE;
               fork
                   er_timer;
                   begin
                       for( i = 0; i < ERS_Time; i = i + 1 ) begin
                           fork
                               begin
                                   @ ( negedge ERS_CLK or posedge Susp_Trig );
                                   disable wpb_checker_be;
                                   if ( Susp_Trig == 1'b1 ) begin
                                       if( Susp_Ready == 0 ) i = i_tmp;
                                       i_tmp = i;
                                       wait( Resume_Trig );
                                       if (WPb !== 1) begin
                                           ERS_Time = tBE / (Clock*2) / 500;
                                       end 
                                       //$display ( $time, " Resume BE Erase ..." );
                                   end
                               end
                               begin: wpb_checker_be
                                   @ ( negedge WPb );
                                   #0.1;
                                   ERS_Time = tBE / (Clock*2) / 500;
                               end
                           join
                       end
                       //#tBE ;
                       for( i = Start_Add; i <= End_Add; i = i + 1 )
                       begin
                           ARRAY[i] = 8'hff;
                       end
                       disable er_timer;
                       disable resume_write;
                       Susp_Ready = 1'b1;
                   end
               join
            end
            else begin
                #tERS_CHK;
            end   
                //WIP : write in process Bit
                Status_Reg[0] =  1'b0;//WIP
                //WEL : write enable latch
                Status_Reg[1] =  1'b0;//WEL
                BE_Mode = 1'b0;
                BE64K_Mode = 1'b0;
        end
    endtask // block_erase

    /*----------------------------------------------------------------------*/
    /*  Description: define a sector 4k erase task                          */
    /*               20 AD1 AD2 AD3                                         */
    /*----------------------------------------------------------------------*/
    task sector_erase_4k;
        integer i, i_tmp;
        //time ERS_Time;
        integer Start_Add;
        integer End_Add;
        begin
            Sector      =  Address[A_MSB:12]; 
            Start_Add   = (Address[A_MSB:12]<<12) + 12'h000;
            End_Add     = (Address[A_MSB:12]<<12) + 12'hfff;          
            //WIP : write in process Bit
            Status_Reg[0] =  1'b1;
            if ( write_protect(Address) == 1'b0 /*&& !Secur_Mode*/ ) begin
               for( i = Start_Add; i <= End_Add; i = i + 1 )
               begin
                   ARRAY[i] = 8'hxx;
               end
               ERS_Time = ERS_Count_SE;
               fork
                   er_timer;
                   begin
                       for( i = 0; i < ERS_Time; i = i + 1 ) begin
                           fork
                               begin
                                   @ ( negedge ERS_CLK or posedge Susp_Trig );
                                   disable wpb_checker_se;
                                   if ( Susp_Trig == 1'b1 ) begin
                                       if( Susp_Ready == 0 ) i = i_tmp;
                                       i_tmp = i;
                                       wait( Resume_Trig );
                                       if (WPb !== 1) begin
                                           ERS_Time = tSE / (Clock*2) / 500;
                                       end 
                                       //$display ( $time, " Resume SE Erase ..." );
                                   end
                               end
                               begin: wpb_checker_se
                                   @ ( negedge WPb );
                                   #0.1;
                                   ERS_Time = tSE / (Clock*2) / 500;
                               end
                           join
                       end
                       for( i = Start_Add; i <= End_Add; i = i + 1 )
                       begin
                           ARRAY[i] = 8'hff;
                       end
                       disable er_timer;
                       disable resume_write;
                       Susp_Ready = 1'b1;
                   end
               join
            end
            else begin
                #tERS_CHK;
            end
                //WIP : write in process Bit
                Status_Reg[0] = 1'b0;//WIP
                //WEL : write enable latch
                Status_Reg[1] = 1'b0;//WEL
                SE_4K_Mode = 1'b0;
         end
    endtask // sector_erase_4k
    

    /*----------------------------------------------------------------------*/
    /*  Description: define a 256 page erase task                          */
    /*               81 AD1 AD2 AD3                                         */
    /*----------------------------------------------------------------------*/
    task page_erase;
        integer i, i_tmp;
        //time ERS_Time;
        integer Start_Add;
        integer End_Add;
        begin
            if (CR_QP) begin
                Page        =  Address[A_MSB:10]; 
                Start_Add   = (Address[A_MSB:10]<<10) + 13'h00;
                End_Add = (Address[A_MSB:10]<<10) + 13'h3ff;
            end else begin
                Page        =  Address[A_MSB:8]; 
                Start_Add   = (Address[A_MSB:8]<<8) + 12'h00;
                End_Add = (Address[A_MSB:8]<<8) + 12'hff;
            end
            //WIP : write in process Bit
            Status_Reg[0] =  1'b1;
	    #100;
            if ( write_protect(Address) == 1'b0 ) begin
               for( i = Start_Add; i <= End_Add; i = i + 1 )
               begin
                   ARRAY[i] = 8'hxx;
               end
               ERS_Time = ERS_Count_SE;
               fork
                   er_timer;
                   begin
                       for( i = 0; i < ERS_Time; i = i + 1 ) begin
                           fork
                               begin
                                   @ ( negedge ERS_CLK or posedge Susp_Trig );
                                   disable wpb_checker_se;
                                   if ( Susp_Trig == 1'b1 ) begin
                                       if( Susp_Ready == 0 ) i = i_tmp;
                                       i_tmp = i;
                                       wait( Resume_Trig );
                                       if (WPb !== 1) begin
                                           ERS_Time = tSE / (Clock*2) / 500;
                                       end 
                                       //$display ( $time, " Resume SE Erase ..." );
                                   end
                               end
                               begin: wpb_checker_se
                                   @ ( negedge WPb );
                                   #0.1;
                                   ERS_Time = tSE / (Clock*2) / 500;
                               end
                           join
                       end
                       for( i = Start_Add; i <= End_Add; i = i + 1 )
                       begin
                           ARRAY[i] = 8'hff;
                       end
                       disable er_timer;
                       disable resume_write;
                       Susp_Ready = 1'b1;
                   end
               join
            end
            else begin
                #tERS_CHK;
            end
                //WIP : write in process Bit
                Status_Reg[0] = 1'b0;//WIP
                //WEL : write enable latch
                Status_Reg[1] = 1'b0;//WEL
                //SE_4K_Mode = 1'b0;
                PE_Mode = 1'b0;
         end
    endtask // page_erase
    
    /*----------------------------------------------------------------------*/
    /*  Description: define a chip erase task                               */
    /*               60(C7)                                                 */
    /*----------------------------------------------------------------------*/
    task chip_erase;
        reg [A_MSB:0] Address_Int;
        integer i;
        begin
            for (i=0; i<=TOP_Add; i=i+1) 
                ARRAY[i] = 8'hxx;

            Address_Int = Address;
            Status_Reg[0] =  1'b1;
            if ( Dis_CE == 1'b1 /*|| Secur_Mode*/ )begin
                #tERS_CHK;
            end
            else begin
                ERS_Time = tCE;
                fork
                    begin
                        for ( i = 0;i<ERS_Time;i = i + 1) begin
                            #1_000_000;
                        end
                        disable wpb_checker_ce;
                    end
                    begin: wpb_checker_ce
                        @( negedge WPb );
                        #0.1;
                        ERS_Time = tCE;
                    end
                join
                for( i = 0; i <Block_NUM; i = i+1 ) begin
                    Address_Int = (i<<16) + 16'h0;
                    Start_Add = (i<<16) + 16'h0;
                    End_Add   = (i<<16) + 16'hffff;     
                    for( j = Start_Add; j <=End_Add; j = j + 1 )
                    begin
                        ARRAY[j] =  8'hff;
                    end
                end
            end
            //WIP : write in process Bit
            Status_Reg[0] = 1'b0;//WIP
            //WEL : write enable latch
            Status_Reg[1] = 1'b0;//WEL
            CE_Mode = 1'b0;
        end
    endtask // chip_erase       

    /*----------------------------------------------------------------------*/
    /*  Description: define a page program task                             */
    /*               02 AD1 AD2 AD3                                         */
    /*----------------------------------------------------------------------*/
    task page_program;
        input  [A_MSB:0]  Address;
        reg    [9:0]      Offset;
        integer Dummy_Count, Tmp_Int, i;
        begin
            if (CR_QP) begin
                Dummy_Count = Buffer_Num * 4 ;    // page size
                Offset  = Address[9:0];
            end
            else begin
                Dummy_Count = Buffer_Num;
                Offset  = {2'b00, Address[7:0]};
            end
            Tmp_Int = 0;
            //$display("Entering page_program.......................\n");
            /*------------------------------------------------*/
            /*  Store 256 bytes into a temp buffer - Dummy_A  */
            /*------------------------------------------------*/
            for (i = 0; i < Dummy_Count ; i = i + 1 ) begin
                Dummy_A[i]  = 8'hff;
            end
            forever begin
                @ ( posedge ISCLK or posedge CS_INT );
                if ( CS_INT == 1'b1 ) begin
                    if ( (Tmp_Int % 8 !== 0) || (Tmp_Int == 1'b0) ) begin
                        PP_4XIO_Mode = 0;
                        PP_1XIO_Mode = 0;
                        DPP_1XIO_Mode = 0;
                        QPP_1XIO_Mode = 0;
                        //PRSCUR_Mode = 0;
                        disable page_program;
                    end
                    else begin
                        if ( Tmp_Int > 8 )
                            Byte_PGM_Mode = 1'b0;
                        else 
                            Byte_PGM_Mode = 1'b1;
                        update_array ( Address );
                    end
                    disable page_program;
                end
                else begin  // count how many Bits been shifted
                    //Tmp_Int = ( PP_4XIO_Mode | ENQUAD ) ? Tmp_Int + 4 : Tmp_Int + 1;
                    Tmp_Int = ( PP_4XIO_Mode || QPP_1XIO_Mode ) ? Tmp_Int + 4 : ( DPP_1XIO_Mode) ? Tmp_Int + 2 : Tmp_Int + 1;
                    if ( Tmp_Int % 8 == 0) begin
                        #1;
                        Dummy_A[Offset] = SI_Reg [7:0];
                        //$display("!!!!!!! DEBUG: Dummy_A[%d] = %x", Offset, Dummy_A[Offset]);
                        Offset = Offset + 1;   
                        if (CR_QP==0) begin
                            Offset = {2'b00, Offset[7:0]};   
                        end
                        else begin
                            Offset = Offset[9:0];   
                        end
                    end  
                end
            end  // end forever
        end
    endtask // page_program

    /*----------------------------------------------------------------------*/
    /*  Description: define a otp program task                             */
    /*               42 AD1 AD2 AD3                                         */
    /*----------------------------------------------------------------------*/
    task otp_program;
        input  [A_MSB:0]  Address;
        reg    [9:0]      Offset;
        integer Dummy_Count, Tmp_Int, i;
        begin
            Dummy_Count = Buffer_Num * 4 ;    // OTP is 1024 in P25Q32H
            Tmp_Int = 0;
            Offset  = Address[9:0];
            /*------------------------------------------------*/
            /*  Store 1024 bytes into a temp buffer - Dummy_A  */
            /*------------------------------------------------*/
            for (i = 0; i < Dummy_Count ; i = i + 1 ) begin
                Dummy_A[i]  = 8'hff;
            end
            forever begin
                @ ( posedge ISCLK or posedge CS_INT );
                if ( CS_INT == 1'b1 ) begin
                    if ( (Tmp_Int % 8 !== 0) || (Tmp_Int == 1'b0) ) begin
                        //PRSCUR_Mode = 0;
                        disable otp_program;
                    end
                    else begin
                        if ( Tmp_Int > 8 )
                            Byte_PGM_Mode = 1'b0;
                        else 
                            Byte_PGM_Mode = 1'b1;
                        update_otp_array ( Address );
                    end
                    disable otp_program;
                end
                else begin  // count how many Bits been shifted
                    Tmp_Int = Tmp_Int + 1;
                    if ( Tmp_Int % 8 == 0) begin
                        #1;
                        Dummy_A[Offset] = SI_Reg [7:0];
                        Offset = Offset + 1;   
                        Offset = Offset[9:0];   
                    end  
                end
            end  // end forever
        end
    endtask // page_program

    
 
    /*----------------------------------------------------------------------*/
    /*  Description: define a read electronic ID (RES)                      */
    /*               AB X X X                                               */
    /*----------------------------------------------------------------------*/
    task read_electronic_id;
        reg  [7:0] Dummy_ID;
        begin
            //$display( $time, " Old DP Mode Register = %b", DP_Mode );
            if (QPI_Mode) begin
                dummy_cycle(5);
            end
            else begin
              dummy_cycle(23);
            end
            Dummy_ID = ID_Device;
            dummy_cycle(1);

            forever begin
                @ ( negedge ISCLK or posedge CS_INT );
                if ( CS_INT == 1'b1 ) begin
                    disable read_electronic_id;
                end 
                else begin  
                    if (QPI_Mode) begin
                        SI_OUT_EN    = 1'b1;
                        WP_OUT_EN    = 1'b1;
                        SIO3_OUT_EN  = 1'b1;
                    end
                    SO_OUT_EN = 1'b1;
                    SO_IN_EN  = 1'b0;
                    SI_IN_EN  = 1'b0;
                    WP_IN_EN  = 1'b0;
                    SIO3_IN_EN= 1'b0;
                    if (QPI_Mode) begin
                        {SIO3_Reg, SIO2_Reg, SIO1_Reg, SIO0_Reg, Dummy_ID} <= {Dummy_ID, Dummy_ID[7:4]};
                    end
                    else begin
                      {SIO1_Reg, Dummy_ID} <= {Dummy_ID, Dummy_ID[7]};
                    end
                end
            end // end forever   
        end
    endtask // read_electronic_id
            
    /*----------------------------------------------------------------------*/
    /*  Description: define a read electronic manufacturer & device ID      */
    /*----------------------------------------------------------------------*/
    task read_electronic_manufacturer_device_id;
        reg  [15:0] Dummy_ID;
        integer Dummy_Count;
        begin
            if ( !QPI_Mode )
                dummy_cycle(24);
            else
                dummy_cycle(6);

            #1;
            if ( Address[0] == 1'b0 ) begin
                Dummy_ID = {ID_PUYA,ID_Device};
            end
            else begin
                Dummy_ID = {ID_Device,ID_PUYA};
            end
            Dummy_Count = 0;
            forever begin
                @ ( negedge ISCLK or posedge CS_INT );
                if ( CS_INT == 1'b1 ) begin
                    disable read_electronic_manufacturer_device_id;
                end
                else begin
                    if (QPI_Mode) begin
                        SO_OUT_EN = 1'b1;
                        SI_OUT_EN   = 1'b1;
                        WP_OUT_EN   = 1'b1;
                        SIO3_OUT_EN = 1'b1;
                    end
                    SO_OUT_EN =  1'b1;
                    SI_IN_EN  =  1'b0;
                    if (QPI_Mode) 
                        {SIO3_Reg, SIO2_Reg, SIO1_Reg, SIO0_Reg, Dummy_ID} <= {Dummy_ID, Dummy_ID[15:12]};
                    else 
                        {SIO1_Reg, Dummy_ID} <= {Dummy_ID, Dummy_ID[15]};
                end
            end // end forever
        end
    endtask // read_electronic_manufacturer_device_id

    /*----------------------------------------------------------------------*/
    /*  Description: define a read electronic manufacturer & device ID      */
    /*----------------------------------------------------------------------*/
    task dual_read_electronic_manufacturer_device_id;
        reg  [15:0] Dummy_ID;
        integer Dummy_Count;
        begin
            Dummy_Count = 4;
            SI_IN_EN = 1'b1;
            SO_IN_EN = 1'b1;
            SI_OUT_EN = 1'b0;
            SO_OUT_EN = 1'b0;

            dummy_cycle(16);
            #1;
            if ( Address[0] == 1'b0 ) begin
                Dummy_ID = {ID_PUYA,ID_Device};
            end
            else begin
                Dummy_ID = {ID_Device,ID_PUYA};
            end
            forever begin
                @ ( negedge ISCLK or posedge CS_INT );
                if ( CS_INT == 1'b1 ) begin
                    disable dual_read_electronic_manufacturer_device_id;
                end
                else begin
                    SO_OUT_EN   = 1'b1;
                    SI_OUT_EN   = 1'b1;
                    SI_IN_EN    = 1'b0;
                    SO_IN_EN    = 1'b0;
                    {SIO1_Reg, SIO0_Reg, Dummy_ID} <= {Dummy_ID, Dummy_ID[15:14]};
                end
            end // end forever
        end
    endtask // dual_read_electronic_manufacturer_device_id

    /*----------------------------------------------------------------------*/
    /*  Description: define a read electronic manufacturer & device ID      */
    /*----------------------------------------------------------------------*/
    task quad_read_electronic_manufacturer_device_id;
        reg  [15:0] Dummy_ID;
        integer Dummy_Count;
        begin
            Dummy_Count = 2;
            SI_OUT_EN    = 1'b0;
            SO_OUT_EN    = 1'b0;
            WP_OUT_EN    = 1'b0;
            SIO3_OUT_EN  = 1'b0;
            SI_IN_EN    = 1'b1;
            SO_IN_EN    = 1'b1;
            WP_IN_EN    = 1'b1;
            SIO3_IN_EN   = 1'b1;

            dummy_cycle(8);
            #1;
            if ( Address[0] == 1'b0 ) begin
                Dummy_ID = {ID_PUYA,ID_Device};
            end
            else begin
                Dummy_ID = {ID_Device,ID_PUYA};
            end
            dummy_cycle(4);
            forever begin
                @ ( negedge ISCLK or posedge CS_INT );
                if ( CS_INT == 1'b1 ) begin
                    disable quad_read_electronic_manufacturer_device_id;
                end
                else begin
                    SI_OUT_EN    = 1'b1;
                    SO_OUT_EN    = 1'b1;
                    WP_OUT_EN    = 1'b1;
                    SIO3_OUT_EN  = 1'b1;
                    SI_IN_EN     = 1'b0;
                    SO_IN_EN     = 1'b0;
                    WP_IN_EN     = 1'b0;
                    SIO3_IN_EN   = 1'b0;
                    {SIO3_Reg, SIO2_Reg, SIO1_Reg, SIO0_Reg, Dummy_ID} <= {Dummy_ID, Dummy_ID[15:12]};
                end
            end // end forever
        end
    endtask // quad_read_electronic_manufacturer_device_id


    /*----------------------------------------------------------------------*/
    /*  Description: define a program chip task                             */
    /*  INPUT:address                                                       */
    /*----------------------------------------------------------------------*/
    task update_array;
        input [A_MSB:0] Address;
        integer Dummy_Count, i, i_tmp;
        integer program_time;
        reg [7:0]  ori [0: 4*Buffer_Num-1];
        begin
            if (CR_QP) begin
                Dummy_Count = Buffer_Num * 4 ;    // page size
                Address = { Address [A_MSB:10], 10'h0 };
            end
            else begin
                Dummy_Count = Buffer_Num;
                Address = { Address [A_MSB:8], 8'h0 };
            end
            program_time = (Byte_PGM_Mode) ? tBP : tPP;
            Status_Reg[0]= 1'b1;
            if ( write_protect(Address) == 1'b0 && add_in_erase(Address) == 1'b0 ) begin
                for ( i = 0; i < Dummy_Count; i = i + 1 ) begin
                     ori[i] = ARRAY[Address + i];
                     ARRAY[Address+ i] = ARRAY[Address + i] & 8'bx;
                end
                fork
                    pg_timer;
                    begin
                        for( i = 0; i*2 < program_time; i = i + 1 ) begin
                            fork
                                begin
                                    @ ( negedge PGM_CLK or posedge Susp_Trig );
                                    disable wpb_checker_pg;
                                    if ( Susp_Trig == 1'b1 ) begin
                                        if( Susp_Ready == 0 ) i = i_tmp;
                                        i_tmp = i;
                                        wait( Resume_Trig );
                                        if ( WPb !== 1 ) begin
                                            program_time = (Byte_PGM_Mode) ? tBP : tPP;
                                        end
                                        //$display ( $time, " Resume program ..." );
                                    end
                                end
                                begin : wpb_checker_pg
                                    @( negedge WPb );
                                    #0.1;
                                    program_time = (Byte_PGM_Mode) ? tBP : tPP;
                                end
                            join
                        end
                        //#program_time ;
                        for ( i = 0; i < Dummy_Count; i = i + 1 ) begin
                             ARRAY[Address+ i] = ori[i] & Dummy_A[i];
                             if ((Address+i)== 21'h1fff00) $display("Address 1fff00 prog w/ %x", ori[i]&Dummy_A[i]);
                        end
                        disable pg_timer;
                        disable resume_write;
                        Susp_Ready = 1'b1;
                    end
                join
            end
            else begin
                #tPGM_CHK ;
            end
            Status_Reg[0] = 1'b0;
            Status_Reg[1] = 1'b0;
            PP_4XIO_Mode = 1'b0;
            PP_1XIO_Mode = 1'b0;
            DPP_1XIO_Mode = 1'b0;
            QPP_1XIO_Mode = 1'b0;
            Byte_PGM_Mode = 1'b0;
        end
    endtask // update_array

    /*----------------------------------------------------------------------*/
    /*  Description: define a program otp task                             */
    /*  INPUT:address                                                       */
    /*----------------------------------------------------------------------*/
    task update_otp_array;
        input [A_MSB:0] Address;
        integer Dummy_Count, i, i_tmp;
        integer program_time;
        reg [7:0]  ori [0:4*Buffer_Num-1];
        begin
            Dummy_Count = 1024; 
            Address = { Address [A_MSB:10], 10'h0 };
            program_time = (Byte_PGM_Mode) ? tBP : tPP;
            Status_Reg[0]= 1'b1;
            if ( write_protect(Address) == 1'b0 && add_in_erase(Address) == 1'b0 ) begin
                for ( i = 0; i < Dummy_Count; i = i + 1 ) begin
                    if ( PRSCUR_Mode == 1'b1) begin
                        if (Address[11:10] == 2'b00) begin
                            if (Address[A_MSB:12] == 1) begin
                                ori[i] = Secur_ARRAY1[i];
                                Secur_ARRAY1[i] = Secur_ARRAY1[i] & 8'bx;
                            end else if (Address[A_MSB:12] == 2) begin
                                ori[i] = Secur_ARRAY2[i];
                                Secur_ARRAY2[i] = Secur_ARRAY2[i] & 8'bx;
                            end else if (Address[A_MSB:12] == 3) begin
                                ori[i] = Secur_ARRAY3[i];
                                Secur_ARRAY3[i] = Secur_ARRAY3[i] & 8'bx;
                            end
                        end
                    end
                end
                fork
                    pg_timer;
                    begin
                        for( i = 0; i*2 < program_time; i = i + 1 ) begin
                            fork
                                begin
                                    @ ( negedge PGM_CLK or posedge Susp_Trig );
                                    disable wpb_checker_pg;
                                    if ( Susp_Trig == 1'b1 ) begin
                                        if( Susp_Ready == 0 ) i = i_tmp;
                                        i_tmp = i;
                                        wait( Resume_Trig );
                                        if ( WPb !== 1 ) begin
                                            program_time = (Byte_PGM_Mode) ? tBP : tPP;
                                        end
                                        //$display ( $time, " Resume program ..." );
                                    end
                                end
                                begin : wpb_checker_pg
                                    @( negedge WPb );
                                    #0.1;
                                    program_time = (Byte_PGM_Mode) ? tBP : tPP;
                                end
                            join
                        end
                        //#program_time ;
                        if (PRSCUR_Mode == 1'b1 && Address[11:10] != 2'b00) $display("Address out of security register (OTP) space, nothing happen\n");
                        for ( i = 0; i < Dummy_Count; i = i + 1 ) begin
                            if ( PRSCUR_Mode == 1'b1) begin
                                if (Address[11:10] == 2'b00) begin
                                    if (Address[A_MSB:12] == 1) 
                                        Secur_ARRAY1[i] = ori[i] & Dummy_A[i];
                                    else if (Address[A_MSB:12] == 2) 
                                        Secur_ARRAY2[i] = ori[i] & Dummy_A[i];
                                    else if (Address[A_MSB:12] == 3) 
                                        Secur_ARRAY3[i] = ori[i] & Dummy_A[i];
                                end
                            end 
                        end
                        disable pg_timer;
                        disable resume_write;
                        Susp_Ready = 1'b1;
                    end
                join
            end
            else begin
                #tPGM_CHK ;
            end
            Status_Reg[0] = 1'b0;
            Status_Reg[1] = 1'b0;
            PRSCUR_Mode   = 1'b0;
            Byte_PGM_Mode = 1'b0;
        end

    endtask // update_array


    /*----------------------------------------------------------------------*/
    /*Description: find out whether the address is selected for erase       */
    /*----------------------------------------------------------------------*/
    function add_in_erase;
        input [A_MSB:0] Address;
        begin
            if( ERSCUR_Mode==1'b0) begin
                if ( ( BE32K_Mode && Address[A_MSB:15] == Block2 && SREG_SUS1 ) ||
                     ( BE64K_Mode && Address[A_MSB:16] == Block && SREG_SUS1) ||
                     ( SE_4K_Mode && Address[A_MSB:12] == Sector && SREG_SUS1) ||
                     ( PE_Mode && Address[A_MSB:9] == Page && SREG_SUS1) ) begin
                    add_in_erase = 1'b1;
                    $display ( $time," Failed programing,address is in erase" );
                end
                else begin
                    add_in_erase = 1'b0;
                end
            end
            else if( ERSCUR_Mode == 1'b1 ) begin
                if ( ERSCUR_Mode && Address[A_MSB:12] != 0 && SREG_SUS1) begin
                    add_in_erase = 1'b1;
                    $display($time, " Failed programming,address is in erase");
                end
                else
                    add_in_erase = 1'b0;
            end
        end
    endfunction // add_in_erase


    /*----------------------------------------------------------------------*/
    /*  Description: define a timer to count program time                   */
    /*----------------------------------------------------------------------*/
    task pg_timer;
        begin
            PGM_CLK = 1'b0;
            forever
                begin
                    #1 PGM_CLK = ~PGM_CLK;    // program timer period is 2ns
                end
        end
    endtask // pg_timer

    /*----------------------------------------------------------------------*/
    /*  Description: Execute Erase Security Register                        */
    /*               44 A23~A0 xx xx                                        */
    /*----------------------------------------------------------------------*/
    task erase_secur_register;
        reg [A_MSB:12] add_cut;    // define the security register section
        integer i, i_tmp;
        begin
            ERSCUR_Mode = 1'b1;
            add_cut = Address[A_MSB:12];
            //WIP: write in progress
            Status_Reg[0] = 1'b1;
	    if (add_cut != 1 && add_cut != 2 && add_cut != 3) begin
			#15;
			end
            else if (write_protect(Address) == 1'b0 && ERSCUR_Mode == 1'b1) begin
                for (i=0; i<=1023; i=i+1) begin
                    if(add_cut == 1) Secur_ARRAY1[i] = 8'hxx;
                    else if(add_cut == 2) Secur_ARRAY2[i] = 8'hxx;
                    else if(add_cut == 3) Secur_ARRAY3[i] = 8'hxx;
                end

               ERS_Time = ERS_Count_BE;
               fork
                   er_timer;
                   begin
                       for( i = 0; i < ERS_Time; i = i + 1 ) begin
                           fork
                               begin
                                   @ ( negedge ERS_CLK or posedge Susp_Trig );
                                   disable wpb_checker_be;
                                   if ( Susp_Trig == 1'b1 ) begin
                                       if( Susp_Ready == 0 ) i = i_tmp;
                                       i_tmp = i;
                                       wait( Resume_Trig );
                                       if (WPb !== 1) begin
                                           ERS_Time = tBE / (Clock*2) / 500;
                                       end 
                                       //$display ( $time, " Resume BE Erase ..." );
                                   end
                               end
                               begin: wpb_checker_be
                                   @ ( negedge WPb );
                                   #0.1;
                                   ERS_Time = tBE / (Clock*2) / 500;
                               end
                           join
                       end
                       //#tBE ;
                       for( i = 0; i <= 1023; i = i + 1 )
                       begin
                           if(add_cut == 1) Secur_ARRAY1[i] = 8'hff;
                           else if(add_cut == 2) Secur_ARRAY2[i] = 8'hff;
                           else if(add_cut == 3) Secur_ARRAY3[i] = 8'hff;
                           //if(add_cut == 1) $display("Erase secur_array1 to ff\n");
                       end
                       disable er_timer;
                       disable resume_write;
                       Susp_Ready = 1'b1;
                   end
               join
            end
                //WIP : write in process Bit
                Status_Reg[0] =  1'b0;//WIP
                //WEL : write enable latch
                Status_Reg[1] =  1'b0;//WEL
                ERSCUR_Mode = 1'b0;
        end
    endtask // erase_secur_register


    /*----------------------------------------------------------------------*/
    /*  Description: Execute 2X IO Read Mode                                */
    /*----------------------------------------------------------------------*/
    task read_2xio;
        reg  [7:0]  OUT_Buf;
        integer     Dummy_Count;
        begin
            Dummy_Count=4;
            SI_IN_EN = 1'b1;
            SO_IN_EN = 1'b1;
            SI_OUT_EN = 1'b0;
            SO_OUT_EN = 1'b0;
            dummy_cycle(12); // for Address
            dummy_cycle(4);  // for M7-0

            #1;
            if ((SI_Reg[5:4] == 2'b10) && !Low_Power_Mode) begin
                Set_2XIO_Enhance_Mode = 1'b1;
            end
            else  begin 
                Set_2XIO_Enhance_Mode = 1'b0;
            end
            //$display("Address is %x\n", Address);

            //if ( (!READ2X_Mode && (CMD_BUS == RSTEN || CMD_BUS == RST) && EN2XIO_Read_Mode == 1'b1 ) )
            //    dummy_cycle(2);
            //else
            //    dummy_cycle(4);   // READ_2XIO


            //dummy_cycle(2);
            //#1;
            //dummy_cycle(2);
            read_array(Address, OUT_Buf);
          
            forever @ ( negedge ISCLK or  posedge CS_INT ) begin
                if ( CS_INT == 1'b1 ) begin
                    disable read_2xio;
                end
                else begin
                    Read_Mode   = 1'b1;
                    SO_OUT_EN   = 1'b1;
                    SI_OUT_EN   = 1'b1;
                    SI_IN_EN    = 1'b0;
                    SO_IN_EN    = 1'b0;
                    if ( Dummy_Count ) begin
                        {SIO1_Reg, SIO0_Reg, OUT_Buf} <= {OUT_Buf, OUT_Buf[1:0]};
                        Dummy_Count = Dummy_Count - 1;
                    end
                    else begin
                        Address = Address + 1;
                        load_address(Address);
                        read_array(Address, OUT_Buf);
                        {SIO1_Reg, SIO0_Reg, OUT_Buf} <= {OUT_Buf, OUT_Buf[1:0]};
                        Dummy_Count = 3 ;
                    end
                end
            end//forever  
        end
    endtask // read_2xio

    /*----------------------------------------------------------------------*/
    /*  Description: Execute 4X IO Read Mode                                */
    /*----------------------------------------------------------------------*/
    task read_4xio;
        //reg [A_MSB:0] Address;
        reg [7:0]   OUT_Buf ;
        integer     Dummy_Count;
        integer     Num_Cycles;
        integer     BurstRd_Wrap_Length;  
        reg         Addr_E7H; 
        reg [3:0]   Addr_E3H; 
        begin
            Dummy_Count = 2;
            SI_OUT_EN    = 1'b0;
            SO_OUT_EN    = 1'b0;
            WP_OUT_EN    = 1'b0;
            SIO3_OUT_EN  = 1'b0;
            SI_IN_EN    = 1'b1;
            SO_IN_EN    = 1'b1;
            WP_IN_EN    = 1'b1;
            SIO3_IN_EN   = 1'b1;
            //clear_EN_Burst = 1'b0;
            dummy_cycle(6); // for address
            #1;
            if (WordRead_Mode) Addr_E7H = Address[0];
            if (OctalRead_Mode) Addr_E3H = Address[3:0];
           
            //if (!(OctalRead_Mode || QPI_Mode)) dummy_cycle(2); // octal read don't require dummy clocks, as last 4 bit is zero!
            if (!QPI_Mode) dummy_cycle(2); // octal read don't require dummy clocks, as last 4 bit is zero!

            #1;
            if (!QPI_Mode || (QPI_Mode && READ4X_Mode)) begin
 	 	#1;
                if ((SI_Reg[5:4] == 2'b10) && !Low_Power_Mode) begin
                    Set_4XIO_Enhance_Mode = 1'b1;
                end
                else  begin 
                    Set_4XIO_Enhance_Mode = 1'b0;
                    //clear_EN_Burst = 1'b1;
                end
            end

            if ( !QPI_Mode) begin
                if ( CMD_BUS == FASTREAD1X || (!READ4X_Mode && (CMD_BUS == RSTEN || CMD_BUS == RST) && EN4XIO_Read_Mode == 1'b1 ) )
                    dummy_cycle(2);
                else if ( CMD_BUS == SFDP_READ )
                    dummy_cycle(6);
                else if ( CMD_BUS == OCTALREAD )
                    dummy_cycle(0);
                else if ( CMD_BUS == WORDREAD )
                    dummy_cycle(2);
                else 
                    dummy_cycle(4);   // READ_4XIO
            end
            else begin // in QPI_MODE
                if (Param_dummy_clock == 2'b00) Num_Cycles = 4;
                if (Param_dummy_clock == 2'b01) Num_Cycles = 4;
                if (Param_dummy_clock == 2'b10) Num_Cycles = 6;
                if (Param_dummy_clock == 2'b11) Num_Cycles = 8;
                dummy_cycle(Num_Cycles);
            end

            read_array(Address, OUT_Buf);

            // output xxx when the address LSBs set not correctly under word/octal read mode
            if ((WordRead_Mode && Addr_E7H != 1'b0) || (OctalRead_Mode && Addr_E3H)) begin
                OUT_Buf = 8'hxx;
            end

            //$display("Debug, outbuf is %x\n", OUT_Buf);
            forever @ ( negedge ISCLK or  posedge CS_INT ) begin
                if ( CS_INT == 1'b1 ) begin
                    disable read_4xio;
                end
                  
                else begin
                    SO_OUT_EN   = 1'b1;
                    SI_OUT_EN   = 1'b1;
                    WP_OUT_EN   = 1'b1;
                    SIO3_OUT_EN = 1'b1;
                    SO_IN_EN    = 1'b0;
                    SI_IN_EN    = 1'b0;
                    WP_IN_EN    = 1'b0;
                    SIO3_IN_EN  = 1'b0;
                    Read_Mode  = 1'b1;
                    if ( Dummy_Count ) begin
                        {SIO3_Reg, SIO2_Reg, SIO1_Reg, SIO0_Reg, OUT_Buf} <= {OUT_Buf, OUT_Buf[3:0]};
                        Dummy_Count = Dummy_Count - 1;
                    end
                    else begin
                         if (SFDP_Mode) begin
                                Address = Address + 1;
                         	end
                         else if (!BurstRead_Mode && READ4X_Mode) begin
                            if ( EN_Burst && Burst_Length==8 && Address[2:0]==3'b111 )
                                Address = {Address[A_MSB:3], 3'b000};
                            else if ( EN_Burst && Burst_Length==16 && Address[3:0]==4'b1111 )
                                Address = {Address[A_MSB:4], 4'b0000};
                            else if ( EN_Burst && Burst_Length==32 && Address[4:0]==5'b1_1111 )
                                Address = {Address[A_MSB:5], 5'b0_0000};
                            else if ( EN_Burst && Burst_Length==64 && Address[5:0]==6'b11_1111 )
                                Address = {Address[A_MSB:6], 6'b00_0000};
                            else
                                Address = Address + 1;
                        	end
                        else if (BurstRead_Mode) begin
                            if (Param_wrap_length == 2'b00 && Address[2:0]==3'b111) 
                                Address = {Address[A_MSB:3], 3'b000};
                            else if ( Param_wrap_length == 2'b01 && Address[3:0]==4'b1111 )
                                Address = {Address[A_MSB:4], 4'b0000};
                            else if ( Param_wrap_length == 2'b10 && Address[4:0]==5'b1_1111 )
                                Address = {Address[A_MSB:5], 5'b0_0000};
                            else if ( Param_wrap_length == 2'b11 && Address[5:0]==6'b11_1111 )
                                Address = {Address[A_MSB:6], 6'b00_0000};
                            else
                                Address = Address + 1;
                        	end
                        else
                            Address = Address + 1;
                        load_address(Address);
                        read_array(Address, OUT_Buf);
                        if ((WordRead_Mode && Addr_E7H != 1'b0) || (OctalRead_Mode && Addr_E3H[3:0])) begin
                            OUT_Buf = 8'hxx;
                        end
                        {SIO3_Reg, SIO2_Reg, SIO1_Reg, SIO0_Reg, OUT_Buf} <= {OUT_Buf, OUT_Buf[3:0]};
                        Dummy_Count = 1 ;
                    end
                end
            end//forever  
        end
    endtask // read_4xio


    /*----------------------------------------------------------------------*/
    /*  Description: define a fast read dual output data task               */
    /*               3B AD1 AD2 AD3 X                                       */
    /*----------------------------------------------------------------------*/
    task fastread_2xio;
        integer Dummy_Count;
        reg  [7:0] OUT_Buf;
        begin
            Dummy_Count = 4 ;
            dummy_cycle(32);
            read_array(Address, OUT_Buf);
            forever @ ( negedge ISCLK or  posedge CS_INT ) begin
                if ( CS_INT == 1'b1 ) begin
                    disable fastread_2xio;
                end
                else begin
                    Read_Mode= 1'b1;
                    SO_OUT_EN = 1'b1;
                    SI_OUT_EN = 1'b1;
                    SI_IN_EN  = 1'b0;
                    SO_IN_EN  = 1'b0;
                    if ( Dummy_Count ) begin
                        {SIO1_Reg, SIO0_Reg, OUT_Buf} <= {OUT_Buf, OUT_Buf[1:0]};
                        Dummy_Count = Dummy_Count - 1;
                    end
                    else begin
                        Address = Address + 1;
                        load_address(Address);
                        read_array(Address, OUT_Buf);
                        {SIO1_Reg, SIO0_Reg, OUT_Buf} <= {OUT_Buf, OUT_Buf[1:0]};
                        Dummy_Count = 3 ;
                    end
                end
            end//forever  
        end
    endtask // fastread_2xio

    /*----------------------------------------------------------------------*/
    /*  Description: define a fast read quad output data task               */
    /*               6B AD1 AD2 AD3 X                                       */
    /*----------------------------------------------------------------------*/
    task fastread_4xio;
        integer Dummy_Count;
        reg  [7:0]  OUT_Buf;
        begin
            Dummy_Count = 2 ;
            dummy_cycle(32);
            read_array(Address, OUT_Buf);
            forever @ ( negedge ISCLK or  posedge CS_INT ) begin
                if ( CS_INT ==      1'b1 ) begin
                    disable fastread_4xio;
                end
                else begin
                    SI_IN_EN    = 1'b0;
                    SI_OUT_EN   = 1'b1;
                    SO_OUT_EN   = 1'b1;
                    WP_OUT_EN   = 1'b1;
                    SIO3_OUT_EN = 1'b1;
                    if ( Dummy_Count ) begin
                        {SIO3_Reg, SIO2_Reg, SIO1_Reg, SIO0_Reg, OUT_Buf} <= {OUT_Buf, OUT_Buf[3:0]};                       
                         Dummy_Count = Dummy_Count - 1;
                    end
                    else begin
                        Address = Address + 1;
                        load_address(Address);
                        read_array(Address, OUT_Buf);
                        {SIO3_Reg, SIO2_Reg, SIO1_Reg, SIO0_Reg, OUT_Buf} <= {OUT_Buf, OUT_Buf[3:0]};
                        Dummy_Count = 1 ;
                    end
                end
            end//forever
        end
    endtask // fastread_4xio

    /*----------------------------------------------------------------------*/
    /*  Description: define read array output task                          */
    /*----------------------------------------------------------------------*/
    task read_array;
        input [A_MSB:0] Address;
        output [7:0]    OUT_Buf;
        reg    [9:0]    Secur_Add;
        begin
            if ( RDSCUR_Mode == 1 ) begin
                Secur_Add = Address[9:0];
                if (Address[A_MSB:12] == 1)      OUT_Buf = Secur_ARRAY1[Secur_Add];
                else if (Address[A_MSB:12] == 2) OUT_Buf = Secur_ARRAY2[Secur_Add];
                else if (Address[A_MSB:12] == 3) OUT_Buf = Secur_ARRAY3[Secur_Add];
            end
            else if ( SFDP_Mode == 1 ) begin
                OUT_Buf = SFDP_ARRAY[Address];
            end
            else begin
                OUT_Buf = ARRAY[Address] ;
            end
        end
    endtask //  read_array

    /*----------------------------------------------------------------------*/
    /*  Description: define read array output task                          */
    /*----------------------------------------------------------------------*/
    task load_address;
        inout [A_MSB:0] Address;
        begin
            if ( RDSCUR_Mode == 1 ) begin
                Address = Address[A_MSB:0] ;
            end
            else if ( SFDP_Mode == 1 ) begin
                Address = Address[A_MSB_SFDP:0] ;
            end
        end
    endtask //  load_address

    /*----------------------------------------------------------------------*/
    /*  Description: define a write_protect area function                   */
    /*  INPUT: address                                                      */
    /*----------------------------------------------------------------------*/ 
    function write_protect;
        input [A_MSB:0] Address;
        reg [Block_MSB:0] Block;
        reg [3:0]         Sector_Name;
        begin
            //protect_define
            if( ERSCUR_Mode == 1'b0 && PRSCUR_Mode == 1'b0  && CR_WPS == 1'b0) begin
                Block  =  Address [A_MSB:16];
                if ( SREG_CMP == 1'b0 ) begin  
                  if (SREG_BP[2:0] == 3'b000) begin
                      write_protect = 1'b0;
                  end
                  else if (SREG_BP[4:0] == 5'b00001) 
                      write_protect = (Block[Block_MSB:0] == 63 );
                  else if (SREG_BP[4:0] == 5'b00010) 
                      write_protect = (Block[Block_MSB:0] >= 62 && Block[Block_MSB:0] <= 63);
                  else if (SREG_BP[4:0] == 5'b00011) 
                      write_protect = (Block[Block_MSB:0] >= 60 && Block[Block_MSB:0] <= 63);
                  else if (SREG_BP[4:0] == 5'b00100) 
                      write_protect = (Block[Block_MSB:0] >= 56 && Block[Block_MSB:0] <= 63);
                  else if (SREG_BP[4:0] == 5'b00101) 
                      write_protect = (Block[Block_MSB:0] >= 48 && Block[Block_MSB:0] <= 63);
                  else if (SREG_BP[4:0] == 5'b00110) 
                      write_protect = (Block[Block_MSB:0] >= 32 && Block[Block_MSB:0] <= 63);
                  else if (SREG_BP[4:0] == 5'b01001) 
                      write_protect = (Block[Block_MSB:0] == 0);
                  else if (SREG_BP[4:0] == 5'b01010) 
                      write_protect = (Block[Block_MSB:0] >= 0 && Block[Block_MSB:0] <= 1); 
                  else if (SREG_BP[4:0] == 5'b01011) 
                      write_protect = (Block[Block_MSB:0] >= 0 && Block[Block_MSB:0] <= 3);
                  else if (SREG_BP[4:0] == 5'b01100) 
                      write_protect = (Block[Block_MSB:0] >= 0 && Block[Block_MSB:0] <= 7);
                  else if (SREG_BP[4:0] == 5'b01101) 
                      write_protect = (Block[Block_MSB:0] >= 0 && Block[Block_MSB:0] <= 15);
                  else if (SREG_BP[4:0] == 5'b01110) 
                      write_protect = (Block[Block_MSB:0] >= 0 && Block[Block_MSB:0] <= 31);
                  else if (SREG_BP[2:0] == 3'b111) 
                      write_protect = (Block[Block_MSB:0] >= 0 && Block[Block_MSB:0] <= 63);
                  // protection within block 63
                  else if (SREG_BP[4:0] == 5'b10001) 
                      write_protect = (Block[Block_MSB:0] == 63 && Address[15:12] == 4'b1111);
                  else if (SREG_BP[4:0] == 5'b10010) 
                      write_protect = (Block[Block_MSB:0] == 63 && Address[15:13] == 3'b111);
                  else if (SREG_BP[4:0] == 5'b10011) 
                      write_protect = (Block[Block_MSB:0] == 63 && Address[15:14] == 2'b11);
                  else if (SREG_BP[4:1] == 4'b1010) 
                      write_protect = (Block[Block_MSB:0] == 63 && Address[15] == 1'b1);
                  else if (SREG_BP[4:0] == 5'b10110) 
                      write_protect = (Block[Block_MSB:0] == 63 && Address[15] == 1'b1);
                  // protection within block 0
                  else if (SREG_BP[4:0] == 5'b11001) 
                      write_protect = (Block[Block_MSB:0] == 0 && Address[15:12] == 4'b0000);
                  else if (SREG_BP[4:0] == 5'b11010) 
                      write_protect = (Block[Block_MSB:0] == 0 && Address[15:13] == 3'b000);
                  else if (SREG_BP[4:0] == 5'b11011) 
                      write_protect = (Block[Block_MSB:0] == 0 && Address[15:14] == 2'b00);
                  else if (SREG_BP[4:1] == 4'b1110) 
                      write_protect = (Block[Block_MSB:0] == 0 && Address[15] == 1'b0);
                  else if (SREG_BP[4:0] == 5'b11110) 
                      write_protect = (Block[Block_MSB:0] == 0 && Address[15] == 1'b0);
                  else
                      write_protect = 1'b1;
                end // if (CMP==1'b0)
                else begin
                  if (SREG_BP[2:0] == 3'b111) begin
                      write_protect = 1'b0;
                  end
                  else if (SREG_BP[2:0] == 3'b000) 
                      write_protect = 1'b1; 
                  else if (SREG_BP[4:0] == 5'b00001) 
                      write_protect = (Block[Block_MSB:0] < 63 );
                  else if (SREG_BP[4:0] == 5'b00010) 
                      write_protect = (Block[Block_MSB:0] < 62 );
                  else if (SREG_BP[4:0] == 5'b00011) 
                      write_protect = (Block[Block_MSB:0] < 60 );
                  else if (SREG_BP[4:0] == 5'b00100) 
                      write_protect = (Block[Block_MSB:0] < 56 );
                  else if (SREG_BP[4:0] == 5'b00101) 
                      write_protect = (Block[Block_MSB:0] < 48 );
                  else if (SREG_BP[4:0] == 5'b00110) 
                      write_protect = (Block[Block_MSB:0] < 32 );
                  // upper
                  else if (SREG_BP[4:0] == 5'b01001) 
                      write_protect = (Block[Block_MSB:0] > 0 );
                  else if (SREG_BP[4:0] == 5'b01010) 
                      write_protect = (Block[Block_MSB:0] > 1 );
                  else if (SREG_BP[4:0] == 5'b01011) 
                      write_protect = (Block[Block_MSB:0] > 3 );
                  else if (SREG_BP[4:0] == 5'b01100) 
                      write_protect = (Block[Block_MSB:0] > 7 );
                  else if (SREG_BP[4:0] == 5'b01101) 
                      write_protect = (Block[Block_MSB:0] > 15 );
                  else if (SREG_BP[4:0] == 5'b01110) 
                      write_protect = (Block[Block_MSB:0] > 31 );
                   // lower 0~31
                  else if (SREG_BP[4:0] == 5'b10001) 
                      //write_protect = Address[A_MSB:12] > {(A_MSB-11){1'b1}}; 
                      write_protect = Address[A_MSB:12] < 10'b11_1111_1111; 
                  else if (SREG_BP[4:0] == 5'b10010) 
                      //write_protect = Address[A_MSB:12] > {(A_MSB-12){1'b1}}; 
                      write_protect = Address[A_MSB:12] < 10'b11_1111_1110; 
                  else if (SREG_BP[4:0] == 5'b10011) 
                      //write_protect = Address[A_MSB:12] > {(A_MSB-13){1'b1}}; 
                      write_protect = Address[A_MSB:12] < 10'b11_1111_1100; 
                  else if (SREG_BP[4:1] == 4'b1010) 
                      //write_protect = Address[A_MSB:12] > {(A_MSB-14){1'b1}}; 
                      write_protect = Address[A_MSB:12] < 10'b11_1111_1000; 
                  else if (SREG_BP[4:0] == 5'b10110) 
                      //write_protect = Address[A_MSB:12] > {(A_MSB-14){1'b1}}; 
                      write_protect = Address[A_MSB:12] < 10'b11_1111_1000; 
                  // protection within block 0
                  else if (SREG_BP[4:0] == 5'b11001) 
                      write_protect = !( Address[A_MSB:12]  == 0 );
                  else if (SREG_BP[4:0] == 5'b11010) 
                      write_protect = !( Address[A_MSB:13]  == 0 );
                  else if (SREG_BP[4:0] == 5'b11011) 
                      write_protect = !( Address[A_MSB:14]  == 0 );
                  else if (SREG_BP[4:1] == 4'b1110) 
                      write_protect = !( Address[A_MSB:15]  == 0 );
                  else if (SREG_BP[4:0] == 5'b11110) 
                      write_protect = !( Address[A_MSB:15]  == 0 );
                  else
                      write_protect = 1'b1;
                end  
            end 

            else if( ERSCUR_Mode == 1'b0 && PRSCUR_Mode == 1'b0  && CR_WPS == 1'b1) begin
                Block  =  Address [A_MSB:16];
                if (Block == 6'b000000) begin
                    Sector_Name = Address[15:12];
                    if ( BE32K_Mode) 
                      write_protect = Sector_Name[3]? (Block0_SL_Reg[15:8] != 8'h00):(Block0_SL_Reg[7:0] != 8'h00);
                    else if ( BE64K_Mode) 
                      write_protect = (Block0_SL_Reg[15:0] != 16'h0000);
		    else
                      write_protect = Block0_SL_Reg[Sector_Name];
                end
                else if (Block == 6'b111111) begin
                    Sector_Name = Address[15:12];
                    if ( BE32K_Mode) 
                      write_protect = Sector_Name[3]? (Block63_SL_Reg[15:8] != 8'h00):(Block63_SL_Reg[7:0] != 8'h00);
                    else if ( BE64K_Mode) 
                      write_protect = (Block63_SL_Reg[15:0] != 16'h0000);
                    else
                      write_protect = Block63_SL_Reg[Sector_Name];
                end
                else begin
                    write_protect = Block_Lock_Reg[Block];
                end
                $display("Block is %x sector is %x write_protect is %x\n", Block, Sector_Name, write_protect);
            end

            // for security registers, it's write protect is determined by LB3~LB1
            else if( ERSCUR_Mode == 1'b1 || PRSCUR_Mode == 1'b1 ) begin
                if      ( SREG_LB3 == 1'b1 && Address[A_MSB:12] == 3 ) write_protect = 1'b1;
                else if ( SREG_LB2 == 1'b1 && Address[A_MSB:12] == 2 ) write_protect = 1'b1;
                else if ( SREG_LB1 == 1'b1 && Address[A_MSB:12] == 1 ) write_protect = 1'b1;
                else write_protect = 1'b0;
            end
            else begin
                write_protect = 1'b0;
            end
        end
    endfunction // write_protect


    /*----------------------------------------------------------------------*/
    /*  Description: define single block lock                               */
    /*----------------------------------------------------------------------*/
    task single_block_lock;
        //input [A_MSB:0]     Address;
        reg   [Block_MSB:0] block_name;  // total 64 blocks in P25Q32H
        reg   [3:0]         sector_name;   // total 16 sector in one block
        begin
            // detect whether block0/63 or other blocks
            block_name = Address[A_MSB:16];
            sector_name = Address[15:12];
            $display("!DEBUG: block %d is being locked, sector is %d\n", block_name, sector_name);

            case (block_name)
                6'b000000:  // block 0, process sector info
                    begin
                        Block0_SL_Reg[sector_name] = 1'b1;
                    end
                6'b111111:  // block 63, process sector info
                    begin
                        Block63_SL_Reg[sector_name] = 1'b1;
                    end
                default:  // block 1-62, process block
                    begin
                        Block_Lock_Reg[block_name] = 1'b1;
                    end
            endcase
        end
    endtask //  single_block_unlock


    /*----------------------------------------------------------------------*/
    /*  Description: define single block unlock                               */
    /*----------------------------------------------------------------------*/
    task single_block_unlock;
        //input [A_MSB:0]     Address;
        reg   [Block_MSB:0] block_name;  // total 64 blocks in P25Q32H
        reg   [3:0]         sector_name;   // total 16 sector in one block
        begin
            // detect whether block0/63 or other blocks
            block_name = Address[A_MSB:16];
            sector_name = Address[15:12];

            $display("!DEBUG: block %d is being unlocked, sector is %d\n", block_name, sector_name);

            case (block_name)
                6'b000000:  // block 0, process sector info
                    begin
                        Block0_SL_Reg[sector_name] = 1'b0;
                    end
                6'b111111:  // block 63, process sector info
                    begin
                        Block63_SL_Reg[sector_name] = 1'b0;
                    end
                default:  // block 1-62, process block
                    begin
                        Block_Lock_Reg[block_name] = 1'b0;
                    end
            endcase
        end
    endtask //  single_block_unlock


    /*----------------------------------------------------------------------*/
    /*  Description: define global block lock                               */
    /*----------------------------------------------------------------------*/
    task global_block_lock;
        begin
            Block0_SL_Reg[15:0]  = 16'hffff;
            Block63_SL_Reg[15:0] = 16'hffff;
            Block_Lock_Reg[62:1] = 62'h3fff_ffff_ffff_ffff;
        end
    endtask //  global_block_lock


    /*----------------------------------------------------------------------*/
    /*  Description: define global block unlock                               */
    /*----------------------------------------------------------------------*/
    task global_block_unlock;
        begin
            Block0_SL_Reg[15:0]  = 16'h0;
            Block63_SL_Reg[15:0] = 16'h0;
            Block_Lock_Reg[62:1] = 62'h0;
        end
    endtask //  global_block_unlock

    /*----------------------------------------------------------------------*/
    /*  Description: read block lock                                      */
    /*----------------------------------------------------------------------*/
    task read_block_lock;
        reg[7:0]  lock_stat;
        reg   [Block_MSB:0] block_name;  // total 64 blocks in P25Q32H
        reg   [3:0]         sector_name;   // total 16 sector in one block
        integer Dummy_Count;
        begin
            // detect whether block0/63 or other blocks
            block_name = Address[A_MSB:16];
            sector_name = Address[15:12];


            lock_stat = 8'h1;

            case (block_name)
                6'b000000:  // block 0, process sector info
                    begin
                        lock_stat[0] = Block0_SL_Reg[sector_name];
                    end
                6'b111111:  // block 63, process sector info
                    begin
                        lock_stat[0] = Block63_SL_Reg[sector_name];
                    end
                default:  // block 1-62, process block
                    begin
                        lock_stat[0] = Block_Lock_Reg[block_name];
                    end
            endcase

            if (CR_WPS == 1'b0)
                lock_stat[0] = 1'bx;   // when WPS=0, we will return x value
            // Output lock status
            if ( QPI_Mode ) 
                 Dummy_Count = 2;
            else Dummy_Count = 8;
            forever begin
                @ ( negedge ISCLK or posedge CS_INT );
                if ( CS_INT == 1'b1 ) begin
                    disable read_block_lock;
                end
                else begin
                    if ( QPI_Mode ) begin
                        SI_OUT_EN   = 1'b1;
                        WP_OUT_EN   = 1'b1;
                        SIO3_OUT_EN = 1'b1;
                    end
                    SO_OUT_EN = 1'b1;
                    SO_IN_EN  = 1'b0;
                    SI_IN_EN  = 1'b0;
                    WP_IN_EN  = 1'b0;
                    SIO3_IN_EN= 1'b0;

                    if ( Dummy_Count ) begin
                        Dummy_Count = Dummy_Count - 1;
                        if (QPI_Mode) begin
                            {SIO3_Reg, SIO2_Reg, SIO1_Reg, SIO0_Reg} <= Dummy_Count ? lock_stat[7:4] : lock_stat[3:0];
                        end else
                            SIO1_Reg    <= lock_stat[Dummy_Count];
                    end
                    else begin
                        if ( QPI_Mode ) begin
                            Dummy_Count = 1;
                            {SIO3_Reg, SIO2_Reg, SIO1_Reg, SIO0_Reg} <= lock_stat[7:4];
                        end else begin
                            Dummy_Count = 7;
                            SIO1_Reg    <= lock_stat[Dummy_Count];
                        end
                    end          
                end
            end  // end forever
        end
    endtask //  global_unlock





// *============================================================================================== 
// * AC Timing Check Section
// *==============================================================================================
    wire SIO3_EN;
    wire WP_EN;
    assign SIO3_EN = !SREG_QE; //!Status_Reg[6];
    assign WP_EN = !SREG_QE && SRWD; // (!Status_Reg[6]) && SRWD; // TODO: check condition
    assign  Write_SHSL = !Read_SHSL;

    wire Read_1XIO_Chk_W;
    assign Read_1XIO_Chk_W = Read_1XIO_Chk;

    wire Read_2XIO_Chk_W_H;
    assign Read_2XIO_Chk_W_H = Read_2XIO_Chk && (!Low_Power_Mode);
    wire Read_2XIO_Chk_W_L;
    assign Read_2XIO_Chk_W_L = Read_2XIO_Chk && Low_Power_Mode;

    wire FastRD_2XIO_Chk_W_H;
    assign FastRD_2XIO_Chk_W_H = FastRD_2XIO_Chk && (!Low_Power_Mode);
    wire FastRD_2XIO_Chk_W_L;
    assign FastRD_2XIO_Chk_W_L = FastRD_2XIO_Chk && Low_Power_Mode;

    wire Read_4XIO_Chk_W_H;
    assign Read_4XIO_Chk_W_H = Read_4XIO_Chk && (!Low_Power_Mode);
    wire Read_4XIO_Chk_W_L;
    assign Read_4XIO_Chk_W_L = Read_4XIO_Chk && Low_Power_Mode;


    wire FastRD_4XIO_Chk_W_H;
    assign FastRD_4XIO_Chk_W_H = FastRD_4XIO_Chk && (!Low_Power_Mode);
    wire FastRD_4XIO_Chk_W_L;
    assign FastRD_4XIO_Chk_W_L = FastRD_4XIO_Chk && Low_Power_Mode;

    wire tDP_Chk_W;
    assign tDP_Chk_W = tDP_Chk;

    wire tWRSR_Chk_W;
    assign tWRSR_Chk_W = tWRSR_Chk;
    wire tWRCR_Chk_W;
    assign tWRCR_Chk_W = tWRCR_Chk;

    wire tRES1_Chk_W;
    assign tRES1_Chk_W = tRES1_Chk;

    wire PP_4XIO_Chk_W;
    assign PP_4XIO_Chk_W = PP_4XIO_Chk;
    wire PP_4XIO_Chk_W_H;
    assign PP_4XIO_Chk_W_H = PP_4XIO_Chk && (!Low_Power_Mode);
    wire PP_4XIO_Chk_W_L;
    assign PP_4XIO_Chk_W_L = PP_4XIO_Chk && Low_Power_Mode;

    wire DPP_1XIO_Chk_W;
    assign DPP_1XIO_Chk_W = DPP_1XIO_Chk;


    wire Read_SHSL_W;
    assign Read_SHSL_W = Read_SHSL;

    wire SI_IN_EN_W;
    assign SI_IN_EN_W = SI_IN_EN;
    wire SO_IN_EN_W;
    assign SO_IN_EN_W = SO_IN_EN;
    wire WP_IN_EN_W;
    assign WP_IN_EN_W = WP_IN_EN;
    wire SIO3_IN_EN_W;
    assign SIO3_IN_EN_W = SIO3_IN_EN;

    wire SCLK_Chk_H;
    assign SCLK_Chk_H = ~CSb && ~Low_Power_Mode;
    wire SCLK_Chk_L;
    assign SCLK_Chk_L = ~CSb && Low_Power_Mode;

    specify
        /*----------------------------------------------------------------------*/
        /*  Timing Check                                                        */
        /*----------------------------------------------------------------------*/
        $period( posedge  SCLK &&& SCLK_Chk_H, tSCLK_H  );      // SCLK _/~ ->_/~
        $period( negedge  SCLK &&& SCLK_Chk_H, tSCLK_H  );      // SCLK ~\_ ->~\_
        $period( posedge  SCLK &&& SCLK_Chk_L, tSCLK_L  );      // SCLK _/~ ->_/~
        $period( negedge  SCLK &&& SCLK_Chk_L, tSCLK_L  );      // SCLK ~\_ ->~\_
        $period( posedge  SCLK &&& Read_1XIO_Chk_W , tRSCLK ); // SCLK _/~ ->_/~
        $period( posedge  SCLK &&& Read_2XIO_Chk_W_H , tTSCLK_H ); // SCLK _/~ ->_/~
        $period( posedge  SCLK &&& Read_2XIO_Chk_W_L , tTSCLK_L ); // SCLK _/~ ->_/~
        $period( posedge  SCLK &&& FastRD_2XIO_Chk_W_H, tTSCLK1_H ); // SCLK _/~ ->_/~
        $period( posedge  SCLK &&& FastRD_2XIO_Chk_W_L, tTSCLK1_L ); // SCLK _/~ ->_/~
        $period( posedge  SCLK &&& Read_4XIO_Chk_W_H , tQSCLK_H ); // SCLK _/~ ->_/~
        $period( posedge  SCLK &&& Read_4XIO_Chk_W_L , tQSCLK_L ); // SCLK _/~ ->_/~
        $period( posedge  SCLK &&& FastRD_4XIO_Chk_W_H, tQSCLK1_H ); // SCLK _/~ ->_/~
        $period( posedge  SCLK &&& FastRD_4XIO_Chk_W_L, tQSCLK1_L ); // SCLK _/~ ->_/~
        $period( posedge  SCLK &&& PP_4XIO_Chk_W_H, t4PP_H ); // SCLK _/~ ->_/~
        $period( posedge  SCLK &&& PP_4XIO_Chk_W_L, t4PP_L ); // SCLK _/~ ->_/~
        $period( posedge  SCLK &&& DPP_1XIO_Chk_W, tTSCLK_H); // SCLK _/~ ->_/~

        $period( posedge  SCLK &&& tWRSR_Chk_W, tSCLK_WRSR  );  // SCLK _/~ ->_/~
        $period( negedge  SCLK &&& tWRSR_Chk_W, tSCLK_WRSR  );  // SCLK ~\_ ->~\_

        $period( posedge  SCLK &&& tWRCR_Chk_W, tSCLK_WRCR  );  // SCLK _/~ ->_/~
        $period( negedge  SCLK &&& tWRCR_Chk_W, tSCLK_WRCR  );  // SCLK ~\_ ->~\_

        $width ( posedge  CSb  &&& tDP_Chk_W, tDP );       // CSb _/~\_
        $width ( posedge  CSb  &&& tRES1_Chk_W, tRES1 );   // CSb _/~\_

        $width ( posedge  SCLK &&& SCLK_Chk_H, tCH_H   );       // SCLK _/~~\_
        $width ( negedge  SCLK &&& SCLK_Chk_H, tCL_H   );       // SCLK ~\__/~
        $width ( posedge  SCLK &&& SCLK_Chk_L, tCH_L   );       // SCLK _/~~\_
        $width ( negedge  SCLK &&& SCLK_Chk_L, tCL_L   );       // SCLK ~\__/~
        $width ( posedge  SCLK &&& Read_1XIO_Chk_W, tCH_R   );       // SCLK _/~~\_
        $width ( negedge  SCLK &&& Read_1XIO_Chk_W, tCL_R   );       // SCLK ~\__/~
        $width ( posedge  SCLK &&& PP_4XIO_Chk_W_H, tCH_H   );       // SCLK _/~~\_
        $width ( negedge  SCLK &&& PP_4XIO_Chk_W_H, tCL_H   );       // SCLK ~\__/~
        $width ( posedge  SCLK &&& PP_4XIO_Chk_W_L, tCH_L   );       // SCLK _/~~\_
        $width ( negedge  SCLK &&& PP_4XIO_Chk_W_L, tCL_L   );       // SCLK ~\__/~

        $width ( posedge  CSb  &&& Read_SHSL_W, tSHSL_R );       // CSb _/~\_
        $width ( posedge  CSb  &&& Write_SHSL, tSHSL_W );// CSb _/~\_
        $setup ( SI &&& ~CSb, posedge SCLK &&& SI_IN_EN_W,  tDVCH );
        $hold  ( posedge SCLK &&& SI_IN_EN_W, SI &&& ~CSb,  tCHDX );

        $setup ( SO &&& ~CSb, posedge SCLK &&& SO_IN_EN_W,  tDVCH );
        $hold  ( posedge SCLK &&& SO_IN_EN_W, SO &&& ~CSb,  tCHDX );
        $setup ( WPb &&& ~CSb, posedge SCLK &&& WP_IN_EN_W,  tDVCH );
        $hold  ( posedge SCLK &&& WP_IN_EN_W, WPb &&& ~CSb,  tCHDX );

        $setup ( SIO3 &&& ~CSb, posedge SCLK &&& SIO3_IN_EN_W,  tDVCH );
        $hold  ( posedge SCLK &&& SIO3_IN_EN_W, SIO3 &&& ~CSb,  tCHDX );

        $setup    ( negedge CSb, posedge SCLK &&& ~CSb, tSLCH );
        $hold     ( posedge SCLK &&& ~CSb, posedge CSb, tCHSH );
     
        $setup    ( posedge CSb, posedge SCLK &&& CSb, tSHCH );
        $hold     ( posedge SCLK &&& CSb, negedge CSb, tCHSL );

        $setup ( posedge WPb &&& WP_EN, negedge CSb,  tWHSL );
        $hold  ( posedge CSb, negedge WPb &&& WP_EN,  tSHWL );

        $setup ( negedge HOLD_B_INT , posedge SCLK &&& ~CSb,  tHLCH );
        $hold  ( posedge SCLK &&& ~CSb, posedge HOLD_B_INT ,  tCHHH );
        $setup ( posedge HOLD_B_INT , posedge SCLK &&& ~CSb,  tHHCH );
        $hold  ( posedge SCLK &&& ~CSb, negedge HOLD_B_INT ,  tCHHL );

        $width ( negedge  RESETB_INT, tRLRH   );      // RESET ~\__/~
        $setup ( posedge CSb, negedge RESETB_INT ,  tRS );
        $hold  ( negedge RESETB_INT, posedge CSb ,  tRH );
        $hold  ( posedge  RESETB_INT, negedge CSb, tRHSL );



     endspecify

    integer AC_Check_File;
    // timing check module 
    initial 
    begin 
        AC_Check_File= $fopen ("ac_check.err" );    
    end

    realtime  T_CS_P , T_CS_N;
    realtime  T_WP_P , T_WP_N;
    realtime  T_SCLK_P , T_SCLK_N;
    realtime  T_SIO3_P , T_SIO3_N;
    realtime  T_SI;
    realtime  T_SO;
    realtime  T_WP;
    realtime  T_SIO3;
    realtime  T_HOLD_P , T_HOLD_N;    

    initial 
    begin
        T_CS_P = 0; 
        T_CS_N = 0;
        T_WP_P = 0;  
        T_WP_N = 0;
        T_SCLK_P = 0;  
        T_SCLK_N = 0;
        T_SIO3_P = 0;  
        T_SIO3_N = 0;
        T_SI = 0;
        T_SO = 0;
        T_WP = 0;
        T_SIO3 = 0;
        T_HOLD_P = 0;
        T_HOLD_N = 0;
    end

    always @ ( posedge SCLK ) begin
        //tSCLK_WRSR
        if ( $realtime - T_SCLK_P < tSCLK_WRSR && tWRSR_Chk && $realtime > 0 && ~CSb ) 
            $fwrite (AC_Check_File, "Clock Frequence when issuing WRSR for performance switch fSCLK_WRSR =%f Mhz, fSCLK_WRSR timing violation at %f \n", fSCLK_WRSR, $realtime );
        if ( $realtime - T_SCLK_P < tSCLK_WRCR && tWRCR_Chk && $realtime > 0 && ~CSb ) 
            $fwrite (AC_Check_File, "Clock Frequence when issuing WRCR for performance switch fSCLK_WRCR =%f Mhz, fSCLK_WRCR timing violation at %f \n", fSCLK_WRCR, $realtime );
        //tSCLK_H
        if ( $realtime - T_SCLK_P < tSCLK_H && ~Low_Power_Mode && $realtime > 0 && ~CSb ) 
            $fwrite (AC_Check_File, "Clock Frequence for except READ instruction fSCLK =%f Mhz, fSCLK timing violation at %f \n", fSCLK_H, $realtime );
        //tSCLK_L
        if ( $realtime - T_SCLK_P < tSCLK_L && Low_Power_Mode && $realtime > 0 && ~CSb ) 
            $fwrite (AC_Check_File, "Clock Frequence for except READ instruction fSCLK =%f Mhz, fSCLK timing violation at %f \n", fSCLK_L, $realtime );
        //fRSCLK
        if ( $realtime - T_SCLK_P < tRSCLK && Read_1XIO_Chk && $realtime > 0 && ~CSb )
            $fwrite (AC_Check_File, "Clock Frequence for READ instruction fRSCLK =%f Mhz, fRSCLK timing violation at %f \n", fRSCLK, $realtime );
        //fTSCLK_H
        if ( $realtime - T_SCLK_P < tTSCLK_H && Read_2XIO_Chk_W_H && $realtime > 0 && ~CSb )
            $fwrite (AC_Check_File, "Clock Frequence for 2XI/O instruction fTSCLK_H =%f Mhz, fTSCLK_H timing violation at %f \n", fTSCLK_H, $realtime );
        //fTSCLK_L
        if ( $realtime - T_SCLK_P < tTSCLK_L && Read_2XIO_Chk_W_L && $realtime > 0 && ~CSb )
            $fwrite (AC_Check_File, "Clock Frequence for 2XI/O instruction fTSCLK_L =%f Mhz, fTSCLK_H timing violation at %f \n", fTSCLK_L, $realtime );
        //fTSCLK1_H
        if ( $realtime - T_SCLK_P < tTSCLK1_H && FastRD_2XIO_Chk_W_H && $realtime > 0 && ~CSb )
            $fwrite (AC_Check_File, "Clock Frequence for 1I/2O instruction fTSCLK1_H =%f Mhz, fTSCLK1_H timing violation at %f \n", fTSCLK1_H, $realtime );
        //fTSCLK1_L
        if ( $realtime - T_SCLK_P < tTSCLK1_L && FastRD_2XIO_Chk_W_L && $realtime > 0 && ~CSb )
            $fwrite (AC_Check_File, "Clock Frequence for 1I/2O instruction fTSCLK1_L =%f Mhz, fTSCLK1_L timing violation at %f \n", fTSCLK1_L, $realtime );
        //fQSCLK_H
        if ( $realtime - T_SCLK_P < tQSCLK_H && Read_4XIO_Chk_W_H && $realtime > 0 && ~CSb )
            $fwrite (AC_Check_File, "Clock Frequence for 4XI/O instruction fQSCLK =%f Mhz, fQSCLK timing violation at %f \n", fQSCLK_H, $realtime );
        //fQSCLK_L
        if ( $realtime - T_SCLK_P < tQSCLK_L && Read_4XIO_Chk_W_L && $realtime > 0 && ~CSb )
            $fwrite (AC_Check_File, "Clock Frequence for 4XI/O instruction fQSCLK =%f Mhz, fQSCLK timing violation at %f \n", fQSCLK_L, $realtime );
        //fQSCLK1_H
        if ( $realtime - T_SCLK_P < tQSCLK1_H && FastRD_4XIO_Chk_W_H && $realtime > 0 && ~CSb )
            $fwrite (AC_Check_File, "Clock Frequence for 1I/4O instruction fQSCLK1 =%f Mhz, fQSCLK1 timing violation at %f \n", fQSCLK1_H, $realtime );
        //fQSCLK1_L
        if ( $realtime - T_SCLK_P < tQSCLK1_L && FastRD_4XIO_Chk_W_L && $realtime > 0 && ~CSb )
            $fwrite (AC_Check_File, "Clock Frequence for 1I/4O instruction fQSCLK1 =%f Mhz, fQSCLK1 timing violation at %f \n", fQSCLK1_L, $realtime );
        //f4PP_H
        if ( $realtime - T_SCLK_P < t4PP_H && PP_4XIO_Chk_W_H && $realtime > 0 && ~CSb )
            $fwrite (AC_Check_File, "Clock Frequence for 4PP program instruction f4PP_H =%f Mhz, f4PP_H timing violation at %f \n", f4PP_H, $realtime );
        //f4PP_L
        if ( $realtime - T_SCLK_P < t4PP_L && PP_4XIO_Chk_W_L && $realtime > 0 && ~CSb )
            $fwrite (AC_Check_File, "Clock Frequence for 4PP program instruction f4PP_L =%f Mhz, f4PP_L timing violation at %f \n", f4PP_L, $realtime );


        T_SCLK_P = $realtime; 
        #0;  
        //tDVCH
        if ( T_SCLK_P - T_SI < tDVCH && SI_IN_EN && T_SCLK_P > 0 )
            $fwrite (AC_Check_File, "minimum Data SI setup time tDVCH=%f ns, tDVCH timing violation at %f \n", tDVCH, $realtime );
        if ( T_SCLK_P - T_SO < tDVCH && SO_IN_EN && T_SCLK_P > 0 )
            $fwrite (AC_Check_File, "minimum Data SO setup time tDVCH=%f ns, tDVCH timing violation at %f \n", tDVCH, $realtime );
        if ( T_SCLK_P - T_WP < tDVCH && WP_IN_EN && T_SCLK_P > 0 )
            $fwrite (AC_Check_File, "minimum Data WPb setup time tDVCH=%f ns, tDVCH timing violation at %f \n", tDVCH, $realtime );

        if ( T_SCLK_P - T_SIO3 < tDVCH && SIO3_IN_EN && T_SCLK_P > 0 )
            $fwrite (AC_Check_File, "minimum Data SIO3 setup time tDVCH=%f ns, tDVCH timing violation at %f \n", tDVCH, $realtime );

        //tCL_H
        if ( T_SCLK_P - T_SCLK_N < tCL_H && ~Low_Power_Mode && ~CSb && T_SCLK_P > 0 )
            $fwrite (AC_Check_File, "minimum SCLK Low time tCL_H=%f ns, tCL_H timing violation at %f \n", tCL_H, $realtime );
        if ( T_SCLK_P - T_SCLK_N < tCL_H && ~Low_Power_Mode && PP_4XIO_Chk && T_SCLK_P > 0 )
            $fwrite (AC_Check_File, "minimum SCLK Low time tCL_H=%f ns, tCL_H timing violation at %f \n", tCL_H, $realtime );

        //tCL_L
        if ( T_SCLK_P - T_SCLK_N < tCL_L && Low_Power_Mode && ~CSb && T_SCLK_P > 0 )
            $fwrite (AC_Check_File, "minimum SCLK Low time tCL_L=%f ns, tCL_L timing violation at %f \n", tCL_L, $realtime );
        if ( T_SCLK_P - T_SCLK_N < tCL_L && Low_Power_Mode && PP_4XIO_Chk && T_SCLK_P > 0 )
            $fwrite (AC_Check_File, "minimum SCLK Low time tCL_L=%f ns, tCL_L timing violation at %f \n", tCL_L, $realtime );

        //tCL_R
        if ( T_SCLK_P - T_SCLK_N < tCL_R && Read_1XIO_Chk && T_SCLK_P > 0 )
            $fwrite (AC_Check_File, "minimum SCLK Low time tCL=%f ns, tCL timing violation at %f \n", tCL_R, $realtime );
        #0;
        // tSLCH
        if ( T_SCLK_P - T_CS_N < tSLCH  && T_SCLK_P > 0 )
            $fwrite (AC_Check_File, "minimum CS# active setup time tSLCH=%f ns, tSLCH timing violation at %f \n", tSLCH, $realtime );

        // tSHCH
        if ( T_SCLK_P - T_CS_P < tSHCH  && T_SCLK_P > 0 )
            $fwrite (AC_Check_File, "minimum CS# not active setup time tSHCH=%f ns, tSHCH timing violation at %f \n", tSHCH, $realtime );
`ifdef HOLD_ENABLE
        //tHLCH
        if ( T_SCLK_P - T_HOLD_N < tHLCH && ~CSb  && T_SCLK_P > 0 )
            $fwrite (AC_Check_File, "minimum HOLD# setup time tHLCH=%f ns, tHLCH timing violation at %f \n", tHLCH, $realtime );

        //tHHCH
        if ( T_SCLK_P - T_HOLD_P < tHHCH && ~CSb  && T_SCLK_P > 0 )
            $fwrite (AC_Check_File, "minimum HOLD setup time tHHCH=%f ns, tHHCH timing violation at %f \n", tHHCH, $realtime );
`endif


    end

    always @ ( negedge SCLK ) begin
        T_SCLK_N = $realtime;
        #0; 
        //tCH_H
        if ( T_SCLK_N - T_SCLK_P < tCH_H && ~Low_Power_Mode && ~CSb && T_SCLK_N > 0 )
            $fwrite (AC_Check_File, "minimum SCLK High time tCH_H=%f ns, tCH_H timing violation at %f \n", tCH_H, $realtime );
        if ( T_SCLK_N - T_SCLK_P < tCH_H && ~Low_Power_Mode && PP_4XIO_Chk && T_SCLK_N > 0 )
            $fwrite (AC_Check_File, "minimum SCLK High time tCH_H=%f ns, tCH_H timing violation at %f \n", tCH_H, $realtime );

        //tCH_L
        if ( T_SCLK_N - T_SCLK_P < tCH_L && Low_Power_Mode && ~CSb && T_SCLK_N > 0 )
            $fwrite (AC_Check_File, "minimum SCLK High time tCH_L=%f ns, tCH_H timing violation at %f \n", tCH_L, $realtime );
        if ( T_SCLK_N - T_SCLK_P < tCH_L && Low_Power_Mode && PP_4XIO_Chk && T_SCLK_N > 0 )
            $fwrite (AC_Check_File, "minimum SCLK High time tCH_L=%f ns, tCH_H timing violation at %f \n", tCH_L, $realtime );

        //tCH_R
        if ( T_SCLK_N - T_SCLK_P < tCH_R && Read_1XIO_Chk && T_SCLK_N > 0 )
            $fwrite (AC_Check_File, "minimum SCLK High time tCH=%f ns, tCH timing violation at %f \n", tCH_R, $realtime );
    end


    always @ ( SI ) begin
        T_SI = $realtime; 
        #0;  
        //tCHDX
        if ( T_SI - T_SCLK_P < tCHDX && SI_IN_EN && T_SI > 0 )
            $fwrite (AC_Check_File, "minimum Data SI hold time tCHDX=%f ns, tCHDX timing violation at %f \n", tCHDX, $realtime );
    end

    always @ ( SO ) begin
        T_SO = $realtime; 
        #0;  
        //tCHDX
        if ( T_SO - T_SCLK_P < tCHDX && SO_IN_EN && T_SO > 0 )
            $fwrite (AC_Check_File, "minimum Data SO hold time tCHDX=%f ns, tCHDX timing violation at %f \n", tCHDX, $realtime );
    end

    always @ ( WPb ) begin
        T_WP = $realtime; 
        #0;  
        //tCHDX
        if ( T_WP - T_SCLK_P < tCHDX && WP_IN_EN && T_WP > 0 )
            $fwrite (AC_Check_File, "minimum Data WPb hold time tCHDX=%f ns, tCHDX timing violation at %f \n", tCHDX, $realtime );
    end

    always @ ( SIO3 ) begin
        T_SIO3 = $realtime; 
        #0;  
        //tCHDX
       if ( T_SIO3 - T_SCLK_P < tCHDX && SIO3_IN_EN && T_SIO3 > 0 )
            $fwrite (AC_Check_File, "minimum Data SIO3 hold time tCHDX=%f ns, tCHDX timing violation at %f \n", tCHDX, $realtime );
    end

    always @ ( posedge CSb ) begin
        T_CS_P = $realtime;
        #0;  
        // tCHSH 
        if ( T_CS_P - T_SCLK_P < tCHSH  && T_CS_P > 0 )
            $fwrite (AC_Check_File, "minimum CS# active hold time tCHSH=%f ns, tCHSH timing violation at %f \n", tCHSH, $realtime );
    end

    always @ ( negedge CSb ) begin
        T_CS_N = $realtime;
        #0;
        //tCHSL
        if ( T_CS_N - T_SCLK_P < tCHSL  && T_CS_N > 0 )
            $fwrite (AC_Check_File, "minimum CS# not active hold time tCHSL=%f ns, tCHSL timing violation at %f \n", tCHSL, $realtime );
        //tSHSL
        if ( T_CS_N - T_CS_P < tSHSL_R && T_CS_N > 0 && Read_SHSL)
            $fwrite (AC_Check_File, "minimum CS# deselect  time tSHSL_R=%f ns, tSHSL timing violation at %f \n", tSHSL_R, $realtime );
        if ( T_CS_N - T_CS_P < tSHSL_W && T_CS_N > 0 && Write_SHSL)
            $fwrite (AC_Check_File, "minimum CS# deselect  time tSHSL_W=%f ns, tSHSL timing violation at %f \n", tSHSL_W, $realtime );

        //tWHSL
        if ( T_CS_N - T_WP_P < tWHSL && WP_EN  && T_CS_N > 0 )
            $fwrite (AC_Check_File, "minimum WPb setup  time tWHSL=%f ns, tWHSL timing violation at %f \n", tWHSL, $realtime );


        //tDP
        if ( T_CS_N - T_CS_P < tDP && T_CS_N > 0 && tDP_Chk)
            $fwrite (AC_Check_File, "when transit from Standby Mode to Deep-Power Mode, CS# must remain high for at least tDP =%f ns, tDP timing violation at %f \n", tDP, $realtime );


        //tRES1/2
        if ( T_CS_N - T_CS_P < tRES1 && T_CS_N > 0 && tRES1_Chk)
            $fwrite (AC_Check_File, "when transit from Deep-Power Mode to Standby Mode, CS# must remain high for at least tRES1 =%f ns, tRES1 timing violation at %f \n", tRES1, $realtime );

    end


    always @ ( posedge HOLD_B_INT ) begin
        T_HOLD_P = $realtime;
        #0;
        //tCHHH
        if ( T_HOLD_P - T_SCLK_P < tCHHH && ~CSb  && T_HOLD_P > 0 )
            $fwrite (AC_Check_File, "minimum HOLD# hold time tCHHH=%f ns, tCHHH timing violation at %f \n", tCHHH, $realtime );
    end

    always @ ( negedge HOLD_B_INT ) begin
        T_HOLD_N = $realtime;
        #0;
        //tCHHL
        if ( T_HOLD_N - T_SCLK_P < tCHHL && ~CSb  && T_HOLD_N > 0 )
            $fwrite (AC_Check_File, "minimum HOLD hold time tCHHL=%f ns, tCHHL timing violation at %f \n", tCHHL, $realtime );
    end

    always @ ( posedge WPb ) begin
        T_WP_P = $realtime;
        #0;  
    end

    always @ ( negedge WPb ) begin
        T_WP_N = $realtime;
        #0;
        //tSHWL
        if ( ((T_WP_N - T_CS_P < tSHWL) || ~CSb) && WP_EN && T_WP_N > 0 )
            $fwrite (AC_Check_File, "minimum WPb hold time tSHWL=%f ns, tSHWL timing violation at %f \n", tSHWL, $realtime );
    end
endmodule



