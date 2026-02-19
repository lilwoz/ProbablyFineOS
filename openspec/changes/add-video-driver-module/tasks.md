# Tasks: add-video-driver-module

## 1. Scaffold video.asm module

- [ ] 1.1 Create `video.asm` file with section headers, include guard comment, and data section (GDT for unreal mode, VBE info block buffer, mode list buffer, framebuffer address variable, active width/height/bpp variables)
- [ ] 1.2 Define public equates: `VIDEO_MAX_WIDTH`, `VIDEO_MAX_HEIGHT`, `VIDEO_BPP`, `VIDEO_FB_SEG`

## 2. Implement VESA VBE 2.0 mode negotiation

- [ ] 2.1 Implement `video_vbe_get_info` — call INT 0x10/AX=0x4F00, verify VBE signature and version
- [ ] 2.2 Implement `video_vbe_get_mode_info` — call INT 0x10/AX=0x4F01, parse `ModeAttributes`, `WinGranularity`, `PhysBasePtr`, `XResolution`, `YResolution`, `BitsPerPixel`
- [ ] 2.3 Implement `video_select_mode` — iterate preferred mode list (D3 in design.md), call `video_vbe_get_mode_info` for each, return first supported linear mode or best bank-switched fallback

## 3. Implement unreal-mode trampoline

- [ ] 3.1 Define 16-byte GDT with null descriptor and flat 4 GB read/write data descriptor (base=0, limit=0xFFFFFFFF, G=1, D=1)
- [ ] 3.2 Implement `video_enter_unreal`:
  - Save `ds`/`es`
  - Load GDT with `lgdt`
  - Set PE bit in CR0, load flat data selector into `es`, clear PE bit
  - Restore `ds`; `es` now has 4 GB limit
- [ ] 3.3 Verify with QEMU that `es` flat limit survives return to real mode

## 4. Implement drawing primitive API

- [ ] 4.1 `video_clear` — fill entire framebuffer with color in `eax`; use `rep stosd` with `a32` prefix
- [ ] 4.2 `video_put_pixel` — write one pixel at (cx=x, dx=y) with color in `eax`; compute `offset = y * pitch + x * (bpp/8)`; `mov [a32 es:ebx], eax` (masked to bpp)
- [ ] 4.3 `video_draw_hline` — horizontal line (cx=x0, dx=y, si=x1, color in `eax`); inner `rep stosd` or word/byte loop
- [ ] 4.4 `video_draw_vline` — vertical line (cx=x, dx=y0, si=y1, color in `eax`); step by pitch
- [ ] 4.5 `video_draw_rect` — outline rectangle (cx=x, dx=y, si=w, di=h, color in `eax`); four line calls
- [ ] 4.6 `video_fill_rect` — filled rectangle (cx=x, dx=y, si=w, di=h, color in `eax`); row-by-row `rep stosd`

## 5. Implement public init entry point

- [ ] 5.1 Implement `video_init`:
  - Call `video_vbe_get_info`; on failure set CF, return
  - Call `video_select_mode`; store chosen mode number, resolution, bpp, and framebuffer address
  - Call `video_enter_unreal`
  - Call INT 0x10/AX=0x4F02 to set the chosen mode (linear bit set if VBE 2.0)
  - Return CF clear on success, CF set on failure

## 6. Integrate into kernel.asm

- [ ] 6.1 Add `include 'video.asm'` near top of `kernel.asm` (after equates, before code)
- [ ] 6.2 Replace existing VESA init sequence in kernel entry with `call video_init`; add error branch that falls back to text mode error message
- [ ] 6.3 Replace all inline `put_pixel` / bank-switch calls in `draw_desktop`, window rendering, and mouse cursor with `call video_put_pixel` (and `call video_fill_rect` where applicable)
- [ ] 6.4 Update any hardcoded `640`/`480` constants to use `VIDEO_MAX_WIDTH`/`VIDEO_MAX_HEIGHT` equates

## 7. Build and test

- [ ] 7.1 `make` — confirm zero assembly errors
- [ ] 7.2 `make run` (QEMU) — confirm desktop renders at target resolution with correct colors
- [ ] 7.3 Verify mouse cursor and window drawing use new primitives correctly
- [ ] 7.4 Test fallback: temporarily restrict preferred modes to force bank-switched path; confirm 640×480 still renders
- [ ] 7.5 (Optional) Physical hardware test via USB image
