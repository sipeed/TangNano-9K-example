#include <stdint.h>
#include <stdbool.h>

typedef struct {
    volatile uint32_t DATA;
    volatile uint32_t CLKDIV;
} PICOUART;

typedef struct {
    volatile uint32_t OUT;
    volatile uint32_t IN;
    volatile uint32_t OE;
} PICOGPIO;

typedef struct {
    union {
        volatile uint32_t REG;
        volatile uint16_t IOW;
        struct {
            volatile uint8_t IO;
            volatile uint8_t OE;
            volatile uint8_t CFG;
            volatile uint8_t EN; 
        };
    };
} PICOQSPI;

#define QSPI0 ((PICOQSPI*)0x81000000)
#define GPIO0 ((PICOGPIO*)0x82000000)
#define UART0 ((PICOUART*)0x83000000)

// --------------------------------------------------------

#define QSPI_IO_CSb     0x20
#define QSPI_IO_CLK     0x10
#define QSPI_IO_MOSI    0x01
#define QSPI_IO_MISO    0x02

#define QSPI_OE_MOSI    0x0100

#define QSPI_EN_ENABLE  0x80

#define QSPI_FLASH_RDSR     0x05
#define QSPI_FLASH_WREN     0x06
#define QSPI_FLASH_SE       0x20
#define QSPI_FLASH_PP       0x02
#define QSPI_FLASHSR_WIP    0x01

#define FLASHIO_REQWREN 0x01

inline uint8_t uart_getchar() {
    int rdata;
    do {
        rdata = UART0->DATA;
    } while (rdata < 0);
    return rdata;
}

inline void uart_putchar(uint8_t wdata) {
    UART0->DATA = wdata;
}

inline uint8_t spi_trbyte(uint8_t txdata) {
    uint8_t spi_io;
    for (int i = 0; i < 8; i++) {
        spi_io = (txdata >> 7) & QSPI_IO_MOSI;
        QSPI0->IO = spi_io;
        spi_io |= QSPI_IO_CLK;
        QSPI0->IO = spi_io;
        txdata = (txdata << 1) | ((QSPI0->IO & QSPI_IO_MISO) >> 1);
    }
    return txdata;
}

void spi_flashio(uint8_t *pdata, int length, int wren) {
    // Set CS high, IO0 is output
    QSPI0->IOW = QSPI_OE_MOSI | QSPI_IO_CSb;
    
    // Enable Manual SPI Ctrl
    QSPI0->EN = 0;

    // Send WREN cmd when requested
    if (wren) {
        QSPI0->IO = 0;
        spi_trbyte(QSPI_FLASH_WREN);
        QSPI0->IO = QSPI_IO_CSb;
    }

    // Perform actual data RW
    QSPI0->IO = 0;
    while (length) {
        *pdata = spi_trbyte(*pdata);
        pdata++;
        length--;
    }
    QSPI0->IO = QSPI_IO_CSb;

    // Check WIP/BUSY bit when WREN issued
    if (wren) {
        uint8_t res;
        do {
            QSPI0->IO = 0;
            spi_trbyte(QSPI_FLASH_RDSR);
            res = spi_trbyte(0x00);
            QSPI0->IO = QSPI_IO_CSb;
        } while(res & QSPI_FLASHSR_WIP);
    }

    // Return to XIP mode
    QSPI0->EN = QSPI_EN_ENABLE;
}

typedef struct {
    uint8_t instr;
    // In transmit sequence, addr[0] -> 23:16 / addr[1] -> 15:8 / addr[0] -> 7:0
    uint8_t addr[3]; 
    uint8_t data_buf[256];
} FLASH_BUF;

// 0.8 us per loop in 24MHz
#define FW_WAIT_MAXCNT  ((int)(400000 / 0.8))
#define CLK_FREQ        25175000
#define UART_BAUD       115200

int main()
{
    FLASH_BUF flash_buffer;
    uint8_t instr;
    int buflen;
    int waitcnt;

    UART0->CLKDIV = CLK_FREQ / UART_BAUD - 2;
    
    for (waitcnt = 0; waitcnt < FW_WAIT_MAXCNT; waitcnt++) {
        if (UART0->DATA == 0x55) {
            uart_putchar(0x56);
            break;
        }
    }

    if (waitcnt == FW_WAIT_MAXCNT) {
        void (*flash_vec)(void) = (void (*)(void))(0x00000000);
        flash_vec();
    }

    while (1) {
        instr = uart_getchar();

        switch(instr) {
        case 0x55:
            // ISP Flasher ACK
            uart_putchar(0x56);
            break;

        case 0x10:
            // ISP Flasher WBUF (Write Pagebuf)
            // Host:  0x10        len dat0-datn
            // Reply:       0x11                chk 
            uart_putchar(0x11);
            
            buflen = uart_getchar() + 1;

            uint8_t chksum = 0;
            for (int i = 0; i < buflen; i++) {
                uint8_t rdata = uart_getchar();
                flash_buffer.data_buf[i] = rdata;
                chksum += rdata;
            }
            uart_putchar(chksum);
            break;

        case 0x30:
            // ISP Flasher ESEC (Erase Sector)
            // Host:  0x30        addr2-0
            // Reply:       0x31           [erase] 0x32 
            uart_putchar(0x31);

            flash_buffer.instr = QSPI_FLASH_SE;
            flash_buffer.addr[0] = uart_getchar();
            flash_buffer.addr[1] = uart_getchar();
            flash_buffer.addr[2] = uart_getchar();

            // Send command
            if (buflen) {
                spi_flashio( (void *)&flash_buffer, 4, FLASHIO_REQWREN);
            }
            
            uart_putchar(0x32);
            break;

        case 0x40:
            // ISP Flasher WPAG (Write Page)
            // page length saved from last WBUF
            // Host:  0x40        addr2-0
            // Reply:       0x41           [program] 0x42
            uart_putchar(0x41);

            flash_buffer.instr = QSPI_FLASH_PP;
            flash_buffer.addr[0] = uart_getchar();
            flash_buffer.addr[1] = uart_getchar();
            flash_buffer.addr[2] = uart_getchar();

            if (buflen) {
                spi_flashio( (void *)&flash_buffer, 4+buflen, FLASHIO_REQWREN);
            }

            uart_putchar(0x42);
            break;

        case 0xF0:
            // ISP Flasher RST
            // Host:  0xF0       
            // Reply:       0xF1 
            uart_putchar(0xF1);
            
            // Jump to reset vector
            void (*rst_vec)(void) = (void (*)(void))(0x80000000);
            rst_vec();
            break;
        default:
            break;
        }
    }
}
