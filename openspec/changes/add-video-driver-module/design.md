# Design: Modular Video Driver (add-video-driver-module)

## Context

ProbablyFineOS runs entirely in x86 16-bit real mode. All BIOS services (INT 0x10, VBE) are only reachable in real mode. VESA VBE 2.0 exposes a linear framebuffer at a physical address typically above 0xC0000000 (above the 1 MB real-mode window), so direct `mov [es:di], al` access does not reach it without a segment trick.

**Unreal mode** (also called "big real mode") is the chosen solution:
1. Temporarily enter 32-bit protected mode with a GDT that grants flat 4 GB data segments.
2. Immediately return to real mode — the 32-bit segment base/limit is cached in the segment descriptor cache and survives the mode switch.
3. Use 32-bit `a32` prefix on `mov` instructions to address the full linear framebuffer without switching modes again for every pixel.
4. BIOS calls work normally because CS is still a real-mode segment.

This is proven, widely used in bootloaders (GRUB stage1.5, Syslinux) and is safe on all i386+ CPUs.

## Goals / Non-Goals

- **Goals**
  - Encapsulate all video hardware interaction in `video.asm`
  - Support VESA VBE 2.0 linear framebuffer (preferred) with unreal-mode 32-bit addressing
  - Fall back to VBE 1.x bank-switched mode (current behavior) when VBE 2.0 is unavailable
  - Provide a stable, register-convention-safe primitive API callable from any kernel subsystem
  - Target 800×600×32bpp as the preferred mode; accept 640×480×32bpp or 640×480×8bpp as fallbacks
  - Remain within the 16-bit real-mode execution model; no permanent protected-mode switch

- **Non-Goals**
  - Hardware-accelerated blitting (2D engine registers, BLT engines) — deferred
  - Double buffering / vsync — deferred
  - Multiple simultaneous display outputs
  - USB or DisplayPort enumeration
  - UEFI GOP (Graphics Output Protocol) support

## Decisions

### D1 — Separate FASM include file, not a separate binary

**Decision:** `video.asm` is a FASM `include` file assembled together with `kernel.asm`, not a separately loaded binary segment.

**Rationale:** The OS has no loader capable of linking separate object files. A flat include file is zero-overhead and consistent with the existing single-file pattern; modularisation is logical (source-level) rather than physical (binary-level).

**Alternatives considered:**
- Separate 512-byte segment loaded by bootloader — adds bootloader complexity and addressing overhead; not warranted at this scale.

### D2 — Unreal mode for linear framebuffer access

**Decision:** Use an unreal-mode trampoline (`video_enter_unreal`) called once during init. Subsequent pixel writes use the `a32` address-size override prefix with `es` pre-loaded to the flat segment (base 0, limit 4 GB).

**Rationale:** Only a temporary GDT and two mode switches (real→PE→real) are needed, both performed once at init. All drawing routines can then use `mov dword [a32 es:eax], ecx` without any further mode switches, keeping pixel throughput high.

**Alternatives considered:**
- BIOS INT 0x10/AX=0x4F05 bank switching for every cross-boundary access — keeps code simpler but requires a call per 64 KB bank boundary crossing, causing significant overhead at 800×600.
- Full protected-mode kernel — out of scope; requires rewriting all BIOS-dependent subsystems.

### D3 — Mode selection order

**Preferred → Fallback chain:**
1. 1024×768×32bpp linear (VBE 2.0)
2. 800×600×32bpp linear (VBE 2.0)
3. 800×600×16bpp linear (VBE 2.0)
4. 640×480×32bpp linear (VBE 2.0)
5. 640×480×8bpp bank-switched (VBE 1.x / legacy — current behavior)

The driver tries each in order using INT 0x10/AX=0x4F02 mode set; first success wins.

### D4 — Calling convention

All `video_*` routines follow the existing kernel convention:
- `pusha` / `popa` frame (all general-purpose registers preserved for caller)
- Parameters passed in registers (documented per routine)
- No stack arguments
- CF set on error (mirrors BIOS convention)

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| Some BIOSes reset flat segment limits on INT call | Test in QEMU; `video_enter_unreal` re-runs before any drawing sequence that precedes a BIOS call |
| VBE mode list may not include preferred modes on real hardware | Fallback chain covers down to the legacy 640×480×8bpp mode already working |
| Unreal mode trampoline requires a temporary GDT (16 bytes static data) | GDT stored in `video.asm` data section; no dynamic allocation needed |
| 16-bit segment registers limit single-call span to 64 KB when a32 is not used | All routines that write more than one pixel use `eax`-indexed `a32 mov`; no 64 KB wrap-around issue |

## Migration Plan

1. Extract existing VESA init code and bank-switched `put_pixel` from `kernel.asm` into `video.asm`.
2. Replace inline video calls in `kernel.asm` with `call video_put_pixel`, etc.
3. Extend `video.asm` with VBE 2.0 mode selection and unreal-mode trampoline.
4. Validate with `make run` (QEMU); confirm desktop renders at new resolution.
5. If QEMU shows correct output, test on physical hardware.

**Rollback:** revert `include 'video.asm'` and restore original inline code — no binary format change, so rollback is a one-line diff.

## Open Questions

- Should `video_fill_rect` use `rep stosd` (32-bit `a32` store) for bulk fills, or loop-based `video_put_pixel`? Prefer `rep stosd` for performance; confirm FASM `a32` prefix syntax in unreal mode.
- QEMU's VBE implementation supports linear framebuffer — does the CI/testing environment have a capable QEMU version? (Expected: yes, `qemu-system-i386` >= 2.x supports VBE 2.0.)
