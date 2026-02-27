# Architecture Contract — Design Decisions

## 1. Target Architecture: x86_64 Long Mode

### 1.1 CPU Requirements
- **Minimum**: x86_64 with long mode support (Intel 64 / AMD64)
- **Required features**: SYSCALL/SYSRET, NX bit (IA32_EFER.NXE), 4-level paging (PML4)
- **Detection**: Boot code must verify `CPUID.80000001h:EDX[29]` (long mode available)

### 1.2 Boot Protocol
- **Current**: Two-stage BIOS bootloader (MBR → stage2 → kernel at 0x10000)
- **Target**: Multiboot2-compliant kernel binary, loadable by GRUB2 in 64-bit mode
- **Transition**: Stage2 enters long mode, maps kernel to higher half, jumps to 64-bit entry

### 1.3 Registers & State
- **Integer**: Use full 64-bit registers (RAX, RBX, RCX, RDX, RSI, RDI, RBP, RSP, R8-R15)
- **Floating-point**: SSE2 for userland (no x87 FPU state saved on context switch)
- **Segments**: Flat model (CS/DS/SS selectors only, no segmentation)

---

## 2. Userland Executable Format: ELF64

### 2.1 Binary Format
- **Standard**: ELF64 (Executable and Linkable Format, 64-bit variant)
- **Entry point**: ELF header `e_entry` field (virtual address)
- **Program headers**: Load PT_LOAD segments into process address space
- **Interpreter**: Initial versions: no dynamic linking (static executables only). Future: support `PT_INTERP` for dynamic loader.

### 2.2 Calling Convention: SysV AMD64
- **Function arguments**: RDI, RSI, RDX, RCX, R8, R9 (integers/pointers), XMM0-XMM7 (floats)
- **Return value**: RAX (integer/pointer), XMM0 (float)
- **Caller-saved**: RAX, RCX, RDX, RSI, RDI, R8-R11
- **Callee-saved**: RBX, RBP, R12-R15
- **Stack alignment**: 16-byte aligned before `call` (RSP % 16 == 8 after call, due to return address push)
- **Red zone**: 128 bytes below RSP (userland only, not kernel)

### 2.3 System Call ABI
- **Mechanism**: `SYSCALL` instruction (ring3 → ring0), `SYSRET` (ring0 → ring3)
- **Syscall number**: RAX
- **Arguments**: RDI, RSI, RDX, R10, R8, R9 (up to 6 args; R10 replaces RCX because SYSCALL clobbers RCX with return RIP)
- **Return**: RAX (value or -errno)
- **Clobbered**: RCX (return RIP), R11 (saved RFLAGS), all other registers preserved
- **Errno convention**: Negative return values are `-errno` (Linux-style: -EINVAL = -22, etc.)

**Syscall numbering** (initial set):
```
0   = sys_exit(int status)
1   = sys_write(int fd, const char* buf, size_t count)
2   = sys_read(int fd, char* buf, size_t count)
3   = sys_open(const char* path, int flags, int mode)
4   = sys_close(int fd)
5   = sys_mmap(void* addr, size_t len, int prot, int flags, int fd, off_t offset)
6   = sys_munmap(void* addr, size_t len)
...
(Expand as needed, reserve 0-999 for core syscalls)
```

---

## 3. Memory Model: 4-Level Paging

### 3.1 Virtual Address Layout (per-process)

**Userland** (0x0000000000000000 - 0x00007FFFFFFFFFFF):
```
0x0000000000000000 - 0x0000000000000FFF   NULL guard page (unmapped)
0x0000000000001000 - 0x0000000000400000   ELF .text (code segment)
0x0000000000400000 - 0x0000000000600000   ELF .data/.bss (data segment)
0x0000000000600000 - 0x00007FFFFFFFFFFF   Heap (brk/mmap space)
0x00007FFFFFFFE000 - 0x00007FFFFFFFFFFF   User stack (grows down from top)
```

**Kernel** (0xFFFF800000000000 - 0xFFFFFFFFFFFFFFFF):
```
0xFFFF800000000000 - 0xFFFF8000FFFFFFFF   Direct physical map (512 GB, identity offset)
                                           Virtual = Physical + 0xFFFF800000000000
0xFFFF900000000000 - 0xFFFF9FFFFFFFFFFF   Kernel heap (vmalloc, per-CPU data)
0xFFFFFFFFC0000000 - 0xFFFFFFFFFFFFFFFF   Kernel image (.text, .data, .bss)
```

