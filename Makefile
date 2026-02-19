# SimpleOS Makefile

FASM = fasm
QEMU = qemu-system-i386

all: simpleos.img

boot.bin: boot.asm
	$(FASM) boot.asm boot.bin

kernel.bin: kernel.asm
	$(FASM) kernel.asm kernel.bin

simpleos.img: boot.bin kernel.bin
	cat boot.bin kernel.bin > simpleos.img

run: simpleos.img
	$(QEMU) -drive format=raw,file=simpleos.img -m 16

debug: simpleos.img
	$(QEMU) -drive format=raw,file=simpleos.img -m 16 -monitor stdio

clean:
	rm -f boot.bin kernel.bin simpleos.img

.PHONY: all run debug clean
