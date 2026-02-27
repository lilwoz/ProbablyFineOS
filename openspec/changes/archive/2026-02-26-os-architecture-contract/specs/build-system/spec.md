## ADDED Requirements

### Requirement: Linker Script — Higher-Half Kernel
Kernel SHALL be linked to 0xFFFFFFFFC0000000 (higher-half) with sections: .boot (identity-mapped stub), .text (code), .rodata (read-only), .data, .bss. All 4KB-aligned.

#### Scenario: Kernel linking
- **WHEN** Linker processes kernel.ld
- **THEN** it places .text section at 0xFFFFFFFFC0000000+
- **AND** exports symbols: _kernel_start, _kernel_end, _text_start, _text_end, etc.
- **AND** aligns all sections to 4KB boundaries

### Requirement: Compiler Flags
Kernel SHALL compile with: -mcmodel=kernel (top 2GB), -mno-red-zone (no red zone below RSP), -mno-sse (no FP in kernel), -fno-pie (fixed address), -O2 -g (optimize + debug).

#### Scenario: Kernel compilation
- **WHEN** GCC compiles kernel.c with -mcmodel=kernel -mno-sse
- **THEN** generated code uses 32-bit signed offsets to access kernel symbols
- **AND** never emits SSE/AVX instructions
- **AND** disables red zone optimization (safe for interrupts)
