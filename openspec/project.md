# Project Context

## Purpose
ProbablyFineOS is a bare-metal operating system written entirely in FASM
(Flat Assembler), targeting IBM-PC compatible hardware (x86 32-bit protected
mode primary; x64 long-mode path scaffolded via compile-time flag).
Goal: understand OS internals from first principles — no C runtime, no libc,
no external linker.

## Tech Stack
- **Language**: FASM (Flat Assembler) ≥ 1.73 — all source, all platforms
- **Primary target**: x86 32-bit protected mode (ARCH=32)
- **Secondary target**: x64 long mode (ARCH=64, stub / scaffold)
- **Boot**: BIOS (MBR two-stage), UEFI deferred
- **Emulator**: QEMU (`qemu-system-i386`) for development
- **Build**: GNU Make + `dd` (no cross-compiler needed)

## Project Conventions

### Code Style
- Every file starts with a block comment naming the file, its role, and its
  public API (symbols other modules may call).
- Included files (`.asm`, `.inc`) MUST NOT contain `format` or `org` directives;
  those belong only in the top-level assembled file (`kernel/kernel.asm`,
  `boot/stage1.asm`, `boot/stage2.asm`).
- Constants: `UPPER_SNAKE_CASE` with `equ` (not `=`, except in `if` guards).
- Labels: `snake_case` for public symbols; `.local_label` for file-private labels.
- Comment style: `;` for inline, `;  ----` for section separators.

### Architecture Patterns
- **Flat binary kernel**: org 0x10000, no ELF, no linker; Stage 2 loads raw blob.
- **Single-file assembly**: `kernel/kernel.asm` is the FASM entry point; it
  `include`s all subsystems sequentially. There is no separate link step.
- **Include path discipline**: each file uses paths relative to its own location.
  - `kernel/kernel.asm` includes `'gdt.asm'`, `'../drivers/video/vga.asm'`, etc.
- **Calling convention** (internal kernel):
  - Arguments: push on stack (cdecl-like); `vga_puts` expects `push ptr / call / add esp, 4`.
  - Callee-saves: `ebx, esi, edi, ebp`.
  - Return value: `eax`.
  - ISR prologue/epilogue: `pushad / push_segs / set_kernel_segs` → … → `pop_segs / popad / iret`.
- **IRQ installation**: drivers call `idt_set_gate(al=vector, eax=handler)` then
  `pic_unmask_irq(al=irq_num)` in their `*_init` function.
- **No global state leakage**: each driver owns its state as `db`/`dw`/`dd`/`rb`
  definitions inside its own `.asm` file.

### Modular Structure
```
ProbablyFineOS/
├── boot/               Stage 1 (MBR) + Stage 2 (PM switch)
├── kernel/             Entry point, GDT, IDT, PIC, shell
├── drivers/
│   ├── video/          VGA text mode, VESA framebuffer, 8×16 font
│   └── input/          PS/2 keyboard, PS/2 mouse
├── include/            Shared constants, macros, struct helpers
├── build/              Generated artefacts (gitignored)
└── tools/              Helper scripts (future)
```

Adding a new driver:
1. Create `drivers/<category>/<name>.asm` with `<name>_init` and public symbols.
2. Add `include '../drivers/<category>/<name>.asm'` to `kernel/kernel.asm`.
3. Call `<name>_init` in `kernel_entry` after PIC init.
4. Add to `kernel` target dependencies in `Makefile`.

### Memory Map
| Address             | Contents                         |
|---------------------|----------------------------------|
| `0x0000 – 0x04FF`   | IVT + BIOS data (real mode)      |
| `0x0500 – 0x7BFF`   | Stage 2 loader                   |
| `0x7C00 – 0x7DFF`   | MBR (Stage 1)                    |
| `0x7E00 – 0x7FFF`   | Free                             |
| `0x8000 – 0x9FFF`   | VESA VBE Mode Info Block buffer  |
| `0x10000 – 0x1FFFF` | Kernel binary                    |
| `0x80000 – 0x8FFFF` | Kernel stack (grows down)        |
| `0xA0000 – 0xAFFFF` | VGA graphics framebuffer         |
| `0xB8000 – 0xB8F9F` | VGA text framebuffer (80×25)     |

### Testing Strategy
- Primary: boot in QEMU (`make run`), observe VGA output.
- Debug: `make debug` launches QEMU + GDB stub on port 1234.
- Regression: manual smoke test — OS banner visible, keyboard echo works,
  `mouse` command shows non-zero coordinates after moving mouse in QEMU.
- Future: unit-test individual routines via a user-mode FASM harness.

### Git Workflow
- Branch: `main` = stable; `dev` = active development.
- Commit convention: `<type>(<scope>): <summary>` — e.g. `feat(vga): add hex dump helper`.
- Each spec change goes through OpenSpec proposal → implement → archive cycle.

## Important Constraints
- No C, no external assembler macros (NASM-only macros), no linker scripts.
- Kernel must stay < 32 KB until a proper disk loader is written (LBA 17-80).
- All I/O port access uses `in`/`out` instructions — no MMIO abstraction yet.
- VESA mode must be set in real mode (Stage 2) before entering protected mode.
- PS/2 mouse may be absent; `mouse_init` must silently handle missing device.
