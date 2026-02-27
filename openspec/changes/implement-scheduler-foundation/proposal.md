# Scheduler Foundation: Interrupts, Context Switching, Preemptive Multitasking

## Why

The current kernel is single-tasked (runs shell in infinite loop). To evolve toward the architecture contract (x86_64 with preemptive multitasking), we need the **foundation for multitasking**:

1. **Exception handling**: Catch hardware exceptions (page fault, GPF, double fault) before they cause silent crashes
2. **System timer**: Periodic interrupts to preempt running code (quantum-based scheduling)
3. **Context switching**: Save/restore full CPU state (registers, FPU/SSE, CR3) between tasks
4. **Round-robin scheduler**: Simple preemptive scheduler that switches between threads on timer ticks

This is **vertical #1** — building from bottom (interrupts) to top (scheduler). Without this foundation, we cannot implement fork/exec, userland processes, or any form of concurrency.

**Current state**: 32-bit kernel with basic IDT (exceptions halt), no timer IRQ handling, no scheduler.

**Target state**: Preemptive scheduler with timer-driven context switching, exception handlers with register dumps, ready for future userland processes.

## What changes

### Implementation work (code changes):
1. **Exception handlers** (`kernel/exceptions.asm`, `kernel/panic.c`):
   - Install ISRs for CPU exceptions 0-31 (divide-by-zero, page fault, GPF, double fault, etc.)
   - Each handler prints register dump (RIP, RSP, error code, CR2 for page fault) and halts
   - Triple-fault detection (if double fault handler itself faults → reboot)

2. **System timer** (`drivers/timer/pit.c`, `drivers/timer/apic_timer.c`):
   - PIT (Programmable Interval Timer): configure channel 0 for IRQ0 at 100 Hz (10ms quantum)
   - LAPIC timer (future): per-CPU timer for SMP, higher precision
   - Timer IRQ handler calls scheduler tick

3. **Context switching** (`kernel/context.asm`, `kernel/thread.c`):
   - `struct thread`: kernel stack, user stack (placeholder), saved registers, FPU/SSE state buffer, state (RUNNING/READY/BLOCKED)
   - `context_switch(old, new)`: save old thread state (pushad + FXSAVE), load new thread state (FXRSTOR + popad), switch stacks
   - Assembly trampoline for initial thread entry

4. **Round-robin scheduler** (`kernel/scheduler.c`):
   - Linked list of threads (ready queue)
   - `schedule()`: select next READY thread (round-robin), mark current as READY
   - `timer_tick()`: decrement quantum counter, call `schedule()` if quantum expired
   - Idle thread (PID 0): runs `hlt` when no other threads ready

5. **Thread API** (`kernel/thread.c`):
   - `thread_create(entry_point, arg)`: allocate thread structure, set up kernel stack with entry trampoline
   - `thread_yield()`: voluntarily give up CPU (for cooperative multitasking testing)
   - `thread_exit()`: mark thread as ZOMBIE, call scheduler

### Documentation (spec deltas):
- Update `process-model` spec: add thread structure details (kernel stack, FPU state)
- Update `arch-x86_64` spec: add exception handling requirements (register dumps)
- Update existing `kernel-core` spec: add scheduler and timer requirements

## Impact

**Positive**:
- **Preemptive multitasking**: Kernel can run multiple tasks concurrently (foundation for userland processes)
- **Robustness**: Exception handlers catch bugs early with diagnostic info (no silent crashes)
- **Testability**: Can create test threads to verify scheduler works before implementing fork/exec

**Breaking changes**:
- **Architectural shift**: Moves from 32-bit flat binary toward 64-bit with context switching (but still 32-bit for now; 64-bit transition is a separate future proposal)
- **IRQ timing**: Timer IRQ fires every 10ms, interrupting current code. Must ensure interrupt handlers are reentrant.

**Performance**:
- **Context switch overhead**: ~1-2μs per switch (save/restore registers + FXSAVE/FXRSTOR). At 100 Hz (10ms quantum), overhead is <1%.
- **Idle CPU usage**: Idle thread uses `hlt` to sleep, so CPU enters low-power state when no work.

## Risks

1. **FPU/SSE state corruption**: If FXSAVE/FXRSTOR not done correctly, FP calculations will produce wrong results. Mitigation: test with FP-heavy threads, verify state isolation.

2. **Stack overflow**: Each thread needs kernel stack (4 pages = 16 KB). If stack overflows, corrupts adjacent memory. Mitigation: guard pages (unmap page below stack), page fault on overflow.

3. **Timer IRQ rate**: 100 Hz might be too slow (poor responsiveness) or too fast (high overhead). Mitigation: make configurable (10 Hz - 1000 Hz range), profile to find sweet spot.

4. **Race conditions**: Scheduler is interrupt-driven, so scheduler code can be interrupted by timer IRQ. Mitigation: disable interrupts (`cli`) during critical sections (scheduler data structure updates).

5. **Triple fault**: If exception handler has a bug (e.g., page fault in page fault handler), CPU triple-faults (resets). Mitigation: separate exception stacks (IST in x64), careful exception handler code review.

## Alternatives considered

1. **Cooperative multitasking only**: Threads explicitly yield (`thread_yield()`), no preemption. Rejected: one misbehaving thread can hang entire system. Preemptive is safer.

2. **User-space scheduler**: Kernel provides primitives, scheduler runs in userland. Rejected: premature optimization, adds complexity. Kernel scheduler is simpler for initial implementation.

3. **Skip FPU/SSE state save**: Only save integer registers, crash if thread uses FP. Rejected: modern code often uses SSE (even memcpy), so FP state must be saved.

4. **Per-thread page tables (CR3)**: Each thread has own address space. Deferred: this is process-level (fork/exec), not thread-level. Threads share address space. CR3 switching comes later with processes.
