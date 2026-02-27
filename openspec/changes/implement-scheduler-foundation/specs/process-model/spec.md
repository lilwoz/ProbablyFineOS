## ADDED Requirements

### Requirement: Thread Structure Implementation
The kernel SHALL implement a thread structure containing: TID, state (READY/RUNNING/BLOCKED/ZOMBIE), kernel stack pointer, saved CPU registers (EAX-EDI, EIP, ESP, EFLAGS, segment registers), and FPU/SSE state buffer (512 bytes, 16-byte aligned).

Each thread SHALL have a dedicated kernel stack (minimum 16 KB) allocated from kernel heap.

#### Scenario: Thread structure allocation
- **WHEN** Kernel creates a new thread via `thread_create(entry, arg)`
- **THEN** it allocates `struct thread` from heap
- **AND** allocates 16 KB kernel stack (4 pages)
- **AND** initializes TID (unique), state (READY), saved registers (entry point in EIP)
- **AND** captures initial FPU state via `FXSAVE` into fpu_state buffer

### Requirement: Context Switch Implementation
The kernel SHALL implement context switching that saves and restores full CPU state including integer registers and FPU/SSE state.

Context switch SHALL use `FXSAVE` to save old thread FPU state and `FXRSTOR` to restore new thread FPU state.

#### Scenario: Context switch execution
- **WHEN** Scheduler calls `context_switch(old_thread, new_thread)`
- **THEN** it saves old thread registers (pushad or manual save to old->regs)
- **AND** executes `FXSAVE [old->fpu_state]` to save FPU/SSE state
- **AND** updates global `current_thread = new_thread`
- **AND** executes `FXRSTOR [new->fpu_state]` to restore new thread FPU state
- **AND** restores new thread registers (popad or manual restore from new->regs)
- **AND** jumps to new thread EIP (resume execution)

### Requirement: Round-Robin Scheduler
The kernel SHALL implement a round-robin scheduler with time-slice based preemption.

Scheduler SHALL maintain a circular ready queue of READY threads and select next thread in round-robin order.

#### Scenario: Timer-driven scheduling
- **WHEN** Timer IRQ fires (every 10ms at 100 Hz)
- **THEN** `timer_tick()` decrements current thread quantum counter
- **AND** if quantum <= 0, moves current thread to ready queue (if still RUNNING)
- **AND** calls `schedule()` to select next READY thread
- **AND** resets new thread quantum to default (100 ticks = 1 second)
- **AND** calls `context_switch(old, new)` to switch execution
