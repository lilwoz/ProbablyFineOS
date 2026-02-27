# OS Architecture Contract

## Why

Define the fundamental architectural contract for ProbablyFineOS — the target design toward which all future development will evolve. This establishes:

- **Execution model**: x86_64 long mode with preemptive multitasking and ring3 userland separation
- **ABI stability**: formal userland contract (ELF64, SysV AMD64, SYSCALL interface)
- **Memory model**: 4-level paging with per-process address spaces and kernel higher-half mapping
- **Driver architecture**: clear API boundaries allowing future migration to userland micro-kernel style
- **Build discipline**: unified linker scripts, symbol tables, and tracing infrastructure

This is NOT an immediate implementation plan — it's the North Star that guides incremental changes. Future proposals will reference this contract when adding features (scheduler, process loader, syscall handlers, etc.).

## What changes

This proposal creates architectural specification documents that define:

1. **Target architecture**: x86_64 long mode requirements, boot protocol, CPU feature detection
2. **Process model**: address space layout, ELF64 loading, ring0/ring3 separation, context switch contract
3. **System call ABI**: SYSCALL/SYSRET mechanism, register conventions (SysV AMD64), syscall numbering
4. **Memory management contract**: 4-level paging structures, higher-half kernel mapping (0xFFFF800000000000+), per-process page tables
5. **Driver API boundaries**: kernel-internal driver interface design that allows future userland migration
6. **Build system contract**: linker script requirements, symbol table conventions, section layout, debug tracing hooks

No implementation code is added — only architectural specs. Future changes will implement pieces of this architecture incrementally, referencing these specs for design authority.

## Impact

- **Documentation**: Establishes authoritative architectural reference for all contributors
- **Compatibility**: Freezes userland ABI (ELF64 format, syscall numbers, calling convention) — changes to these require explicit versioning
- **Development**: All future kernel/driver/userland PRs must align with this contract
- **Current code**: The existing 32-bit protected-mode kernel is acknowledged as "bootstrap phase" — incremental migration to 64-bit is expected

## Risks

- **Scope creep**: Defining target architecture without implementation could lead to over-design. Mitigation: keep specs focused on invariants (ABI, memory layout) not implementation details.
- **Premature optimization**: Detailed specs before real-world usage may miss edge cases. Mitigation: mark sections as "provisional" and allow refinement based on implementation experience.
- **Compatibility burden**: Once userland ABI is stable, changes are costly. Mitigation: initially mark ABI as "unstable" (version 0.x) until first userland programs exist.

## Alternatives considered

1. **Ad-hoc evolution**: Let architecture emerge organically without upfront contract. Rejected because it leads to ABI churn and incompatible userland binaries.
2. **Pure microkernel from day 1**: Require all drivers in userland immediately. Rejected as too ambitious — incremental migration is more practical.
3. **32-bit architecture**: Stay with current x86 protected mode. Rejected because modern toolchains, libraries, and ecosystem assume x86_64.
