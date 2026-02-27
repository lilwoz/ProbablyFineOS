# Scheduler Foundation — Implementation Tasks

## Section 1: Exception Handling

### Task 1.1: Create exception handler infrastructure
- [ ] Create `kernel/exceptions.asm` with exception stub macros
- [ ] Generate ISRs for exceptions 0-31 (with/without error code)
- [ ] Implement `exception_common` trampoline (save registers, call C handler)
- [ ] Install exception ISRs into IDT (call `idt_set_gate` for each)

### Task 1.2: Implement exception handler (C)
- [ ] Create `kernel/panic.c` with `exception_handler(eip, error_code, exc_num)`
- [ ] Print exception name, EIP, error code
- [ ] Read CR2 for page fault (exception 14), print faulting address
- [ ] Print register dump from stack frame (EAX-EDI, segment registers)
- [ ] Freeze system after printing (call existing `freeze` macro)

### Task 1.3: Test exception handlers
- [ ] Add test function `test_divide_by_zero()` in shell (command "crash div")
- [ ] Add test function `test_page_fault()` in shell (command "crash pf")
- [ ] Verify exception handler prints correct info and halts

---

## Section 2: System Timer (PIT)

### Task 2.1: Implement PIT driver
- [ ] Create `drivers/timer/pit.c` with `pit_init(int hz)`
- [ ] Configure PIT channel 0 for 100 Hz (10ms quantum)
- [ ] Send command byte 0x36 (channel 0, mode 3, lo/hi byte)
- [ ] Write divisor to port 0x40 (lo byte, hi byte)

### Task 2.2: Install timer IRQ handler
- [ ] Create `kernel/timer.asm` with `irq0_timer_handler`
- [ ] Handler: pushad, push_segs, set_kernel_segs, call `timer_tick`, eoi_master, pop_segs, popad, iret
- [ ] Install handler into IDT vector 0x20 (IRQ0)
- [ ] Unmask IRQ0 on PIC (call `pic_unmask_irq(0)`)

### Task 2.3: Implement timer tick (C)
- [ ] Create `kernel/scheduler.c` with `timer_tick()` function
- [ ] Increment global tick counter (`volatile uint64_t ticks`)
- [ ] Print "tick" message every 100 ticks (for initial testing)
- [ ] Later: call `schedule()` to switch threads (Section 4)

---

## Section 3: Thread Structure & Context Switching

### Task 3.1: Define thread structure
- [ ] Create `include/thread.h` with `struct thread` definition
- [ ] Fields: tid, state (READY/RUNNING/BLOCKED/ZOMBIE), kernel_stack_base, kernel_stack_top
- [ ] Fields: saved registers (eax-edi, eip, esp, eflags, cs/ds/ss/es/fs/gs)
- [ ] Field: fpu_state (uint8_t[512] aligned to 16 bytes)
- [ ] Field: quantum (remaining ticks), next (linked list pointer)

### Task 3.2: Implement thread creation
- [ ] Create `kernel/thread.c` with `thread_create(entry, arg)`
- [ ] Allocate thread structure from heap (use existing memory allocator or simple bump allocator)
- [ ] Allocate kernel stack (4 pages = 16 KB)
- [ ] Set up initial stack frame (push arg, return addr, entry point, saved registers)
- [ ] Initialize FPU state with `fxsave` (store initial clean FPU state)
- [ ] Return thread pointer

### Task 3.3: Implement context switching
- [ ] Create `kernel/context.asm` with `context_switch(old, new)`
- [ ] Save old thread: pushad (or manually save eax-edi), save esp into old->regs.esp
- [ ] Save old thread FPU state: `fxsave [old->fpu_state]`
- [ ] Update global `current_thread` pointer to `new`
- [ ] Restore new thread FPU state: `fxrstor [new->fpu_state]`
- [ ] Restore new thread: load esp from new->regs.esp, popad (or manually restore eax-edi)
- [ ] Jump to new thread EIP: `jmp [new->regs.eip]` or `ret` (if EIP is on stack)

### Task 3.4: Test context switching (basic)
- [ ] Create two test threads: `test_thread_a` and `test_thread_b`
- [ ] Each prints message, calls `thread_yield()`, repeats 5 times, exits
- [ ] Manually call `context_switch(a, b)` to verify switching works
- [ ] Verify interleaved output: "Thread A: 0", "Thread B: 0", "Thread A: 1", etc.

---

## Section 4: Round-Robin Scheduler

### Task 4.1: Implement scheduler data structures
- [ ] Create `kernel/scheduler.c` with `struct scheduler` (ready_queue, current, quantum_ticks)
- [ ] Global scheduler instance: `static struct scheduler sched`
- [ ] Initialize scheduler in `scheduler_init()`: set current = NULL, ready_queue = NULL, quantum_ticks = 100

