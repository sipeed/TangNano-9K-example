import sys

if len(sys.argv) < 4 or '-h' in sys.argv:
    print("Usage: python vdump8to32.py <input 8b verilog hex path> <output path> <v32|vx4|mif|mi|mix4>")
    sys.exit()
    
# read file

fin = open(sys.argv[1], 'r', buffering=8192)
foutfmt = sys.argv[3]

if len(sys.argv) > 4:
    memaddrbase = int(sys.argv[4], 16)
else:
    memaddrbase = 0

memsize = 8*1024
memwidth = 32 # Fixed size

memaddrlen = (memsize * 8) // memwidth

membuf = [0] * memaddrlen
waddr = 0

for line in fin:
    if line.startswith('@'):
        # Address set
        waddr = int(line[1:], 16) - memaddrbase
    else:
        # Data bytes
        for b in line.split():
            membuf[waddr >> 2] |= int(b, 16) << (8*(waddr&0x03))
            waddr += 1

fin.close()

if foutfmt == "v32":
    # readmemh file
    fout = open(sys.argv[2], 'w+', buffering=8192)
    print("@00000000", file=fout)
    for u in membuf:
        print("{:08X}".format(u), file=fout)
    print("", file=fout)
    fout.close()
elif foutfmt == "vx4":
    # 4 Separated Gowin SPRAM files for devices not supporting byte-enable
    fout = [ open(sys.argv[2][0:sys.argv[2].rfind('.')] + ".vx{}".format(i), 'w+', buffering=8192) for i in range(4) ]
    for fo in fout:
        print("@00000000", file=fo)
    for u in membuf:
        print("{:02X}".format( (u >>  0) & 0xFF ), file=fout[0])
        print("{:02X}".format( (u >>  8) & 0xFF ), file=fout[1])
        print("{:02X}".format( (u >> 16) & 0xFF ), file=fout[2])
        print("{:02X}".format( (u >> 24) & 0xFF ), file=fout[3])
    for fo in fout:
        fo.close()
elif foutfmt == "mif":
    # Quartus mif file
    fout = open(sys.argv[2], 'w+', buffering=8192)
    print("DEPTH = {};".format(memaddrlen), file=fout)
    print("WIDTH = {};".format(memwidth), file=fout)
    print("ADDRESS_RADIX = HEX;", file=fout)
    print("DATA_RADIX = HEX;", file=fout)
    print("CONTENT", file=fout)
    print("BEGIN", file=fout)
    for i, u in enumerate(membuf):
        print("{:04X}: {:08X};".format(i, u), file=fout)
    print("END;", file=fout)
    fout.close()
elif foutfmt == "mi":
    # Gowin SPRAM file
    fout = open(sys.argv[2], 'w+', buffering=8192)
    print("#File_format=Hex", file=fout)
    print("#Address_depth={}".format(memaddrlen), file=fout)
    print("#Data_width={}".format(memwidth), file=fout)
    for u in membuf:
        print("{:08X}".format(u), file=fout)
    fout.close()
elif foutfmt == "mix4":
    # 4 Separated Gowin SPRAM files for devices not supporting byte-enable
    fout = [ open(sys.argv[2][0:sys.argv[2].rfind('.')] + "_{}.mi".format(i), 'w+', buffering=8192) for i in range(4) ]
    for fo in fout:
        print("#File_format=Hex", file=fo)
        print("#Address_depth={}".format(memaddrlen), file=fo)
        print("#Data_width={}".format(memwidth//4), file=fo)
    for u in membuf:
        print("{:02X}".format( (u >>  0) & 0xFF ), file=fout[0])
        print("{:02X}".format( (u >>  8) & 0xFF ), file=fout[1])
        print("{:02X}".format( (u >> 16) & 0xFF ), file=fout[2])
        print("{:02X}".format( (u >> 24) & 0xFF ), file=fout[3])
    for fo in fout:
        fo.close()
else:
    print("Format {} error".format(foutfmt))


