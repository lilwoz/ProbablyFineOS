## ADDED Requirements

### Requirement: Process Structure
Each process SHALL have: PID, CR3 (PML4 phys), saved registers, kernel stack, state (RUNNING/READY/BLOCKED/ZOMBIE).

#### Scenario: Process creation (fork)
- **WHEN** Process calls sys_fork()
- **THEN** kernel allocates new process structure
- **AND** copies parent PML4 (userland pages marked copy-on-write)
- **AND** adds child to scheduler ready queue
- **AND** returns child PID to parent, 0 to child

### Requirement: Context Switch
Kernel SHALL switch processes by: saving current registers, updating current_process pointer, loading CR3 (new PML4), switching kernel stack (TSS.RSP0), restoring registers, jumping to saved RIP.

#### Scenario: Timer preemption
- **WHEN** IRQ0 timer fires while Process A runs
- **THEN** kernel saves A's registers to A->context
- **AND** scheduler selects next process B
- **AND** loads B->pml4_phys into CR3
- **AND** restores B's registers from B->context
- **AND** returns to B's saved RIP
