# project-structure Specification

## Purpose
TBD - created by archiving change add-os-foundation. Update Purpose after archive.
## Requirements
### Requirement: Directory Layout
The project SHALL follow a modular directory structure where each subsystem
resides in its own directory so contributors can locate and modify a single
driver without touching unrelated code.

```
ProbablyFineOS/
├── boot/              # Stage 1 (MBR) and Stage 2 bootloader
├── kernel/            # Kernel entry point and CPU subsystems
├── drivers/
│   ├── video/         # VGA and VESA drivers
│   └── input/         # Keyboard and mouse drivers
├── include/           # Shared headers: macros, constants, structs
├── build/             # Generated artifacts (.img, .o, listings)
└── tools/             # Helper scripts (disk image creator, etc.)
```

#### Scenario: New subsystem added
- **WHEN** a developer adds a new driver (e.g., `drivers/serial/`)
- **THEN** the new directory is self-contained with its own `.asm` file
  and the kernel includes it via `include` directive without restructuring
  existing files

### Requirement: Shared Include Headers
The project SHALL provide three shared include files in `include/` that all
subsystem files MAY reference:
- `constants.inc` — named constants for I/O port addresses, memory addresses, VGA colors
- `macros.inc` — FASM macros for common operations (`outb`, `inb`, `io_delay`, `print_str`)
- `structs.inc` — FASM struct definitions for GDT descriptors, IDT descriptors, mouse packets

#### Scenario: Driver uses a port constant
- **WHEN** `drivers/input/keyboard.asm` references `KBD_DATA_PORT`
- **THEN** the symbol is resolved from `include/constants.inc` without redefinition

#### Scenario: Macro prevents code duplication
- **WHEN** multiple files need to write to an I/O port
- **THEN** they all call `outb port, value` macro defined once in `include/macros.inc`

### Requirement: Build System
The project SHALL provide a top-level `Makefile` with the following targets:

| Target  | Action                                                                   |
|---------|--------------------------------------------------------------------------|
| `all`   | Assemble all sources and produce `build/os.img` bootable disk image      |
| `clean` | Remove all generated files from `build/`                                 |
| `run`   | Launch `build/os.img` in QEMU (x86, 512 MB RAM, VGA output)             |
| `debug` | Launch QEMU with GDB stub on port 1234, GDB server paused at entry       |

#### Scenario: Fresh build
- **WHEN** developer runs `make` in project root
- **THEN** FASM assembles all `.asm` files, `dd` produces a bootable `.img`,
  and exit code is 0 with no errors

#### Scenario: QEMU launch
- **WHEN** developer runs `make run`
- **THEN** QEMU starts with `build/os.img`, the OS boots to the demo shell

### Requirement: Conditional Architecture Flag
The build system SHALL support an `ARCH` variable (`32` or `64`) that selects
between 32-bit protected mode and 64-bit long mode code paths via FASM
conditional assembly (`if ARCH = 64 ... end if`).

Default: `ARCH = 32`.

#### Scenario: 32-bit default build
- **WHEN** `make` is run without overrides
- **THEN** FASM sets `ARCH = 32` and produces a 32-bit protected-mode kernel

#### Scenario: 64-bit build flag
- **WHEN** `make ARCH=64` is run
- **THEN** FASM sets `ARCH = 64` and assembles the long-mode code paths