**Page table hierarchy**:
- **PML4** (Page Map Level 4): 512 entries, each covers 512 GB
- **PDPT** (Page Directory Pointer Table): 512 entries, each covers 1 GB
- **PD** (Page Directory): 512 entries, each covers 2 MB
- **PT** (Page Table): 512 entries, each covers 4 KB

**Per-process state**:
- Each process has its own PML4 (CR3 points to physical address of PML4)
- Kernel mappings (0xFFFF800000000000+) are identical in all processes (shared kernel space)
- Userland mappings (0x0000000000000000+) are unique per process
- Context switch: `mov cr3, <new_pml4_phys>`

### 3.2 Physical Memory Manager
- **Bitmap allocator**: Track free/used 4KB pages in a bitmap (1 bit per page)
- **Boot memory**: Kernel binary + initial page tables allocated by bootloader
- **Runtime allocation**: `pmm_alloc_page()` returns physical address of free 4KB page, `pmm_free_page(phys_addr)`

### 3.3 Virtual Memory Manager
- **Per-process `struct vm_space`**: Contains PML4 physical address, list of memory regions (VMA: virtual memory area)
- **VMA**: Each userland region (code, data, heap, stack, mmap) tracked as `struct vma { void* start; size_t len; uint32_t prot; ... }`
- **Page fault handler**: ISR 14 (page fault) checks faulting address against VMAs, allocates physical page on-demand if valid

---

## 4. Process Model: Ring0/Ring3 Separation

### 4.1 Process Structure
```c
struct process {
    uint64_t pid;                   // Process ID
    uint64_t* pml4_phys;            // CR3 value (physical address of PML4)
    struct vm_space vm;             // Virtual memory areas
    struct registers context;       // Saved register state (RIP, RSP, etc.)
    enum { RUNNING, READY, BLOCKED, ZOMBIE } state;
    struct process* next;           // Scheduler queue link
};
```

### 4.2 Context Switch
**On timer IRQ or syscall yield**:
1. Save current process registers to `current->context` (RAX, RBX, ..., RIP, RSP, RFLAGS)
2. Select next process from scheduler queue: `next = schedule()`
3. Load next process PML4: `mov cr3, next->pml4_phys`
4. Restore next process registers from `next->context`
5. `SYSRET` or `IRETQ` to return to userland

**Kernel stack**: Each process has a dedicated kernel stack (used during syscalls/IRQs). Stored in process structure: `void* kernel_stack_top`.

### 4.3 Scheduler (Initial: Round-Robin)
- **Algorithm**: Simple round-robin (FIFO queue of READY processes)
- **Timer**: IRQ0 (PIT or APIC timer) triggers scheduler every 10ms
- **Preemption**: Kernel is preemptible (timer IRQ can occur during syscall; scheduler runs)
- **Priority**: Future extension (for now, all processes equal priority)

---

## 5. Driver Architecture: Clear API Boundaries

### 5.1 Current State ("Phase 1")
- **All drivers in kernel**: VGA, keyboard, mouse, disk drivers compiled into kernel binary
- **Direct hardware access**: `outb()`, `inb()`, MMIO via kernel virtual addresses
- **IRQ handlers**: Drivers register ISRs directly into IDT

### 5.2 Target State ("Phase 2" — Userland Drivers)
- **Driver API isolation**: Even though drivers are in kernel initially, they use a **driver API** (not raw hardware access)
- **Driver API contract**:
  ```c
  // Kernel provides:
  int driver_map_mmio(uint64_t phys_addr, size_t len, void** virt_out);
  int driver_request_irq(int irq_num, void (*handler)(void* ctx), void* ctx);
  int driver_dma_alloc(size_t len, uint64_t* phys_out);

  // Driver provides:
  int driver_init(struct driver_info* info);
  int driver_ioctl(int cmd, void* arg);
  ```
- **Future migration**: When drivers move to userland, they communicate with kernel via syscalls (`sys_ioctl`, shared memory for DMA buffers). The **driver API** maps to syscalls instead of kernel functions.

### 5.3 Device Files (Future)
- **VFS layer**: `/dev/vga0`, `/dev/kbd`, `/dev/mouse` as device nodes
- **Userland programs**: Open `/dev/mouse`, read packets via `read()` syscall
- **Driver daemons**: Userland drivers register with kernel via `sys_register_driver()`, handle IRQs via kernel upcalls or shared memory

---

## 6. Build System Contract

