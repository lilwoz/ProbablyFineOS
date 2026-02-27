## ADDED Requirements

### Requirement: Exception Handler Installation
The kernel SHALL install interrupt service routines (ISRs) for all CPU exceptions (vectors 0-31) in the IDT.

Exception handlers SHALL save full register state before calling C exception handler.

#### Scenario: Exception ISR installation
- **WHEN** Kernel initializes IDT
- **THEN** it installs ISRs for exceptions 0-31 using `idt_set_gate(vector, handler_addr)`
- **AND** ISRs with error code (8, 10-14, 17): CPU pushes error code before calling ISR
- **AND** ISRs without error code: ISR pushes dummy error code (0) for consistent stack layout
- **AND** all ISRs jump to common handler that saves registers (pushad, push_segs)

### Requirement: Exception Register Dump
Exception handlers SHALL print diagnostic information including exception number, EIP, error code, and register dump before halting.

For page fault (exception 14), handler SHALL read CR2 register (faulting address) and include in dump.

#### Scenario: Page fault exception handling
- **WHEN** CPU triggers page fault (exception 14)
- **THEN** exception handler prints: "KERNEL PANIC: Page Fault"
- **AND** prints EIP (instruction pointer that caused fault)
- **AND** prints error code (present bit, write bit, user bit)
- **AND** reads CR2 register: `mov eax, cr2`
- **AND** prints "Faulting address: 0xXXXXXXXX" (CR2 value)
- **AND** prints register dump: EAX-EDI, segment registers, stack frame
- **AND** halts system with `freeze` (cli + hlt loop)
