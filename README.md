# SimpleOS

A minimal graphical operating system written in x86 assembly (FASM) that boots from a USB drive.

## Features

- **Graphical Desktop**: VGA mode 13h (320x200, 256 colors)
- **Decorative Wallpaper**: Blue gradient with diamond pattern and circle decorations
- **Mouse Support**: Clickable icons and windows with custom cursor
- **Keyboard Support**: Type in the text editor
- **Taskbar**: Start button and clock display
- **Window Manager**: Draggable windows with close buttons
- **Text Editor**: Create and edit text files
- **File Manager**: View saved files
- **RAM-based File System**: Store up to 16 files

## Requirements

- **FASM** (Flat Assembler): [https://flatassembler.net/](https://flatassembler.net/)
- **QEMU** (for testing): [https://www.qemu.org/](https://www.qemu.org/)

### Installing FASM

```bash
# Ubuntu/Debian
sudo apt install fasm

# Arch Linux
sudo pacman -S fasm

# Fedora
sudo dnf install fasm
```

## Building

### Using the build script:
```bash
chmod +x build.sh
./build.sh
```

### Using make:
```bash
make
```

## Running

### Test with QEMU (recommended):
```bash
qemu-system-i386 -drive format=raw,file=simpleos.img -m 16
```

Or simply:
```bash
make run
```

### Boot from USB drive:

**Warning**: This will overwrite data on the USB drive!

1. Insert USB drive
2. Find the device name: `lsblk`
3. Write the image:
```bash
sudo dd if=simpleos.img of=/dev/sdX bs=512 conv=notrunc
sync
```
Replace `/dev/sdX` with your actual USB device (e.g., `/dev/sdb`)

4. Restart computer and boot from USB

## Usage

### Desktop
- **Click on "Editor" icon**: Opens the text editor
- **Click on "Files" icon**: Opens the file manager
- **Start button**: Decorative (not functional in this version)

### Text Editor
- **Type**: Enter text characters
- **Enter**: New line
- **Backspace**: Delete character
- **Save button**: Save current text to first file slot
- **Clear button**: Clear all text
- **X button**: Close window

### File Manager
- **Click on a file**: Load it into the text editor
- **X button**: Close window

## Technical Details

### Memory Map
```
0x0000 - 0x7BFF : Free / Stack
0x7C00 - 0x7DFF : Bootloader (512 bytes)
0x1000 - 0x8FFF : Kernel (~30KB)
0xA0000        : VGA Video Memory
```

### File System Structure
- 16 file slots maximum
- Each file: 12-byte filename + 2-byte size + 512-byte content
- Files persist only while OS is running (RAM-based)

### VGA Mode 13h
- Resolution: 320x200 pixels
- Colors: 256 (8-bit palette)
- Linear framebuffer at 0xA0000

## File Structure

```
os/
├── boot.asm      # Bootloader (512 bytes, loads kernel)
├── kernel.asm    # Main OS kernel
├── build.sh      # Build script
├── Makefile      # Alternative build system
└── README.md     # This file
```

## Customization

### Change wallpaper pattern
Edit the `draw_wallpaper` function in `kernel.asm` to create your own pattern.

### Change colors
Modify the color constants at the top of `kernel.asm`:
```asm
COLOR_DESKTOP       equ 1       ; Blue
COLOR_TASKBAR       equ 7       ; Gray
```

### Add more icons
Add new icon drawing routines and update `draw_icons` function.

## Limitations

- No persistence (files lost on reboot)
- No real file system on disk
- Single-tasking only
- Fixed screen resolution
- No networking
- No sound

## License

Public domain - feel free to use and modify!
