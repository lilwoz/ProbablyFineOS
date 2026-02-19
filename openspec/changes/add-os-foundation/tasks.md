## 1. Project Structure & Build System
- [x] 1.1 Create directory layout: `boot/`, `kernel/`, `drivers/video/`, `drivers/input/`, `include/`, `build/`, `tools/`
- [x] 1.2 Create `include/constants.inc` — port addresses, memory map constants, color attributes
- [x] 1.3 Create `include/macros.inc` — utility macros (outb, inb, io_delay, eoi, freeze, etc.)
- [x] 1.4 Create `include/structs.inc` — IDT descriptor, GDT descriptor, VESA offsets
- [x] 1.5 Create `Makefile` with targets: `all`, `clean`, `run` (QEMU), `debug` (QEMU + GDB), `info`

## 2. Bootloader — Stage 1 (MBR)
- [x] 2.1 Create `boot/stage1.asm` — 512-byte MBR, BIOS INT 13h disk read, jump to stage2 at `0x0500`
- [x] 2.2 Verify MBR signature `0xAA55` at byte 510

## 3. Bootloader — Stage 2
- [x] 3.1 Create `boot/stage2.asm` — A20 line enable, load kernel from disk to `0x10000`
- [x] 3.2 Set up temporary GDT for real→protected mode transition
- [x] 3.3 Switch to 32-bit protected mode, far-jump to kernel entry

## 4. Kernel Core
- [x] 4.1 Create `kernel/kernel.asm` — entry point at `0x10000`, call subsystem init functions
- [x] 4.2 Create `kernel/gdt.asm` — GDT with null, code, data, user-code, user-data descriptors; `gdt_init`
- [x] 4.3 Create `kernel/idt.asm` — IDT with 256 entries, `idt_init`, default exception handlers (0–7)
- [x] 4.4 Create `kernel/pic.asm` — 8259A remap IRQ0–7 → 0x20, IRQ8–15 → 0x28; `pic_init`

## 5. Video Driver
- [x] 5.1 Create `drivers/video/vga.asm` — VGA text mode 80×25; `vga_clear`, `vga_putc`, `vga_puts`, `vga_set_color`, `vga_scroll`, cursor management
- [x] 5.2 Create `drivers/video/vesa.asm` — VESA BIOS Extensions mode set (800×600×32); linear framebuffer `vesa_put_pixel`, `vesa_fill_rect`, `vesa_clear`, `vesa_puts`
- [x] 5.3 Create `drivers/video/font.inc` — 8×16 bitmap font for VESA text rendering (ASCII 0x20–0x7E)

## 6. Keyboard Driver
- [x] 6.1 Create `drivers/input/keyboard.asm` — `keyboard_init`, IRQ1 handler, scancode set 1 → ASCII table, `keyboard_getc`, circular 256-byte ring buffer
- [x] 6.2 Handle modifier keys: Shift, Ctrl, Alt, CapsLock
- [x] 6.3 Install keyboard IRQ via IDT entry 0x21

## 7. Mouse Driver
- [x] 7.1 Create `drivers/input/mouse.asm` — `mouse_init`, enable PS/2 mouse via port 0x64, IRQ12 handler
- [x] 7.2 Decode 3-byte PS/2 packets: buttons, X delta, Y delta
- [x] 7.3 Maintain global `mouse_x`, `mouse_y`, `mouse_buttons`; clamp to screen bounds
- [x] 7.4 Install mouse IRQ via IDT entry 0x2C

## 8. Kernel Demo Shell
- [x] 8.1 Create `kernel/shell.asm` — minimal echo shell: read keyboard, display on VGA, show mouse coords
- [x] 8.2 Display OS banner on boot (multi-line, coloured ASCII art)

## 9. Update Project Metadata
- [x] 9.1 Update `openspec/project.md` with tech stack and conventions
- [x] 9.2 Update `README.md` with build instructions and architecture overview
