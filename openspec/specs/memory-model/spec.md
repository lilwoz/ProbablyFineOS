# memory-model Specification

## Purpose
TBD - created by archiving change os-architecture-contract. Update Purpose after archive.
## Requirements
### Requirement: 4-Level Paging
The system SHALL use 4-level paging (PML4/PDPT/PD/PT) with 4KB pages. CR3 points to PML4 physical address (per-process).

#### Scenario: Page table walk
- **WHEN** CPU translates virtual address 0x400000
- **THEN** it indexes PML4[0], PDPT[0], PD[2], PT[0]
- **AND** retrieves physical page address from PT entry
- **AND** accesses physical memory at (page_phys | offset)

### Requirement: Virtual Address Layout
Userland SHALL occupy 0x0-0x7FFFFFFFFFFF. Kernel SHALL occupy 0xFFFF800000000000+ (higher-half). Direct physical map at 0xFFFF800000000000, kernel image at 0xFFFFFFFFC0000000.

#### Scenario: Per-process address space
- **WHEN** Process A runs with CR3=A_pml4
- **THEN** userland mappings (PML4[0-255]) are unique to Process A
- **AND** kernel mappings (PML4[256-511]) are shared across all processes
- **WHEN** Context switch to Process B: mov cr3, B_pml4
- **THEN** userland mappings change, kernel mappings remain identical

