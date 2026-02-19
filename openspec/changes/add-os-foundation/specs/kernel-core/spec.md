## ADDED Requirements

### Requirement: Kernel Entry Point
The system SHALL provide a kernel entry point in `kernel/kernel.asm` at physical
address `0x10000`. On entry (from Stage 2):
1. Set up segment registers (DS, ES, SS) to the flat data segment (0x10)
2. Initialize a kernel stack at a well-known address (e.g., `0x90000`, growing down)
3. Call subsystem init functions in order: `gdt_init`, `idt_init`, `pic_init`,
   `vga_init`, `keyboard_init`, `mouse_init`, then `shell_main`
4. If `shell_main` returns, enter an infinite HLT loop

#### Scenario: Kernel initializes subsystems in order
- **WHEN** Stage 2 jumps to `0x10000`
- **THEN** the kernel sets up segments and stack, calls each `*_init` function,
  and finally calls `shell_main`

#### Scenario: Unexpected return from shell
- **WHEN** `shell_main` returns (should not happen normally)
- **THEN** the kernel enters an infinite `hlt` loop and does not triple-fault

### Requirement: Global Descriptor Table
The system SHALL provide `kernel/gdt.asm` with a GDT exported via `gdt_init`:
- Entry 0: Null descriptor
- Entry 1: 32-bit code segment (base=0, limit=4GB, DPL=0)
- Entry 2: 32-bit data segment (base=0, limit=4GB, DPL=0)
- Entry 3: 32-bit code segment (DPL=3, for future user mode)
- Entry 4: 32-bit data segment (DPL=3, for future user mode)

`gdt_init` SHALL load the new GDT with `lgdt` and reload all segment registers.

#### Scenario: GDT loaded at boot
- **WHEN** `gdt_init` is called from `kernel_main`
- **THEN** `lgdt [gdt_descriptor]` executes, CS is reloaded via far jump,
  and DS/ES/SS/FS/GS are reloaded with the kernel data selector (0x10)

### Requirement: Interrupt Descriptor Table
The system SHALL provide `kernel/idt.asm` with:
- 256 IDT entries, all initially pointing to `isr_default` (which prints exception
  info and halts)
- CPU exception handlers for vectors 0–7 (divide-by-zero, debug, NMI, breakpoint,
  overflow, bound, invalid opcode, device-not-available)
- `idt_init` SHALL fill the IDT table and call `lidt`

#### Scenario: Default exception handler fires
- **WHEN** a CPU exception (e.g., divide-by-zero, vector 0) occurs
- **THEN** the IDT dispatches to the handler, which prints the exception number
  to the VGA screen and halts

### Requirement: 8259A PIC Initialization
The system SHALL provide `kernel/pic.asm` with `pic_init` that:
- Remaps IRQ0–7 to interrupt vectors 0x20–0x27
- Remaps IRQ8–15 to interrupt vectors 0x28–0x2F
- Masks all IRQs initially; individual drivers unmask their own IRQ

#### Scenario: IRQ remapping prevents spurious exceptions
- **WHEN** `pic_init` completes
- **THEN** hardware interrupts from the PIC no longer overlap CPU exception
  vectors (0x00–0x1F), eliminating double-fault confusion
