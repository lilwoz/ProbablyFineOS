# kernel-core Specification

## Purpose
Defines the core kernel subsystems including initialization order, descriptor tables, interrupt handling, scheduling, and timer management for ProbablyFineOS.

## Requirements
### Requirement: Kernel Entry Point (Updated)
The system SHALL provide a kernel entry point in `kernel/kernel.asm` at physical
address `0x10000`. On entry (from Stage 2):
1. Set up segment registers (DS, ES, SS) to the flat data segment (0x10)
2. Initialize a kernel stack at a well-known address (`0x90000`, growing down)
3. Call subsystem init functions in order:
   - `gdt_init` — Global Descriptor Table
   - `fpu_init` — FPU/SSE initialization with CPUID check
   - `idt_init` — Interrupt Descriptor Table
   - `install_exception_handlers` — CPU exception handlers (0-31)
   - `pic_init` — 8259A PIC remapping
   - `thread_init` — Thread subsystem and idle thread
   - `scheduler_init` — Ready queue initialization
   - `pit_init` — System timer at 100 Hz
   - `vga_init` — VGA text mode driver
   - `keyboard_init`, `mouse_init` — Input drivers
   - `shell_main` — Interactive shell
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

### Requirement: System Timer (PIT)
The system SHALL provide `kernel/pit.asm` with `pit_init(frequency)` that:
- Configures PIT channel 0 for programmable frequency (default 100 Hz)
- Sends command byte 0x36 (channel 0, mode 3 square wave, lo/hi byte)
- Calculates divisor: `1193182 / frequency`
- Writes divisor to port 0x40 (low byte then high byte)
- Installs IRQ0 handler into IDT vector 0x20
- Unmasks IRQ0 on PIC

#### Scenario: Timer fires at 100 Hz
- **WHEN** `pit_init(100)` is called
- **THEN** PIT generates IRQ0 every 10ms
- **AND** `timer_tick()` function is called on each IRQ
- **AND** global tick counter increments
- **AND** scheduler checks for quantum expiration

### Requirement: Round-Robin Scheduler
The system SHALL provide `kernel/scheduler.asm` with:
- **Ready Queue**: Circular linked list of READY threads
- **schedule()**: Selects next READY thread from queue (round-robin)
- **scheduler_tick()**: Called on each timer interrupt, decrements quantum
- **Idle Thread**: TID 0, runs when no threads READY, executes HLT in loop

#### Scenario: Thread quantum expires
- **WHEN** Timer tick occurs and current thread quantum reaches 0
- **THEN** scheduler adds current thread to end of ready queue
- **AND** selects next READY thread from front of queue
- **AND** calls `context_switch(old, new)`
- **AND** new thread gets fresh quantum (100 ticks)

#### Scenario: No threads ready
- **WHEN** Ready queue is empty and scheduler is called
- **THEN** scheduler returns idle thread (TID 0)
- **AND** idle thread executes HLT instruction (power saving)
- **AND** next interrupt wakes CPU and scheduler checks again

### Requirement: Exception Handling (Expanded)
The system SHALL provide `kernel/exceptions.asm` with handlers for all CPU exceptions 0-31:
- Exceptions without error code (0-7, 9, 16-21): Use stub that pushes dummy 0
- Exceptions with error code (8, 10-14, 17, 21, 29-30): Error code already on stack
- All exceptions call common handler `exception_common`
- Handler prints exception name, EIP, error code, register dump
- Handler halts system gracefully with freeze loop

#### Scenario: Divide-by-zero exception
- **WHEN** Code executes `div edx` with EDX=0
- **THEN** CPU triggers exception 0 (Divide Error)
- **AND** IDT dispatches to exception handler
- **AND** handler prints "Exception: Divide By Zero (#DE)"
- **AND** displays EIP, error code, all registers
- **AND** system halts with "System halted." message

### Requirement: FPU/SSE Initialization
The system SHALL provide `kernel/fpu.asm` with `fpu_init()` that:
- Checks CPUID for FXSR support (CPUID.01h:EDX[bit 24])
- If supported: enables CR4.OSFXSR (bit 9) and CR4.OSXMMEXCPT (bit 10)
- Sets global flag `fxsr_available` to 1 if supported, 0 otherwise
- Initializes FPU with `finit` instruction
- Clears CR0.EM (bit 2) and sets CR0.MP (bit 1)

#### Scenario: FXSR available
- **WHEN** CPU supports FXSR (e.g., Pentium II or later)
- **THEN** `fpu_init()` enables FXSR in CR4
- **AND** sets `fxsr_available = 1`
- **AND** context switches use FXSAVE/FXRSTOR

#### Scenario: FXSR not available
- **WHEN** CPU does not support FXSR (e.g., old Pentium)
- **THEN** `fpu_init()` sets `fxsr_available = 0`
- **AND** context switches skip FXSAVE/FXRSTOR
- **AND** FPU state is not preserved (acceptable fallback)

