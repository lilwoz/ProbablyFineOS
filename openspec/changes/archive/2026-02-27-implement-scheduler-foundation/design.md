# Scheduler Foundation — Design Decisions

## 1. Exception Handling

### 1.1 IDT Setup (32-bit Protected Mode)

Current IDT has 256 entries. Install ISRs for:
- **Exceptions 0-31**: CPU-defined exceptions (divide-by-zero, debug, page fault, GPF, etc.)
- **IRQ 0 (timer)**: System timer tick (PIT channel 0)
- **IRQ 1 (keyboard)**: Already installed, keep as-is
- **IRQ 12 (mouse)**: Already installed, keep as-is

**Exception stub pattern** (assembly):
```asm
; Exceptions with error code pushed by CPU: 8, 10, 11, 12, 13, 14, 17
exception_with_error:
    ; Error code already on stack
    push eax                  ; Save EAX (will use for exception number)
    mov eax, <exception_num>
    jmp exception_common

; Exceptions without error code: all others
exception_no_error:
    push 0                    ; Dummy error code
    push eax
    mov eax, <exception_num>
    jmp exception_common

exception_common:
    pushad                    ; Save all GP registers
    push_segs                 ; Save segment registers

    push eax                  ; Exception number
    push dword [esp + 44]     ; Error code (after pushad + push_segs)
    push dword [esp + 48]     ; EIP (after pushad + push_segs + error + exc_num)
    call exception_handler    ; C function
    add esp, 12

    ; Exception handler never returns (kernel panic)
    freeze
```

### 1.2 Exception Handler (C)

```c
void exception_handler(uint32_t eip, uint32_t error_code, uint32_t exc_num) {
    kprintf("\n*** KERNEL PANIC: Exception %u ***\n", exc_num);
    kprintf("EIP: 0x%08x  Error: 0x%08x\n", eip, error_code);

    // Read CR2 for page faults (exception 14)
    if (exc_num == 14) {
        uint32_t cr2;
        asm volatile("mov %0, cr2" : "=r"(cr2));
        kprintf("CR2 (faulting address): 0x%08x\n", cr2);
    }

    // Print register dump (from stack frame)
    kprintf("Registers:\n");
    kprintf("  EAX=... EBX=... ECX=... EDX=...\n");  // From pushad frame
    kprintf("  ESI=... EDI=... EBP=... ESP=...\n");

    kprintf("Halting.\n");
    freeze();
}
```

**Exception names** (for printing):
```c
const char* exception_names[] = {
    "Divide by Zero", "Debug", "NMI", "Breakpoint",
    "Overflow", "Bound Range Exceeded", "Invalid Opcode", "Device Not Available",
    "Double Fault", "Coprocessor Segment Overrun", "Invalid TSS", "Segment Not Present",
    "Stack-Segment Fault", "General Protection Fault", "Page Fault", "(reserved)",
    "x87 FPU Error", "Alignment Check", "Machine Check", "SIMD FP Exception",
    // ... (20-31 reserved)
};
```

---

## 2. System Timer

### 2.1 PIT (Programmable Interval Timer)

**Configuration**:
- Channel 0: IRQ0, periodic mode (mode 3: square wave)
- Frequency: 1193182 Hz (PIT base frequency)
- Divisor: 11932 → 100 Hz (10ms quantum)

**Setup code**:
```c
#define PIT_FREQUENCY 1193182
#define TIMER_HZ 100
#define PIT_CHANNEL0 0x40
#define PIT_COMMAND  0x43

void pit_init(void) {
    uint16_t divisor = PIT_FREQUENCY / TIMER_HZ;

    // Command byte: channel 0, lo/hi byte, mode 3, binary
    outb(PIT_COMMAND, 0x36);  // 0b00110110

    // Send divisor (lo byte, then hi byte)
    outb(PIT_CHANNEL0, divisor & 0xFF);
    outb(PIT_CHANNEL0, (divisor >> 8) & 0xFF);
}
```

**IRQ0 handler**:
```asm
global irq0_timer_handler
irq0_timer_handler:
    pushad
    push_segs
    set_kernel_segs

    call timer_tick           ; C function

    eoi_master                ; Send EOI to PIC
    pop_segs
    popad
    iret
```

### 2.2 LAPIC Timer (Future)

Deferred to SMP proposal. LAPIC provides per-CPU timer with nanosecond precision. For single-CPU, PIT is sufficient.

---

## 3. Thread Structure

### 3.1 Thread State

