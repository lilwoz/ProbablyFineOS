# =============================================================
# ProbablyFineOS — Build System
#
# Requirements:
#   fasm   >= 1.73  (https://flatassembler.net)
#   qemu-system-i386 or qemu-system-x86_64
#   dd, coreutils
#
# Usage:
#   make          build disk image  (build/os.img)
#   make run      boot in QEMU
#   make debug    boot in QEMU + GDB stub on :1234 (paused)
#   make clean    remove build artefacts
#   make info     print image layout
#
# Architecture:
#   make ARCH=32  (default) — 32-bit protected mode kernel
#   make ARCH=64            — long-mode kernel (scaffold)
#
# VESA graphics mode:
#   make VESA=1   — request 800x600x32bpp via BIOS before PM switch
# =============================================================

ARCH    ?= 32
VESA    ?= 0

FASM    := fasm
QEMU    := qemu-system-i386
BUILD   := build

# FASM preprocessor definitions
FASM_DEFS := -d ARCH=$(ARCH) -d VESA_ENABLE=$(VESA)

# Output files
IMG     := $(BUILD)/os.img
STAGE1  := $(BUILD)/stage1.bin
STAGE2  := $(BUILD)/stage2.bin
KERNEL  := $(BUILD)/kernel.bin

# Disk geometry (1.44 MB floppy, 512-byte sectors)
IMG_SECTORS := 2880

# Sector positions (LBA)
STAGE2_LBA  := 1
KERNEL_LBA  := 17

.PHONY: all clean run debug info

# --------------------------------------------------------------
all: $(IMG)

$(BUILD):
	mkdir -p $(BUILD)

# ---- Stage 1 (MBR) -------------------------------------------
$(STAGE1): boot/stage1.asm include/constants.inc | $(BUILD)
	$(FASM) $(FASM_DEFS) $< $@
	@SIZE=$$(wc -c < $@); \
	 if [ $$SIZE -ne 512 ]; then \
	   echo "ERROR: stage1.bin must be exactly 512 bytes (got $$SIZE)"; \
	   exit 1; \
	 fi
	@echo "  [OK] stage1.bin  (512 bytes, MBR)"

# ---- Stage 2 -------------------------------------------------
$(STAGE2): boot/stage2.asm include/constants.inc | $(BUILD)
	$(FASM) $(FASM_DEFS) $< $@
	@echo "  [OK] stage2.bin  ($$(wc -c < $@) bytes, max $$(( ($(KERNEL_LBA) - $(STAGE2_LBA)) * 512 )) bytes)"

# ---- Kernel --------------------------------------------------
$(KERNEL): kernel/kernel.asm \
           kernel/gdt.asm kernel/idt.asm kernel/pic.asm kernel/shell.asm \
           drivers/video/vga.asm drivers/video/vesa.asm drivers/video/font.inc \
           drivers/input/keyboard.asm drivers/input/mouse.asm \
           include/constants.inc include/macros.inc include/structs.inc | $(BUILD)
	$(FASM) $(FASM_DEFS) $< $@
	@echo "  [OK] kernel.bin  ($$(wc -c < $@) bytes)"

# ---- Disk image ----------------------------------------------
$(IMG): $(STAGE1) $(STAGE2) $(KERNEL) | $(BUILD)
	# Create blank floppy image
	dd if=/dev/zero of=$@ bs=512 count=$(IMG_SECTORS) 2>/dev/null
	# Write each binary at its LBA position
	dd if=$(STAGE1) of=$@ bs=512 seek=0           conv=notrunc 2>/dev/null
	dd if=$(STAGE2) of=$@ bs=512 seek=$(STAGE2_LBA) conv=notrunc 2>/dev/null
	dd if=$(KERNEL) of=$@ bs=512 seek=$(KERNEL_LBA) conv=notrunc 2>/dev/null
	@echo "  [OK] os.img      ($(IMG_SECTORS) sectors = $$(( $(IMG_SECTORS) / 2 )) KB)"

# --------------------------------------------------------------
run: $(IMG)
	$(QEMU) \
	  -drive format=raw,file=$(IMG),if=floppy \
	  -m 64M \
	  -vga std \
	  -name "ProbablyFineOS"

# Debug: QEMU paused, GDB listening on localhost:1234
debug: $(IMG)
	@echo "Launching QEMU (paused). Connect GDB with:"
	@echo "  gdb -ex 'target remote localhost:1234' -ex 'set arch i386'"
	$(QEMU) \
	  -drive format=raw,file=$(IMG),if=floppy \
	  -m 64M \
	  -vga std \
	  -name "ProbablyFineOS (debug)" \
	  -s -S

# Print disk image layout
info: $(IMG)
	@echo "Disk image layout: $(IMG)"
	@echo "  LBA 0        : Stage 1 (MBR, 512 bytes)"
	@echo "  LBA 1-16     : Stage 2 (max 8 KB)"
	@echo "  LBA 17+      : Kernel  (max 32 KB)"
	@echo "Binary sizes:"
	@echo "  stage1.bin   : $$(wc -c < $(STAGE1)) bytes"
	@echo "  stage2.bin   : $$(wc -c < $(STAGE2)) bytes"
	@echo "  kernel.bin   : $$(wc -c < $(KERNEL)) bytes"

clean:
	rm -rf $(BUILD)
	@echo "  [CLEAN] build/ removed"
