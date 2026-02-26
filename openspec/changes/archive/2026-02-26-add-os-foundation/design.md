# Design: OS Foundation

## Context
ProbablyFineOS is written entirely in FASM (flat assembler).
Target: IBM-PC compatible machines with BIOS firmware (x86 32-bit protected mode first;
x64 long-mode path prepared via conditional includes).
No external C runtime or libc — all code is assembly-only.

## Goals / Non-Goals
- **Goals:**
  - Boot from MBR, enter 32-bit protected mode
  - Minimal kernel with interrupt handling and VGA console
  - VGA text mode + VESA mode 2 graphics drivers
  - PS/2 keyboard and mouse drivers
  - Modular, easy-to-extend file layout with reusable include files
  - Single `make` command builds a bootable `.img` image

- **Non-Goals:**
  - USB drivers (future)
  - File system (future)
  - Multitasking / scheduler (future)
  - UEFI boot (future)
  - Networking (future)

## Architecture

```
+---------------------+
|   MBR Bootloader    |  Stage 1 — 512 bytes, loads Stage 2 from disk
+---------------------+
|  Stage 2 Loader     |  Switches to protected mode, loads kernel blob
+---------------------+
|      Kernel         |
|  +--------------+  |
|  |  GDT / IDT   |  |  CPU tables (protected mode)
|  +--------------+  |
|  |  IRQ / PIC   |  |  8259A PIC remapping, IRQ handlers
|  +--------------+  |
|  |  VGA Driver  |  |  Text mode 80×25, VESA framebuffer
|  +--------------+  |
|  | Keyboard Drv |  |  PS/2 port 0x60, scancode set 1 → ASCII
|  +--------------+  |
|  |  Mouse Drv   |  |  PS/2 port 0x60/0x64, 3-byte packets
|  +--------------+  |
+---------------------+
```

## Decisions

### D1 — FASM only, no external assembler
- **Decision:** Use FASM `format binary` throughout; no NASM or LD.
- **Why:** FASM has its own powerful macro system, supports `include`, and
  generates raw binary — ideal for bootloader + kernel blobs without a linker.
- **Alternative:** NASM + LD — more common but adds linker complexity.

### D2 — Flat binary, no ELF for kernel
- **Decision:** Kernel is a raw binary loaded at physical address `0x10000`.
- **Why:** Simplifies bootloader loader logic; ELF parsing in a stage-2 written
  in assembly is fragile. ELF support can be added later in a C stub.
- **Trade-off:** Debugger support is reduced without symbols (DWARF future task).

### D3 — Modular via FASM `include`
- **Decision:** Each subsystem lives in its own `.asm` file; kernel includes them.
- **Why:** FASM preprocessor handles includes at assembly time — zero runtime
  cost, clean separation of concerns.
- **Pattern:** `include/macros.inc` — shared macros; `include/constants.inc` —
  port numbers, memory addresses; `include/structs.inc` — data structures.

### D4 — x86 primary, x64 stubs via conditional assembly
- **Decision:** `ARCH` macro selects 32-bit or 64-bit code paths.
  ```fasm
  ARCH = 32   ; set to 64 for long-mode build
  ```
- **Trade-off:** Long-mode path is scaffolded but not functional until long-mode
  GDT, paging, and a 64-bit entry point are implemented.

### D5 — 8259A PIC (legacy interrupts)
- **Decision:** Use legacy PIC, remap IRQs to 0x20–0x2F.
- **Why:** Simplest hardware interrupt path; APIC can be added later.
- **Alternative:** xAPIC/x2APIC — correct for SMP but complex.

## Memory Map

| Address        | Content                         |
|----------------|---------------------------------|
| `0x0000–0x04FF` | IVT + BIOS data (real mode)    |
| `0x0500–0x7BFF` | Stage 2 loader                 |
| `0x7C00–0x7DFF` | MBR (Stage 1)                  |
| `0x7E00–0x9FFF` | Free (stack during boot)       |
| `0x10000+`      | Kernel binary                  |
| `0xA0000`       | VGA framebuffer                |
| `0xB8000`       | VGA text buffer                |

## Risks / Trade-offs
- **Real hardware quirks** → Test in QEMU first; document known issues.
- **FASM macro complexity** → Keep macros simple; document all in comments.
- **PS/2 mouse absent** → Driver checks device presence; gracefully skips init.

## Open Questions
- Q1: VESA mode — which resolution to default? (Proposed: 800×600 32bpp)
- Q2: Long-mode paging: 4KB or 2MB huge pages for initial identity map?
