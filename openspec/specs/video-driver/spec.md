# video-driver Specification

## Purpose
TBD - created by archiving change add-os-foundation. Update Purpose after archive.
## Requirements
### Requirement: VGA Text Mode Driver
The system SHALL provide `drivers/video/vga.asm` implementing VGA text mode 80×25.

Exported procedures:
| Symbol         | Description                                                  |
|----------------|--------------------------------------------------------------|
| `vga_init`     | Clear screen, set cursor to (0,0), set default colors        |
| `vga_clear`    | Fill entire text buffer with spaces (current foreground/bg)  |
| `vga_putc`     | Write one character at cursor; advance cursor; handle `\n`   |
| `vga_puts`     | Write null-terminated string via repeated `vga_putc`         |
| `vga_set_color`| Set foreground (low 4 bits) and background (high 4 bits)     |
| `vga_set_cursor`| Move hardware cursor to (row, col) via CRTC ports 0x3D4/0x3D5|
| `vga_scroll`   | Scroll text buffer up by one line, blank last row            |

The text buffer SHALL be memory-mapped at `0xB8000`.
Each cell is 2 bytes: character byte + attribute byte (fg | bg<<4).

#### Scenario: Single character output
- **WHEN** `vga_putc` is called with ASCII value `0x41` ('A')
- **THEN** byte `0x41` is written to the current cursor cell and the attribute
  byte is written alongside; cursor column advances by 1

#### Scenario: Newline handling
- **WHEN** `vga_putc` is called with `0x0A` (newline)
- **THEN** cursor moves to column 0 of the next row; if already on row 24,
  `vga_scroll` is called first

#### Scenario: Screen scroll
- **WHEN** cursor is at row 24, column 79 and `vga_putc` is called
- **THEN** all rows shift up by one, the last row is cleared with spaces,
  and the cursor is placed at the start of row 24

### Requirement: VESA Linear Framebuffer Driver
The system SHALL provide `drivers/video/vesa.asm` implementing VESA graphics mode.

Mode: 800×600, 32 bits per pixel (BGRA), linear framebuffer.
VESA mode is set via BIOS INT 10h/AX=0x4F02 **before** entering protected mode
(called from Stage 2 if `VESA_ENABLE = 1`).

Exported procedures:
| Symbol          | Description                                                 |
|-----------------|-------------------------------------------------------------|
| `vesa_init`     | Store framebuffer base address from VESA info block         |
| `vesa_clear`    | Fill framebuffer with a single 32-bit color                 |
| `vesa_put_pixel`| Write one pixel at (x, y) with 32-bit BGRA color           |
| `vesa_fill_rect`| Fill axis-aligned rectangle with a color                    |
| `vesa_puts`     | Render null-terminated string using 8×16 bitmap font        |

#### Scenario: Pixel write
- **WHEN** `vesa_put_pixel` is called with x=10, y=20, color=0x00FF0000 (blue in BGRA)
- **THEN** the 4 bytes at `fb_base + (20 * 800 + 10) * 4` are written as `[00, 00, FF, 00]`

#### Scenario: Rectangle fill
- **WHEN** `vesa_fill_rect` is called with x=0, y=0, w=800, h=600, color=0x00000000
- **THEN** entire framebuffer is overwritten with zeros (black screen)

#### Scenario: Text rendering in VESA mode
- **WHEN** `vesa_puts` is called with a pointer to "Hello"
- **THEN** each character is rendered using the 8×16 bitmap font at the current
  graphics cursor position in the foreground color

### Requirement: 8x16 Bitmap Font
The system SHALL include `drivers/video/font.inc` containing a complete 8×16
bitmap font for ASCII characters 0x20–0x7E embedded as raw binary data.
Each character occupies 16 consecutive bytes (one byte per row, MSB = leftmost pixel).

#### Scenario: Font lookup
- **WHEN** `vesa_puts` renders character `0x41` ('A')
- **THEN** it reads 16 bytes from `font_data + (0x41 * 16)` and plots the
  corresponding pixel pattern

