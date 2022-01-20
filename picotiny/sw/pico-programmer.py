# coding: utf-8

# compile and linking
# to be optimized
# $ riscv32-unknown-elf-gcc -march=RV32IMC -Wl,-Bstatic,-T,sections.lds,--strip-debug -ffreestanding -nostdlib -o firmware.elf start.s isp_flasher.s firmware.c
# 
# $ riscv32-unknown-elf-objcopy.exe -O verilog firmware.elf firmware.out     

import serial, sys
import time

if len(sys.argv) != 3 or '-h' in sys.argv:
    print("Usage: python pico-programmer.py <firmware.out file path> <serial port>")
    sys.exit()
    

def isp_exec_esec(addr):
    # ISP Flasher ESEC (Erase Sector)
    # Host:  0x30        addr2-0
    # Reply:       0x31           [erase] 0x32 
    
    saddr = bytes([(addr // 65535) & 0xFF, (addr // 256) & 0xF0, 0x00])

    ser.write(bytes([0x30]))
    
    resp = bytes([0x00])
    wcou = 0
    while resp[0] != 0x31:
        resp = ser.read()
        wcou = wcou + 1
        if len(resp) == 0:
            resp = bytes([0x00])
            if wcou > 10:
                wcou = 0
                ser.write(bytes([0x30]))
        elif resp[0] == 0x31:
            pass
            # print("Erase processing")
            
    ser.write(saddr)

    resp = bytes([0x00])
    while resp[0] != 0x32:
        resp = ser.read()
        if len(resp) == 0:
            resp = bytes([0x00])
        elif resp[0] == 0x32:
            pass
            # print("Erase finished")

def isp_exec_wbuf(data):
    # ISP Flasher WBUF (Write Pagebuf)
    # Host:  0x10        len dat0-datn
    # Reply:       0x11                chk 
    wrbyte = bytes([len(data) - 1] + data)
    chksum = sum(data) & 0xFF
    
    ser.write(bytes([0x10]))

    resp = bytes([0x00])
    while resp[0] != 0x11:
        resp = ser.read()
        if len(resp) == 0:
            resp = bytes([0x00])
        elif resp[0] == 0x11:
            pass
            # print("  Write processing")
            
    ser.write(wrbyte)
    
    resp = bytes([0x00])
    while resp[0] != chksum:
        resp = ser.read()
        if len(resp) == 0:
            resp = bytes([0x00])
        elif resp[0] == chksum:
            return True
            # print("  Chksum get")
        else:
            print("  Bad chksum", resp[0])
            return False

def isp_exec_wpag(addr):
    # ISP Flasher WPAG (Write Page)
    # page length saved from last WBUF
    # Host:  0x40        addr2-0
    # Reply:       0x41           [program] 0x42
    pgbuf = bytes([(addr // 65535) & 0xFF, (addr // 256) & 0xFF, addr & 0xFF])

    ser.write(bytes([0x40]))

    resp = bytes([0x00])
    while resp[0] != 0x41:
        resp = ser.read()
        if len(resp) == 0:
            resp = bytes([0x00])
        elif resp[0] == 0x41:
            pass
            # print("  Programming processing")
                
    ser.write(pgbuf)

    resp = bytes([0x00])
    while resp[0] != 0x42:
        resp = ser.read()
        if len(resp) == 0:
            resp = bytes([0x00])
        elif resp[0] == 0x42:
            pass
            #print("  Programming finished")

def isp_exec_rst():
    # ISP Flasher RST
    # Host:  0xF0       
    # Reply:       0xF1 
    ser.write(bytes([0xF0]))
    ser.read()

# read file

filepath = sys.argv[1]
file = open(filepath, 'r', buffering=8192)

lprog = []
plinecount = 0

lbegin = False
for line in file:
    # skipping ram space
    if lbegin:
        lprog.append(line)
        plinecount += 1
    if line.startswith('@00000000'):
        lbegin = True
        lprog.append(line)

file.close()


nproglen = 16 * (plinecount-1) + len(lprog[plinecount-1].split(' ')) - 1

print("Read program with", nproglen, "bytes")

prog = [0] * nproglen
wp = 0
flash_base = 0x00000000

for i, lstr in enumerate(lprog):
    if lstr.startswith('@'):
        wp = int(lstr[1:], 16) - flash_base
    for j, bprog in enumerate(lstr.split(' ')[0:-1]):
        prog[wp] = int(bprog, 16)
        wp += 1


# open serial and check status
ser = serial.Serial(sys.argv[2], 115200, timeout=0.01)

print("  - Waiting for reset -", flush=True)
print('    ', end='', flush=True)

for i in range(100):
    ser.reset_input_buffer()
    ser.write(bytes([0x55, 0x55]))
    ser.flush()
    res = ser.read()
    
    time.sleep(0.1)

    if i % 10 == 0:
        print('.', end='', flush=True)
    
    if len(res) > 0 and res[0] == 0x56:
        break

print("")

if len(res) == 0 or res[0] != 0x56:
    print("Picorv32-isp not detected or not in isp mode")
    print("Check serial port or check reset button")
    ser.close()
    sys.exit()

# begin programming

sectind = 0
pageind = 0
wrtbyte = 0
rembyte = len(prog)
curraddr = 0
pagestep = 256

sectreq = ((rembyte - 1) // 4096) + 1
pagereq = ((rembyte - 1) // pagestep) + 1

print("Total sectors", sectreq, flush=True)
print("Total pages", pagereq, flush=True)

wbufFailed = False
wbufRetryLimit = 3


for i in range(sectreq):
    
    print(f"Flashing {i+1} / {sectreq}", flush=True)
    
    # Erase the sector to be programmed
    # print("Erasing sector", i, "at 0x{:06x}".format(curraddr & 0xFFF000))
    
    isp_exec_esec(curraddr)
    
    for j in range( min(16, pagereq - i*16) ):
        wlen = min(pagestep, rembyte - curraddr)
        wrdat = prog[curraddr:curraddr+wlen]
        
        # Send data to page buffer
        # print(f" Writing from 0x{curraddr:06X} to 0x{curraddr+wlen-1:06X}")

        wbufRetryCnt = 0
        while True:
            if isp_exec_wbuf(wrdat):
                break
            else:
                wbufRetryCnt += 1
                if wbufRetryCnt > wbufRetryLimit:
                    wbufFailed = True
                    break
        if wbufFailed:
            break
        
        # Write from page buffer to flash
        # print(f" Programming {j+i*16} at 0x{curraddr:06X}")
        isp_exec_wpag(curraddr)
        
        curraddr += pagestep
    
    if wbufFailed:
        print("  Too many retires on sending data to page buffer")        
        break

# reset system
if wbufFailed:
    print("Flashing failed")
else:
    isp_exec_rst()

    print("")
    print("Flashing completed")

ser.close()