# keyboard-driver Specification

## Purpose
TBD - created by archiving change add-os-foundation. Update Purpose after archive.
## Requirements
### Requirement: PS/2 Keyboard Driver
The system SHALL provide `drivers/input/keyboard.asm` implementing a PS/2
keyboard driver using IRQ1 (IDT vector 0x21).

Exported symbols:
| Symbol          | Description                                                    |
|-----------------|----------------------------------------------------------------|
| `keyboard_init` | Flush PS/2 output buffer, unmask IRQ1 in PIC                  |
| `keyboard_getc` | Return next ASCII byte from ring buffer (0 if buffer empty)    |
| `key_buffer`    | 256-byte circular ring buffer (head/tail indices)              |

The IRQ1 handler SHALL:
1. Read scancode from port `0x60`
2. Translate using scancode-set-1 table to ASCII
3. Handle make codes only (bit 7 = 0); ignore break codes (bit 7 = 1)
4. Push translated ASCII into `key_buffer`
5. Send EOI (`0x20`) to PIC master (port `0x20`)

Modifier keys tracked in a `key_modifiers` byte:
- Bit 0: Shift (left or right)
- Bit 1: Ctrl
- Bit 2: Alt
- Bit 3: CapsLock (toggle)

#### Scenario: Regular key press
- **WHEN** the user presses 'A' (scancode `0x1E`)
- **THEN** IRQ1 fires, the handler reads `0x1E` from port `0x60`,
  looks up ASCII `'a'` (or `'A'` if Shift/CapsLock active),
  places it in `key_buffer`, and sends EOI

#### Scenario: Shift modifier
- **WHEN** Shift is held and 'A' is pressed
- **THEN** the handler sets bit 0 of `key_modifiers` on Shift make code,
  and the resulting character is `'A'` (uppercase)

#### Scenario: Buffer wrap-around
- **WHEN** 256 characters are typed without being consumed
- **THEN** the oldest character is silently overwritten (ring buffer behavior)

#### Scenario: Empty buffer read
- **WHEN** `keyboard_getc` is called and `key_buffer` is empty
- **THEN** it returns `0` immediately without blocking

### Requirement: Keyboard Scancode Table
The keyboard driver SHALL embed a complete scancode-set-1 to ASCII lookup table
covering all printable ASCII characters (0x20–0x7E) and the following specials:
`Enter` (0x0D), `Backspace` (0x08), `Tab` (0x09), `Escape` (0x1B).
Shift variants (e.g., digits → symbols) SHALL have a separate table.

#### Scenario: Digit shift variant
- **WHEN** Shift is held and '1' is pressed (scancode `0x02`)
- **THEN** the character `'!'` is placed in the buffer (from the shifted table)