```c
enum thread_state {
    THREAD_READY,             // In ready queue, can be scheduled
    THREAD_RUNNING,           // Currently executing
    THREAD_BLOCKED,           // Waiting for I/O or event
    THREAD_ZOMBIE,            // Exited, waiting to be reaped
};

struct thread {
    uint32_t tid;             // Thread ID (unique)
    enum thread_state state;

    // Kernel stack (allocated from heap)
    void* kernel_stack_base;  // Bottom of stack (for freeing)
    void* kernel_stack_top;   // Top of stack (initial ESP)

    // User stack (placeholder for future userland)
    void* user_stack_top;     // Will be used for ring3 threads

    // Saved context (registers)
    struct {
        uint32_t eax, ebx, ecx, edx;
        uint32_t esi, edi, ebp, esp;
        uint32_t eip;
        uint32_t eflags;
        uint16_t cs, ds, ss, es, fs, gs;
    } regs;

    // FPU/SSE state (512 bytes for FXSAVE)
    uint8_t fpu_state[512] __attribute__((aligned(16)));

    // Scheduling
    int quantum;              // Remaining time slice (ticks)
    struct thread* next;      // Linked list pointer
};
```

**Thread stack layout** (kernel stack grows down):
```
Top of stack (ESP at context switch)
+---------------------------+
| Saved EIP (return addr)   |  <- Entry point for new threads
| Saved EBP                 |
| Saved EBX, ESI, EDI       |  <- Callee-saved registers
| ... (pushad frame)        |
| FPU state (if needed)     |
+---------------------------+
Bottom of stack (4 pages = 16 KB)
```

### 3.2 Context Switch

**Save context** (in `timer_tick` or `thread_yield`):
```c
void context_switch(struct thread* old, struct thread* new) {
    // Save old thread registers
    asm volatile(
        "mov [%0], eax \n"
        "mov [%1], ebx \n"
        // ... (save all registers)
        "mov [%2], esp \n"
        : : "m"(old->regs.eax), "m"(old->regs.ebx), "m"(old->regs.esp)
    );

    // Save FPU/SSE state
    asm volatile("fxsave [%0]" : : "r"(old->fpu_state));

    // Switch to new thread
    current_thread = new;

    // Restore new thread FPU state
    asm volatile("fxrstor [%0]" : : "r"(new->fpu_state));

    // Restore new thread registers
    asm volatile(
        "mov eax, [%0] \n"
        "mov ebx, [%1] \n"
        // ... (restore all registers)
        "mov esp, [%2] \n"
        "jmp [%3] \n"        // Jump to saved EIP
        : : "m"(new->regs.eax), "m"(new->regs.ebx),
            "m"(new->regs.esp), "m"(new->regs.eip)
    );
}
```

**Initial thread setup**:
When creating a new thread, manually set up stack frame as if it had been context-switched:
```c
struct thread* thread_create(void (*entry)(void*), void* arg) {
    struct thread* t = kmalloc(sizeof(struct thread));
    t->tid = next_tid++;
    t->state = THREAD_READY;

    // Allocate kernel stack (4 pages = 16 KB)
    t->kernel_stack_base = kmalloc(16384);
    t->kernel_stack_top = t->kernel_stack_base + 16384;

    // Set up initial stack frame (as if context_switch was called)
    uint32_t* stack = (uint32_t*)t->kernel_stack_top;
    *(--stack) = (uint32_t)arg;           // Argument (on stack for entry function)
    *(--stack) = (uint32_t)thread_exit;   // Return address (if entry returns)
    *(--stack) = (uint32_t)entry;         // Entry point (EIP)
    *(--stack) = 0;                       // EBP
    // ... (save other callee-saved registers as 0)

    t->regs.esp = (uint32_t)stack;
    t->regs.eip = (uint32_t)entry;

    // Initialize FPU state (empty)
    asm volatile("fxsave [%0]" : : "r"(t->fpu_state));

    return t;
}
```

---

## 4. Round-Robin Scheduler

### 4.1 Scheduler Data Structures

```c
struct scheduler {
    struct thread* ready_queue;    // Circular linked list of READY threads
    struct thread* current;        // Currently RUNNING thread
    int quantum_ticks;             // Ticks per quantum (default: 100 ticks = 1 sec at 100 Hz)
};

static struct scheduler sched;
```

### 4.2 Scheduler Operations

**Add thread to ready queue**:
```c
void scheduler_add(struct thread* t) {
    t->state = THREAD_READY;
    t->quantum = sched.quantum_ticks;

    if (sched.ready_queue == NULL) {
        sched.ready_queue = t;
        t->next = t;  // Point to itself (circular)
    } else {
        // Insert at end of circular list
        t->next = sched.ready_queue->next;
        sched.ready_queue->next = t;
        sched.ready_queue = t;
    }
}
```

