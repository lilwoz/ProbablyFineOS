# Architecture Contract — Tasks

> **Note**: This proposal defines the architectural contract, not an immediate implementation plan. Tasks listed here are **documentation milestones** to complete this proposal. Actual implementation work will be organized in separate future proposals that reference this contract.

## Documentation Tasks

### 1. Core Architecture Specs

- [ ] **1.1** Create `arch-x86_64` spec
  - Target: x86_64 long mode requirements
  - Boot protocol (Multiboot2 compliance)
  - CPU feature detection (CPUID checks)
  - Register usage conventions

- [ ] **1.2** Create `abi-userland` spec
  - ELF64 binary format requirements
  - SysV AMD64 calling convention
  - SYSCALL/SYSRET mechanism and register clobbering rules
  - Syscall numbering table (initial 0-999 reserved)
  - Errno convention (negative return values)

- [ ] **1.3** Create `memory-model` spec
  - 4-level paging structure (PML4, PDPT, PD, PT)
  - Virtual address layout: userland 0x0000..., kernel 0xFFFF...
  - Higher-half kernel mapping (0xFFFF800000000000 direct map, 0xFFFFFFFFC0000000 kernel image)
  - Per-process address spaces (CR3 switching)
  - Physical memory manager interface (`pmm_alloc_page`, `pmm_free_page`)
  - Virtual memory manager interface (VMA tracking, page fault handling)

- [ ] **1.4** Create `process-model` spec
  - Process structure (`struct process` layout)
  - Ring0/Ring3 separation (kernel/userland privilege levels)
  - Context switch contract (register save/restore, CR3 switch)
  - Scheduler interface (round-robin initial algorithm)
  - Kernel stack per-process (used during syscalls/IRQs)

- [ ] **1.5** Create `driver-api` spec
  - Current state: drivers in kernel (Phase 1)
  - Driver API contract (`driver_map_mmio`, `driver_request_irq`, `driver_dma_alloc`)
  - Future migration path: userland drivers (Phase 2)
  - Device file model (VFS `/dev/*` nodes)
  - IRQ forwarding mechanism (kernel → userland driver)

- [ ] **1.6** Create `build-system` spec
  - Linker script contract (`kernel.ld` for higher-half kernel)
  - Section layout (`.text`, `.rodata`, `.data`, `.bss` alignment)
  - Symbol table conventions (exported symbols: `kernel_start`, `text_start`, etc.)
  - Build flags (GCC/Clang: `-mcmodel=kernel`, `-mno-red-zone`, `-mno-sse`)
  - Debug symbols (DWARF, stack trace support)

### 2. Migration Path Documentation

- [ ] **2.1** Document Phase B (32-bit → 64-bit transition)
  - Stage2 long mode entry sequence
  - Initial 4-level page table setup (identity map + higher-half)
  - 64-bit GDT configuration
  - Driver porting checklist (VGA, keyboard, mouse)

- [ ] **2.2** Document Phase C (Process model bootstrap)
  - Process structure initialization
  - Scheduler tick setup (IRQ0 timer)
  - Initial idle process (PID 0)
  - First fork/exec implementation outline

- [ ] **2.3** Document Phase D (ELF loader)
  - ELF64 header parsing
  - PT_LOAD segment mapping to userland address space
  - User stack setup
  - RIP/RSP initialization at ELF entry point

- [ ] **2.4** Document Phase E (Syscall infrastructure)
  - MSR configuration (IA32_STAR, IA32_LSTAR, IA32_FMASK)
  - Syscall dispatcher (RAX → handler table)
  - Core syscall implementations: write, read, open, close, mmap, munmap, exit

- [ ] **2.5** Document Phase F (VFS & device files)
  - VFS layer design (mount points, inodes, file operations)
  - Device driver registration with VFS
  - `/dev/kbd`, `/dev/mouse`, `/dev/tty` device nodes
  - Userland program access via `open()`/`read()`/`write()`

- [ ] **2.6** Document Phase G (Userland drivers — future)
  - Kernel syscall extensions for driver API
  - Shared memory ring buffer for IRQ forwarding
  - Driver daemon lifecycle (register, handle IRQs, unregister)
  - Example: keyboard driver in userland

### 3. Validation & Cross-References

- [ ] **3.1** Update `project.md` to reference new arch contract
  - Add section: "Target Architecture: x86_64 Long Mode"
  - Link to `arch-x86_64`, `abi-userland`, `memory-model` specs

- [ ] **3.2** Mark existing specs as "Phase A (Bootstrap)"
  - Update `bootloader`, `kernel-core`, `video-driver`, `keyboard-driver`, `mouse-driver` specs
  - Add "Phase: A (32-bit bootstrap)" metadata
  - Note: "Will be superseded by 64-bit implementations in Phase B+"

- [ ] **3.3** Validate spec consistency
  - Ensure syscall numbers don't conflict with reserved ranges
  - Verify virtual address ranges don't overlap (userland vs kernel)
  - Check that linker script sections align with memory model

- [ ] **3.4** Create compatibility matrix
  - Document which phases preserve backward compatibility
  - Note: 32-bit → 64-bit is **breaking change** (no binary compatibility)
  - Userland ABI (ELF64, syscalls) is stable only after Phase E complete

---

## Non-Tasks (Implementation Work)

The following are **NOT** part of this proposal (they belong in future proposals):

- ❌ Implement long mode entry code
- ❌ Port drivers to 64-bit
- ❌ Write scheduler or context switch assembly
- ❌ Implement ELF loader
- ❌ Write syscall handlers
- ❌ Build VFS layer

This proposal **only** documents the architecture. Implementation is tracked separately.

---

## Acceptance Criteria

This proposal is complete when:
1. All 6 core architecture specs (`arch-x86_64`, `abi-userland`, `memory-model`, `process-model`, `driver-api`, `build-system`) are created
2. Migration path (Phases B-G) is documented with clear requirements
3. `project.md` references the new architecture contract
4. All specs validate with `openspec validate --specs`
5. No implementation code is added (this is documentation-only)