### 6.1 Linker Script (kernel.ld)
**Sections** (64-bit kernel):
```ld
ENTRY(kernel_entry)
OUTPUT_FORMAT(elf64-x86-64)

SECTIONS {
    . = 0xFFFFFFFFC0000000;  /* Kernel higher-half base */

    .text : ALIGN(4K) {
        *(.text.boot)        /* Early boot code (identity-mapped stub) */
        *(.text)
    }

    .rodata : ALIGN(4K) {
        *(.rodata*)
    }

    .data : ALIGN(4K) {
        *(.data)
    }

    .bss : ALIGN(4K) {
        *(.bss)
        *(COMMON)
    }
}
```

**Symbol export**:
- `kernel_start`, `kernel_end`: Full kernel image bounds (for initial page table setup)
- `text_start`, `text_end`, `rodata_start`, etc.: Per-section bounds
- All symbols in single symbol table (no hidden symbols for now)

### 6.2 Debug & Tracing
- **Debug symbols**: Include DWARF debug info in kernel binary (`-g` flag)
- **Stack traces**: Kernel panic handler walks stack frames (`RBP` chain), looks up symbols
- **Trace hooks** (future): `TRACE_SYSCALL(num, args...)` macros expand to logging calls (optional, disabled by default)

### 6.3 Build Flags (GCC/Clang for 64-bit kernel)
```makefile
CFLAGS := -ffreestanding -nostdlib -mcmodel=kernel \
          -mno-red-zone -mno-mmx -mno-sse -mno-sse2 \
          -fno-pie -fno-stack-protector \
          -Wall -Wextra -O2 -g
```
- **`-mcmodel=kernel`**: Code/data in high 2GB (0xFFFFFFFF80000000+)
- **`-mno-red-zone`**: Disable 128-byte red zone below RSP (kernel uses interrupts, can't rely on red zone)
- **`-mno-sse*`**: No floating-point in kernel (avoid FPU context save/restore)

---

## 7. Migration Path (32-bit → 64-bit)

### Phase A (Current): 32-bit Bootstrap
- x86 protected mode, flat binary, no paging
- VGA text mode, PS/2 keyboard/mouse, simple shell

### Phase B: Enable Long Mode
- Stage2 sets up 4-level page tables (identity map + higher-half kernel)
- Enters long mode, jumps to 64-bit kernel entry
- GDT updated for 64-bit code/data segments
- Existing drivers (VGA, keyboard, mouse) ported to 64-bit

### Phase C: Process Model
- Add process structure, scheduler, context switch
- Implement `sys_fork()`, `sys_exec()`, `sys_exit()`
- Simple init process (PID 1) spawns shell

### Phase D: ELF Loader
- Parse ELF64 headers, load PT_LOAD segments into process address space
- Map user stack, set up initial registers (RIP = ELF entry, RSP = stack top)
- Execute first userland program (`/bin/init`)

### Phase E: Syscalls
- Configure MSRs for SYSCALL/SYSRET (IA32_STAR, IA32_LSTAR, IA32_FMASK)
- Implement syscall dispatcher (switch on RAX, call handler)
- Add core syscalls: write, read, open, close, mmap

### Phase F: VFS & Device Files
- Virtual filesystem layer: mount root filesystem (tmpfs or initrd)
- Device driver registration: `/dev/kbd`, `/dev/mouse`, `/dev/tty`
- Userland programs use `open("/dev/kbd")` to access devices

### Phase G: Userland Drivers (Future)
- Move keyboard/mouse drivers to userland daemons
- Kernel provides driver API via syscalls (`sys_map_mmio`, `sys_request_irq`)
- IRQ handling: kernel forwards IRQ to userland driver via shared memory ring buffer

---

## 8. Compatibility & Versioning

### 8.1 ABI Stability
- **Unstable (0.x)**: Until first userland programs exist, syscall numbers/ABI can change freely
- **Stable (1.0+)**: Once declared stable, syscall ABI is **frozen** (can only add new syscalls at end of table, not change existing ones)

### 8.2 Kernel API (Internal)
- **Driver API**: Kernel-internal driver interface can evolve as long as all in-tree drivers are updated
- **No external modules**: Initially no loadable kernel modules (all drivers compiled in), so kernel API changes don't break external code

---

## 9. Open Questions & Future Work

1. **SMP (multicore)**: How to handle per-CPU data, spinlocks, TLB shootdown?
2. **Interrupts on x64**: Use APIC (local APIC + I/O APIC) instead of legacy PIC?
3. **Time source**: HPET, TSC, or PIT for scheduling timer?
4. **Filesystem**: Initrd (RAM disk) or real disk driver + ext2/FAT32?
5. **Network stack**: When/how to add TCP/IP?

These are deferred to future proposals. This contract focuses on the **invariants** (ABI, memory layout, driver boundaries) that must remain stable.
