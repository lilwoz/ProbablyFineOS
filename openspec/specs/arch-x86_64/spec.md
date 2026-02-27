# arch-x86_64 Specification

## Purpose
Defines x86 architecture-specific requirements for ProbablyFineOS, including CPU feature detection, register usage, exception handling, and system call interfaces.

## Implementation Note
Current implementation targets **x86 32-bit protected mode** as foundation. 64-bit long mode support is planned for future but not yet implemented. This spec documents both current (32-bit) and planned (64-bit) requirements.

## Requirements

### Requirement: Exception Handling (32-bit Implementation)
The system SHALL handle all CPU exceptions (vectors 0-31) by:
- Installing ISR for each exception in IDT
- Saving all register state on exception entry
- Printing exception information (name, EIP, error code, registers)
- Halting system gracefully (no triple-fault)

Exception ISRs SHALL distinguish between exceptions with/without error codes:
- **Without error code** (0-7, 9, 16-21): Push dummy 0 before common handler
- **With error code** (8, 10-14, 17, 21, 29-30): CPU pushes error code automatically

#### Scenario: General Protection Fault (32-bit)
- **WHEN** Code attempts invalid memory access or segment violation
- **THEN** CPU triggers exception 13 (General Protection Fault)
- **AND** pushes error code identifying segment selector
- **AND** ISR saves all registers (EAX-EDI, ESP, EIP, EFLAGS)
- **AND** displays exception details and register dump
- **AND** halts system with freeze loop
### Requirement: x86_64 Long Mode Support
The system SHALL target x86_64 CPUs with long mode, SYSCALL/SYSRET, NX bit, and 4-level paging support.

Boot code SHALL verify CPU features via CPUID before entering long mode. If unsupported, halt with error message.

#### Scenario: CPU feature detection
- **WHEN** Stage2 bootloader executes before entering long mode
- **THEN** it runs `CPUID.80000001h` and checks EDX bits 29 (long mode), 11 (SYSCALL/SYSRET), 20 (NX bit)
- **AND** if any required feature is missing, displays "CPU not supported" via BIOS and halts
- **OTHERWISE** proceeds with long mode entry sequence

### Requirement: Long Mode Entry Protocol
Stage2 bootloader SHALL transition from 16-bit real mode to 64-bit long mode by:
1. Setting up 4-level page tables (identity map + higher-half kernel mapping)
2. Loading GDT with 64-bit code/data segments
3. Enabling CR4.PAE, loading CR3 with PML4 address
4. Setting IA32_EFER.LME, then CR0.PG
5. Far jumping to 64-bit code segment

Kernel entry point SHALL receive control in 64-bit mode with paging enabled and higher-half mapping active at 0xFFFF800000000000+.

#### Scenario: Successful long mode transition
- **WHEN** Stage2 has verified CPU features and prepared page tables
- **THEN** it enables paging (CR0.PG=1) which activates long mode (LME+PE+PG)
- **AND** performs far jump to 64-bit code segment
- **AND** kernel entry receives control in 64-bit mode with higher-half mapping active

### Requirement: Register Usage Conventions
The kernel SHALL use full 64-bit registers (RAX-RDX, RSI, RDI, RBP, RSP, R8-R15).

The kernel SHALL NOT use floating-point/SIMD registers (SSE/AVX) and SHALL compile with `-mno-sse -mno-avx`.

Userland MAY use SSE2 instructions (state saved on context switch).

#### Scenario: Kernel floating-point prohibition
- **WHEN** Kernel code is compiled
- **THEN** compiler flags include `-mno-sse -mno-mmx -mno-avx` to prevent FP usage
- **AND** if kernel accidentally uses FP instructions, CPU raises #UD (invalid opcode) exception