### Task 4.2: Implement scheduler operations
- [ ] `scheduler_add(thread)`: add thread to end of circular ready queue
- [ ] `schedule()`: select next thread from ready queue (round-robin), mark as RUNNING
- [ ] If ready queue empty, return idle thread (TID 0)
- [ ] Update `timer_tick()` to decrement current thread quantum, call `schedule()` if quantum expired

### Task 4.3: Create idle thread
- [ ] Implement `idle_thread_entry()`: infinite loop with `hlt` instruction
- [ ] Create idle thread in `scheduler_init()` with TID 0, state RUNNING
- [ ] Set `sched.current = idle_thread`

### Task 4.4: Integrate scheduler with timer
- [ ] Update `timer_tick()` to call scheduler logic:
  - Decrement current thread quantum
  - If quantum <= 0, move current to ready queue, call `schedule()`, call `context_switch()`
- [ ] Test: create 2-3 threads, verify they get scheduled in round-robin order

---

## Section 5: Thread API

### Task 5.1: Implement thread_yield
- [ ] Create `thread_yield()` in `kernel/thread.c`
- [ ] Move current thread to ready queue (if RUNNING), call `schedule()`, call `context_switch()`
- [ ] Test: create thread that yields voluntarily, verify context switch happens

### Task 5.2: Implement thread_exit
- [ ] Create `thread_exit()` in `kernel/thread.c`
- [ ] Mark current thread as ZOMBIE
- [ ] Call `schedule()` to pick next thread, call `context_switch()` (never returns)
- [ ] TODO (future): wake up threads waiting for this thread (join)

### Task 5.3: Add thread management to shell
- [ ] Shell command `threads`: list all threads (TID, state, quantum)
- [ ] Shell command `spawn <name>`: create test thread (predefined test functions)
- [ ] Test threads: `test_loop` (prints message in loop), `test_fpu` (uses floating-point)

---

## Section 6: Testing & Validation

### Task 6.1: Test exception handling
- [ ] Shell command `crash div`: trigger divide-by-zero exception, verify handler prints dump
- [ ] Shell command `crash pf`: trigger page fault, verify handler prints CR2
- [ ] Shell command `crash gpf`: trigger general protection fault (e.g., invalid segment)

### Task 6.2: Test scheduler with multiple threads
- [ ] Create 3 test threads that print messages and yield
- [ ] Verify interleaved output (round-robin order)
- [ ] Verify timer preemption: create thread that doesn't yield (infinite loop with counter), verify it gets preempted after quantum expires

### Task 6.3: Test FPU/SSE state isolation
- [ ] Create two threads: one sets FPU registers to known values, one computes sin/cos
- [ ] Verify each thread sees correct FPU state after context switch (no corruption)
- [ ] Test: thread A sets ST(0)=1.23, yields, thread B sets ST(0)=4.56, yields, thread A verifies ST(0)=1.23

### Task 6.4: Stress test (many threads)
- [ ] Create 10-20 threads, each prints message and yields
- [ ] Verify no crashes, no deadlocks
- [ ] Monitor tick counter, verify scheduler overhead is acceptable

---

## Section 7: Documentation

### Task 7.1: Update specs
- [ ] Update `process-model` spec: add thread structure details (kernel stack, FPU state, quantum)
- [ ] Update `arch-x86_64` spec: add exception handling requirements
- [ ] Update `kernel-core` spec: add scheduler and timer requirements

### Task 7.2: Update README
- [ ] Document scheduler architecture (round-robin, preemptive)
- [ ] Document thread creation API (`thread_create`, `thread_yield`, `thread_exit`)
- [ ] Document exception handler behavior (register dump, halt)

### Task 7.3: Write testing guide
- [ ] Document how to test scheduler (shell commands, expected output)
- [ ] Document known limitations (32-bit only, single-CPU, no priority)

---

## Acceptance Criteria

This proposal is complete when:
1. ✅ All exception handlers (0-31) installed, print register dumps, halt gracefully
2. ✅ PIT timer fires at 100 Hz, `timer_tick()` called on every IRQ0
3. ✅ Context switching works: can switch between 2+ threads, interleaved output verified
4. ✅ Round-robin scheduler works: threads get equal time slices, preempted after quantum expires
5. ✅ Thread API works: `thread_create`, `thread_yield`, `thread_exit` all functional
6. ✅ FPU/SSE state isolation: threads don't corrupt each other's FP state
7. ✅ Idle thread works: CPU enters `hlt` when no threads ready
8. ✅ Shell commands added: `threads` (list), `spawn` (create), `crash` (test exceptions)
9. ✅ All tests pass (exception handlers, scheduler, FPU isolation)
10. ✅ Documentation updated (specs, README, testing guide)
