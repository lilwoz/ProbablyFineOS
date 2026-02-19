# Project Context

## Purpose
SimpleOS is a minimal graphical operating system written entirely in x86 assembly (FASM) that boots directly from a USB drive or disk image. It demonstrates low-level bare-metal programming: graphics rendering, mouse/keyboard handling, window management, and a basic file system — all in 16-bit real mode without any OS dependencies.

## Tech Stack
- **Language**: x86 16-bit real mode assembly (FASM syntax)
- **Assembler**: FASM (Flat Assembler)
- **Graphics**: VESA VBE mode 0x101 (640x480, 256 colors, bank-switched)
- **Testing**: QEMU (qemu-system-i386) for emulation, manual interactive testing
- **Build**: GNU Make + Bash (`build.sh`), producing a raw disk image
- **No runtime dependencies** — bare-metal, no libraries or frameworks

## Project Conventions

### Code Style
- **Labels**: `snake_case` (e.g., `draw_desktop`, `mouse_init`)
- **Constants**: `SCREAMING_SNAKE_CASE` (e.g., `SCREEN_WIDTH`, `MAX_FILES`)
- **Local labels**: dot-prefixed (e.g., `.loop`, `.done`)
- **Data variables**: `snake_case` (e.g., `mouse_x`, `editor_state`)
- **String literals**: prefixed with `str_` (e.g., `str_editor_title`)
- **Indentation**: 4 spaces for instructions
- **Comments**: section dividers with `; ====...`, inline comments aligned, function headers document inputs/outputs/clobbered registers
- **Register preservation**: `pusha`/`popa` frame around functions

### Architecture Patterns
- **Two-stage boot**: bootloader (`boot.asm`, 512 bytes at 0x7C00) loads kernel (`kernel.asm` at 0x1000)
- **Monolithic kernel**: single `kernel.asm` file containing all subsystems
- **Poll-based event loop**: mouse via IRQ 12, keyboard via INT 16h
- **Direct hardware I/O**: BIOS interrupts (INT 0x10, 0x13, 0x16) and port I/O (VGA, PS/2, PIC)
- **Bank-switched framebuffer**: VESA VBE for >64KB video memory access

### Testing Strategy
- No formal test framework (bare-metal environment)
- Primary testing via QEMU emulation (`make run`)
- Debug mode available (`make debug` — QEMU with monitor)
- Hardware testing by writing image to USB with `dd`
- Build script includes assembly error checking

### Git Workflow
- No formal branching strategy established yet
- Build artifacts (`*.bin`, `*.img`) should not be committed in general

## Domain Context
This is an **OS development** project operating in x86 real mode. Key domain concepts:
- **BIOS interrupts**: legacy INT-based I/O for video, disk, keyboard
- **VESA VBE**: bank switching required because framebuffer exceeds 64KB segment limit
- **PS/2 protocol**: 3-byte mouse packets, IRQ 12, 8042 controller
- **PIC (8259A)**: programmable interrupt controller for IRQ management
- **MBR boot**: bootloader must be exactly 512 bytes with 0xAA55 signature
- **RAM-based file system**: custom format, 16 files max, 512-byte content per file, non-persistent

## Important Constraints
- **16-bit real mode**: limited to 1MB addressable memory, no protected mode
- **Bootloader**: must be exactly 512 bytes
- **Single-tasking**: no multitasking or process isolation
- **No persistence**: all file system data lost on reboot
- **Fixed resolution**: 640x480x256 hardcoded
- **Integer-only**: no FPU usage
- **PS/2 only**: no USB input device support
- **Hardware requirements**: VESA VBE support (mode 0x101), PS/2 mouse/keyboard, x86 CPU (i386+)

## External Dependencies
- **FASM** — assembler (required for build)
- **QEMU** — emulator (required for testing)
- **GNU Make / Bash** — build tooling
- **dd** — for writing to USB (optional, deployment only)
