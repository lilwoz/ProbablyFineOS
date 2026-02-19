# ProbablyFineOS

A bare-metal operating system written entirely in [FASM](https://flatassembler.net) (Flat Assembler), targeting x86 protected mode. No C, no external runtime — assembly all the way down.

## Features

- Two-stage BIOS bootloader (MBR → protected mode)
- 32-bit protected-mode kernel with flat GDT
- IDT with CPU exception handlers and IRQ dispatch
- 8259A PIC remapping (IRQ0-7 → 0x20, IRQ8-15 → 0x28)
- VGA text mode driver (80×25, colour, hardware cursor, scroll)
- VESA linear framebuffer driver (800×600×32bpp, optional)
- 8×16 bitmap font for VESA text rendering
- PS/2 keyboard driver — scancode-set-1, Shift/Ctrl/Alt/CapsLock
- PS/2 mouse driver — 3-byte packets, coordinate clamping
- Minimal interactive shell with `help`, `clear`, `mouse` commands

## Requirements

| Tool | Version | Purpose |
|------|---------|---------|
| `fasm` | ≥ 1.73 | Assembler |
| `qemu-system-i386` | any | Emulator |
| `make`, `dd` | GNU coreutils | Build system |

Install on Debian/Ubuntu:
```bash
sudo apt install fasm qemu-system-x86 make
```

## Build & Run

```bash
# Build disk image (32-bit protected mode)
make

# Boot in QEMU
make run

# Boot with 800x600 VESA graphics
make VESA=1 run

# GDB debug session (QEMU paused, GDB stub on :1234)
make debug
# In another terminal:
gdb -ex 'target remote localhost:1234' -ex 'set arch i386'

# Remove build artefacts
make clean

# Show disk layout and binary sizes
make info
```

## Project Structure

```
ProbablyFineOS/
├── boot/
│   ├── stage1.asm          MBR (512 bytes) — loads stage2
│   └── stage2.asm          Stage 2 — A20, PM switch, loads kernel
├── kernel/
│   ├── kernel.asm          Entry point; includes all subsystems
│   ├── gdt.asm             Global Descriptor Table
│   ├── idt.asm             Interrupt Descriptor Table
│   ├── pic.asm             8259A PIC
│   └── shell.asm           Demo interactive shell
├── drivers/
│   ├── video/
│   │   ├── vga.asm         VGA text mode 80×25
│   │   ├── vesa.asm        VESA 800×600×32bpp framebuffer
│   │   └── font.inc        8×16 bitmap font (ASCII 0x20–0x7E)
│   └── input/
│       ├── keyboard.asm    PS/2 keyboard, IRQ1, scancode set 1
│       └── mouse.asm       PS/2 mouse, IRQ12, 3-byte packets
├── include/
│   ├── constants.inc       I/O ports, memory map, VGA colours
│   ├── macros.inc          outb/inb/io_delay/eoi/freeze helpers
│   └── structs.inc         GDT/IDT entry macros, VESA offsets
├── build/                  Generated artefacts (gitignored)
├── openspec/               Spec-driven change management
├── Makefile
└── README.md
```

## Disk Image Layout

| LBA     | Content       | Size    |
|---------|---------------|---------|
| 0       | Stage 1 (MBR) | 512 B   |
| 1–16    | Stage 2       | ≤ 8 KB  |
| 17–80   | Kernel        | ≤ 32 KB |

## Memory Map

| Address      | Use                              |
|--------------|----------------------------------|
| `0x0500`     | Stage 2 entry                    |
| `0x7C00`     | MBR load address                 |
| `0x8000`     | VESA Mode Info Block (stage2)    |
| `0x10000`    | Kernel base address              |
| `0x90000` ↓ | Kernel stack (grows down)        |
| `0xB8000`    | VGA text framebuffer             |

## Adding a New Driver

1. Create `drivers/<category>/<name>.asm` with a `<name>_init` procedure
   and public symbols documented in a header comment.
2. Add `include '../drivers/<category>/<name>.asm'` at the bottom of
   `kernel/kernel.asm`.
3. Call `<name>_init` in `kernel_entry` after `pic_init`.
4. Add the new file to the `$(KERNEL)` dependency list in `Makefile`.
5. Create an OpenSpec proposal (`openspec/changes/add-<name>/`).

## Shell Commands

| Command | Description |
|---------|-------------|
| `help`  | List available commands |
| `clear` | Clear the VGA screen |
| `mouse` | Print current mouse X/Y position and button state |

## Architecture Notes

- **No linker**: FASM assembles the entire kernel as one flat binary
  (`format binary`). All sub-files are `include`-d into `kernel/kernel.asm`.
- **Calling convention**: cdecl-like stack passing for public API
  (`vga_puts`: `push ptr / call / add esp, 4`).
- **IRQ flow**: `pic_init` masks all IRQs → each driver's `*_init` installs
  its IDT gate via `idt_set_gate` then calls `pic_unmask_irq`.
- **x64 stub**: pass `ARCH=64` to assemble with long-mode code paths
  (scaffold; paging and 64-bit entry not yet complete).

## License

MIT — see [LICENSE](LICENSE).
