#!/bin/bash

# SimpleOS Build Script
# Requirements: fasm (flat assembler)

set -e

echo "=== SimpleOS Build Script ==="
echo ""

# Check for FASM
if ! command -v fasm &> /dev/null; then
    echo "Error: FASM (Flat Assembler) is not installed."
    echo "Install it with:"
    echo "  Ubuntu/Debian: sudo apt install fasm"
    echo "  Arch Linux:    sudo pacman -S fasm"
    echo "  Or download from: https://flatassembler.net/"
    exit 1
fi

# Clean previous build
echo "[1/4] Cleaning previous build..."
rm -f boot.bin kernel.bin simpleos.img

# Assemble bootloader
echo "[2/4] Assembling bootloader..."
fasm boot.asm boot.bin
if [ $? -ne 0 ]; then
    echo "Error: Failed to assemble bootloader"
    exit 1
fi

# Assemble kernel
echo "[3/4] Assembling kernel..."
fasm kernel.asm kernel.bin
if [ $? -ne 0 ]; then
    echo "Error: Failed to assemble kernel"
    exit 1
fi

# Create disk image
echo "[4/4] Creating disk image..."
cat boot.bin kernel.bin > simpleos.img

# Pad to 1.44MB floppy size (optional, for compatibility)
# truncate -s 1474560 simpleos.img

echo ""
echo "=== Build Complete ==="
echo "Output: simpleos.img"
echo ""
echo "To test with QEMU:"
echo "  qemu-system-i386 -drive format=raw,file=simpleos.img -m 16"
echo ""
echo "To write to USB drive (CAREFUL - replace /dev/sdX with your USB):"
echo "  sudo dd if=simpleos.img of=/dev/sdX bs=512 conv=notrunc"
echo "  sync"
