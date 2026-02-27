## ADDED Requirements

### Requirement: System Timer (PIT) Configuration
The kernel SHALL configure the Programmable Interval Timer (PIT) channel 0 to generate IRQ0 at 100 Hz (10ms interval).

PIT SHALL be programmed in mode 3 (square wave) with divisor calculated as: `1193182 / 100 = 11932`.

#### Scenario: PIT initialization
- **WHEN** Kernel initializes system timer via `pit_init(100)`
- **THEN** it sends command byte 0x36 to port 0x43 (channel 0, lo/hi byte, mode 3, binary)
- **AND** writes divisor low byte (11932 & 0xFF) to port 0x40
- **AND** writes divisor high byte ((11932 >> 8) & 0xFF) to port 0x40
- **AND** PIT begins generating IRQ0 at 100 Hz (every 10ms)

### Requirement: Timer IRQ Handler
The kernel SHALL install an IRQ0 handler that calls scheduler tick function on each timer interrupt.

Timer handler SHALL send End-of-Interrupt (EOI) to PIC after processing.

#### Scenario: Timer IRQ processing
- **WHEN** PIT generates IRQ0 (timer tick)
- **THEN** CPU jumps to `irq0_timer_handler` (IDT vector 0x20)
- **AND** handler saves registers (pushad, push_segs, set_kernel_segs)
- **AND** calls C function `timer_tick()`
- **AND** `timer_tick()` increments global tick counter
- **AND** `timer_tick()` calls scheduler to check quantum expiration
- **AND** handler sends EOI (0x20) to PIC master (port 0x20)
- **AND** handler restores registers (pop_segs, popad) and returns (iret)

### Requirement: Scheduler Integration
The kernel SHALL integrate scheduler with timer tick to implement preemptive multitasking.

Scheduler SHALL be called on every timer tick to potentially switch threads.

#### Scenario: Quantum expiration and preemption
- **WHEN** Timer tick occurs and current thread quantum reaches 0
- **THEN** `timer_tick()` marks current thread as READY (if was RUNNING)
- **AND** adds current thread to end of ready queue
- **AND** calls `schedule()` to select next READY thread
- **AND** calls `context_switch(old, new)` to switch execution
- **AND** new thread resumes with quantum reset to 100 ticks

### Requirement: Idle Thread
The kernel SHALL create an idle thread (TID 0) that runs when no other threads are READY.

Idle thread SHALL execute `HLT` instruction to enter low-power state until next interrupt.

#### Scenario: Idle thread execution
- **WHEN** Scheduler finds ready queue empty (no READY threads)
- **THEN** `schedule()` returns pointer to idle thread (TID 0)
- **AND** context switches to idle thread
- **AND** idle thread executes infinite loop: `while(1) { asm("hlt"); }`
- **AND** CPU enters low-power state, wakes on next IRQ (timer, keyboard, etc.)
- **AND** on next timer tick, scheduler checks ready queue again
