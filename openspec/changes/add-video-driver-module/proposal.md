# Change: Add Modular Video Driver with VESA VBE 2.0 Linear Framebuffer

## Why

The kernel currently performs all video operations inline inside `kernel.asm`, using VESA VBE mode 0x101 (640×480, 256-color) via bank-switched memory access. This couples rendering tightly to the monolithic kernel, limits resolution and color depth, and forces expensive bank-switch calls on every cross-boundary pixel write. A dedicated `video.asm` module with VESA VBE 2.0 linear framebuffer support removes this coupling, enables higher resolutions and color depths, and provides a clean primitive API for all rendering subsystems.

## What Changes

- **NEW** `video.asm` — self-contained video driver module included by `kernel.asm`
- **NEW** VESA VBE 2.0 mode negotiation: enumerate modes, select best available (target 800×600 or 1024×768, 16/24/32 bpp), fall back to VBE 1.2 bank-switched mode if VBE 2.0 linear framebuffer is unavailable
- **NEW** Unreal mode (big real mode) trampoline for linear framebuffer writes exceeding the 64 KB segment limit, returning to 16-bit real mode for BIOS calls
- **NEW** Drawing primitive API: `video_clear`, `video_put_pixel`, `video_draw_hline`, `video_draw_vline`, `video_draw_rect`, `video_fill_rect`
- **NEW** Resolution/color-depth constants exposed as equates for use by all subsystems
- **MODIFIED** `kernel.asm` — inline VESA setup and pixel-write routines replaced with `include 'video.asm'` and calls to the new API
- **BREAKING** Existing callers of bank-switched pixel routines must be updated to call `video_put_pixel`

## Impact

- Affected specs: `video-driver` (new capability)
- Affected code: `kernel.asm` (video init, draw_desktop, window rendering, mouse cursor), `build.sh` (no change expected)
