# bootloader Specification

## Purpose
TBD - created by archiving change add-os-foundation. Update Purpose after archive.
## Requirements
### Requirement: Stage 1 MBR Bootloader
The system SHALL provide a 512-byte MBR bootloader in `boot/stage1.asm` that:
1. Is loaded by BIOS at physical address `0x7C00`
2. Reads Stage 2 from disk sector 2 onward into address `0x0500` using BIOS INT 13h (CHS mode)
3. Jumps to Stage 2 at `0x0500`
4. Ends with the MBR boot signature `0xAA55` at bytes 510–511

#### Scenario: Successful Stage 2 load
- **WHEN** BIOS loads the MBR and transfers control to `0x7C00`
- **THEN** Stage 1 reads Stage 2 sectors from disk using INT 13h/AH=02h,
  copies them to `0x0500`, and jumps to `0x0500`

#### Scenario: Disk read error
- **WHEN** INT 13h returns a non-zero error code in AH
- **THEN** Stage 1 prints `"Disk error"` via BIOS INT 10h and halts (HLT)

### Requirement: Stage 2 Loader
The system SHALL provide a Stage 2 loader in `boot/stage2.asm` that:
1. Enables the A20 address line via the keyboard controller method
2. Reads the kernel binary from disk to physical address `0x10000`
3. Sets up a minimal flat GDT (null, 32-bit code CS=0x08, 32-bit data DS=0x10)
4. Enables CR0.PE to switch to 32-bit protected mode
5. Far-jumps to the kernel entry at `0x10000`

#### Scenario: A20 enable via keyboard controller
- **WHEN** Stage 2 runs in real mode
- **THEN** it sends `0xD1` to port `0x64`, then `0xDF` to port `0x60` to
  enable A20, and verifies by writing/reading across the 1 MB boundary

#### Scenario: Protected mode entry
- **WHEN** Stage 2 has loaded the kernel and set up the GDT
- **THEN** it sets CR0 bit 0, performs a far jump to flush the pipeline,
  and arrives at the kernel entry point in 32-bit protected mode

#### Scenario: Kernel load failure
- **WHEN** disk read for kernel sectors fails
- **THEN** Stage 2 prints `"Kernel load error"` in real mode via INT 10h and halts