**Select next thread** (round-robin):
```c
struct thread* schedule(void) {
    if (sched.ready_queue == NULL) {
        return idle_thread;  // No ready threads, run idle
    }

    // Pick next thread in circular queue
    struct thread* next = sched.ready_queue->next;
    next->state = THREAD_RUNNING;
    next->quantum = sched.quantum_ticks;

    // Advance ready queue pointer
    sched.ready_queue = next;

    return next;
}
```

**Timer tick**:
```c
void timer_tick(void) {
    struct thread* current = sched.current;

    if (current == idle_thread) {
        // Idle thread, always reschedule
        struct thread* next = schedule();
        if (next != current) {
            context_switch(current, next);
        }
        return;
    }

    // Decrement quantum
    current->quantum--;

    if (current->quantum <= 0) {
        // Time slice expired, reschedule
        if (current->state == THREAD_RUNNING) {
            current->state = THREAD_READY;
            scheduler_add(current);
        }

        struct thread* next = schedule();
        context_switch(current, next);
    }
}
```

### 4.3 Idle Thread

Special thread (TID 0) that runs when no other threads are ready:
```c
void idle_thread_entry(void* arg) {
    while (1) {
        asm volatile("hlt");  // Wait for next interrupt
    }
}

void scheduler_init(void) {
    // Create idle thread
    idle_thread = thread_create(idle_thread_entry, NULL);
    idle_thread->tid = 0;
    idle_thread->state = THREAD_RUNNING;

    sched.current = idle_thread;
    sched.ready_queue = NULL;
    sched.quantum_ticks = 100;  // 1 second quantum at 100 Hz
}
```

---

## 5. Thread API

### 5.1 Thread Creation

```c
struct thread* thread_create(void (*entry)(void*), void* arg);
// Allocates thread structure, sets up stack, adds to ready queue
// Returns thread pointer (caller can save TID for wait/join)
```

### 5.2 Thread Yield

```c
void thread_yield(void) {
    // Voluntarily give up CPU
    struct thread* current = sched.current;
    if (current->state == THREAD_RUNNING) {
        current->state = THREAD_READY;
        scheduler_add(current);
    }

    struct thread* next = schedule();
    context_switch(current, next);
}
```

### 5.3 Thread Exit

```c
void thread_exit(void) {
    struct thread* current = sched.current;
    current->state = THREAD_ZOMBIE;

    // TODO: wake up threads waiting for this thread (join)

    struct thread* next = schedule();
    context_switch(current, next);  // Never returns
}
```

---

## 6. Testing Strategy

### 6.1 Unit Tests (in kernel)

Create test threads to verify scheduler:
```c
void test_thread_1(void* arg) {
    for (int i = 0; i < 5; i++) {
        kprintf("Thread 1: iteration %d\n", i);
        thread_yield();
    }
    thread_exit();
}

void test_thread_2(void* arg) {
    for (int i = 0; i < 5; i++) {
        kprintf("Thread 2: iteration %d\n", i);
        thread_yield();
    }
    thread_exit();
}

void test_scheduler(void) {
    thread_create(test_thread_1, NULL);
    thread_create(test_thread_2, NULL);

    // Threads should interleave output:
    // Thread 1: iteration 0
    // Thread 2: iteration 0
    // Thread 1: iteration 1
    // Thread 2: iteration 1
    // ...
}
```

### 6.2 Exception Tests

Trigger exceptions to verify handlers work:
```c
void test_divide_by_zero(void) {
    int x = 10;
    int y = 0;
    int z = x / y;  // Should trigger exception 0, print register dump, halt
}

void test_page_fault(void) {
    uint32_t* p = (uint32_t*)0x12345678;
    *p = 0xDEADBEEF;  // Should trigger page fault, print CR2=0x12345678, halt
}
```

---

## 7. Migration Path

Current kernel → scheduler-enabled kernel:

1. **Phase A (current)**: Single-threaded kernel, shell runs in main loop
2. **Phase B (this proposal)**: Scheduler infrastructure added, but shell still runs as main thread
3. **Phase C (future)**: Shell becomes a thread, kernel main becomes idle loop
4. **Phase D (future)**: Add userland processes (fork/exec), threads become kernel-only

---

## 8. Open Questions

1. **Thread priority**: Should we add priority levels (real-time, normal, background)? Deferred: round-robin is sufficient for initial implementation.

2. **Thread local storage (TLS)**: Do threads need TLS? Deferred: not needed for kernel threads. Userland threads will need TLS (FS/GS segments).

3. **SMP (multi-core)**: How to handle per-CPU scheduler? Deferred: SMP is a separate large proposal. This is single-CPU only.

4. **Stack guard pages**: Should we unmap a page below each stack to catch overflow? Recommended: yes, but requires paging to be enabled. Deferred until memory management is implemented.
