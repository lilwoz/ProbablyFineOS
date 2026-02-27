# process-model Specification

## Purpose
Defines the structure and behavior of processes and threads in ProbablyFineOS, including context switching, scheduling, and thread lifecycle management.

## Current Implementation Status
- ✅ Kernel threads implemented (32-bit protected mode)
- ⏳ User processes (with separate address spaces) - planned for future
- ✅ Round-robin scheduler with preemptive multitasking
- ✅ Thread Control Blocks (TCB) with full CPU state
## Requirements
### Requirement: Thread Structure (Implemented)
Each kernel thread SHALL have a Thread Control Block (TCB) containing:
- **TID**: Thread ID (0 = idle thread)
- **State**: READY, RUNNING, or DEAD
- **Quantum**: Remaining time slice in ticks (100 ticks = 1 second)
- **CPU Context**: All general-purpose registers (EAX-EDI, ESP, EBP, EFLAGS)
- **FPU State**: 512-byte buffer for FXSAVE/FXRSTOR (16-byte aligned)
- **Kernel Stack**: 16 KB dedicated stack at fixed memory location
- **Queue Links**: Next/prev pointers for ready queue (circular linked list)

#### Scenario: Thread creation
- **WHEN** Code calls `thread_create(entry_point)`
- **THEN** kernel allocates new TCB with unique TID
- **AND** allocates 16 KB kernel stack
- **AND** initializes CPU context (ESP points to stack top with entry point)
- **AND** sets state to READY
- **AND** adds thread to scheduler ready queue
- **AND** returns TID to caller

#### Scenario: Thread termination
- **WHEN** Thread calls `thread_exit()` or returns from entry point
- **THEN** kernel marks thread state as DEAD
- **AND** removes thread from ready queue
- **AND** calls scheduler to select next thread
- **AND** context switches away (never returns)
- **AND** thread resources remain allocated (no cleanup yet)

### Requirement: FPU/SSE State Isolation (Implemented)
Kernel SHALL preserve FPU/SSE state across context switches when FXSR is available:
- **Check CPUID**: Verify FXSR support (CPUID.01h:EDX.FXSR[bit 24])
- **Enable CR4.OSFXSR**: Set bit 9 in CR4 to enable FXSAVE/FXRSTOR
- **Save on switch**: Use FXSAVE to save 512 bytes of FPU/SSE state to TCB
- **Restore on switch**: Use FXRSTOR to load FPU/SSE state from TCB
- **Fallback**: If FXSR not available, skip FPU state save/restore

#### Scenario: FPU state isolation between threads
- **GIVEN** Thread A sets ST(0) = 1.23 and yields
- **AND** Thread B sets ST(0) = 4.56 and yields
- **WHEN** Scheduler switches back to Thread A
- **THEN** Thread A reads ST(0) and gets 1.23 (original value)
- **AND** Thread B's FPU state does not corrupt Thread A's state

### Requirement: Process Structure
Each process SHALL have: PID, CR3 (PML4 phys), saved registers, kernel stack, state (RUNNING/READY/BLOCKED/ZOMBIE).

#### Scenario: Process creation (fork)
- **WHEN** Process calls sys_fork()
- **THEN** kernel allocates new process structure
- **AND** copies parent PML4 (userland pages marked copy-on-write)
- **AND** adds child to scheduler ready queue
- **AND** returns child PID to parent, 0 to child

### Requirement: Context Switch (Implemented for Threads)
Kernel SHALL switch threads by:
1. **Save old context**: Store EAX-EDI, ESP, EFLAGS to old TCB
2. **Save FPU state**: Execute FXSAVE if FXSR available
3. **Update pointer**: Set `current_thread` to new TCB
4. **Restore FPU state**: Execute FXRSTOR if FXSR available
5. **Restore context**: Load EAX-EDI, ESP, EFLAGS from new TCB
6. **Return**: RET instruction pops saved EIP from stack

Note: No CR3 loading (all threads share kernel address space)

#### Scenario: Timer preemption (Implemented)
- **WHEN** IRQ0 timer fires while Thread A runs
- **THEN** timer handler saves A's registers to A->TCB
- **AND** FXSAVE stores A's FPU state (if supported)
- **AND** scheduler decrements A's quantum
- **IF** quantum expired **THEN** scheduler adds A to ready queue
- **AND** scheduler selects next READY thread B (or idle if none)
- **AND** FXRSTOR loads B's FPU state (if supported)
- **AND** restores B's registers from B->TCB
- **AND** IRET returns to B's saved EIP

#### Scenario: Voluntary yield (Implemented)
- **WHEN** Thread A calls `thread_yield()`
- **THEN** kernel adds A to end of ready queue (state = READY)
- **AND** scheduler selects next READY thread B
- **AND** context switches from A to B
- **AND** A will run again when scheduler selects it from queue

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

