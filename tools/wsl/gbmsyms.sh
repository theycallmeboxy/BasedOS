W=$HOME/basedos-work/rootfs/usr/lib
python3 - "$W/libgbm.so.1" "$W/libdrm.so.2" /mnt/c/Users/davea/AppData/Local/Temp/claude/a94d57fe7943bc14/f6560338-698e-402f-90f3-1667c29cc68b/scratchpad/want.txt <<'PY'
import struct,sys
def dynsyms(p):
    b=open(p,'rb').read()
    shoff,=struct.unpack_from('<Q',b,0x28); shentsize,shnum,shstrndx=struct.unpack_from('<HHH',b,0x3A)
    secs=[struct.unpack_from('<IIQQQQIIQQ',b,shoff+i*shentsize) for i in range(shnum)]
    out=set()
    for s in secs:
        if s[1]==11:  # SHT_DYNSYM
            strtab=secs[s[6]]; off,size,ent=s[4],s[5],s[9]
            for o in range(off,off+size,ent):
                name,info,other,shndx=struct.unpack_from('<IBBH',b,o)
                if shndx==0 or name==0: continue
                e=b.index(b'\0',strtab[4]+name); out.add(b[strtab[4]+name:e].decode())
    return out
have=dynsyms(sys.argv[1])|dynsyms(sys.argv[2])|dynsyms(sys.argv[1].replace("libgbm.so.1","libmali.so.1"))
want=open(sys.argv[3]).read().split()
miss=[w for w in want if w not in have]
print('exported by mali libgbm + libdrm:', len(have)); print('missing:', miss)
PY
