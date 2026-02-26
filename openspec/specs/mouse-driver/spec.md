# mouse-driver Specification

## Purpose
TBD - created by archiving change add-os-foundation. Update Purpose after archive.
## Requirements
### Requirement: PS/2 Mouse Driver
The system SHALL provide `drivers/input/mouse.asm` implementing a PS/2 mouse
driver using IRQ12 (IDT vector 0x2C).

Exported symbols:
| Symbol          | Description                                                         |
|-----------------|---------------------------------------------------------------------|
| `mouse_init`    | Enable PS/2 auxiliary port, set sample rate, unmask IRQ12           |
| `mouse_x`       | Signed 16-bit current X position (clamped to [0, screen_width-1])  |
| `mouse_y`       | Signed 16-bit current Y position (clamped to [0, screen_height-1]) |
| `mouse_buttons` | Byte: bit0=left, bit1=right, bit2=middle button state              |

Mouse initialization sequence (via PS/2 controller ports `0x60`/`0x64`):
1. Send `0xA8` to `0x64` (enable auxiliary device)
2. Send `0x20` to `0x64`, read byte, OR with `0x02`, send `0x60` + modified byte
   (enable IRQ12 in PS/2 status)
3. Send `0xD4` to `0x64` + `0xF4` to `0x60` (enable data reporting on mouse)

The IRQ12 handler SHALL:
1. Accumulate 3 bytes per PS/2 packet (state machine with `mouse_phase` counter)
2. On 3rd byte: extract button bits from byte 0, X delta from byte 1,
   Y delta from byte 2 (byte 0 bit 4/5 = sign extension)
3. Add deltas to `mouse_x`/`mouse_y`, clamp to screen bounds
4. Send EOI to both PIC slave (`0xA0`) and master (`0x20`)

#### Scenario: Mouse move right
- **WHEN** mouse moves right (X delta = +10 in packet)
- **THEN** IRQ12 fires three times (one per byte), and after byte 3,
  `mouse_x` increases by 10 (clamped to max screen width)

#### Scenario: Left button press
- **WHEN** left mouse button is pressed
- **THEN** bit 0 of the first packet byte is set and `mouse_buttons` bit 0 is set to 1

#### Scenario: Mouse absent
- **WHEN** PS/2 controller reports no auxiliary device (status bit)
- **THEN** `mouse_init` skips initialization and leaves `mouse_x/y/buttons` at 0;
  no error is raised

#### Scenario: Coordinate clamping
- **WHEN** `mouse_x` is at maximum (799 for 800-wide screen) and X delta is +5
- **THEN** `mouse_x` remains 799 (clamped, no overflow)

