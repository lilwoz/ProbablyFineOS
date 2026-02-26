# Change: Add OS Foundation — Bootloader, Kernel, Drivers, Project Structure

## Why
ProbablyFineOS is a new bare-metal OS written in FASM targeting x86/x64.
The project needs a modular foundation: bootloader, protected-mode kernel,
video driver, and input drivers so further subsystems can be added incrementally.

## What Changes
- Add two-stage BIOS bootloader (MBR + stage2) in FASM
- Add kernel entry point with GDT, IDT, protected mode setup, and basic VGA console
- Add VGA text-mode driver and VESA linear framebuffer driver
- Add PS/2 keyboard driver with scancode-to-ASCII translation
- Add PS/2 mouse driver with packet decoding
- Add modular directory layout, shared include headers, and Makefile build system
- All code dual-target: x86 (32-bit protected mode) primary; x64 long-mode stubs prepared

## Impact
- Affected specs: bootloader, kernel-core, video-driver, keyboard-driver, mouse-driver, project-structure
- Affected code: entire repository (greenfield — no existing code)
- Breaking changes: none (new project)
