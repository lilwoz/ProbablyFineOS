# driver-api Specification

## Purpose
TBD - created by archiving change os-architecture-contract. Update Purpose after archive.
## Requirements
### Requirement: Driver API Abstraction
Drivers SHALL use driver API (driver_map_mmio, driver_request_irq, driver_inb/outb) instead of raw hardware access. Phase 1: in-kernel. Phase 2: userland drivers via syscalls.

#### Scenario: Keyboard driver initialization (Phase 1)
- **WHEN** Kernel calls keyboard_init()
- **THEN** driver calls driver_request_irq(1, handler, ctx)
- **AND** kernel installs ISR into IDT[0x21]
- **AND** driver calls driver_outb(0x60, cmd) to configure keyboard

### Requirement: Userland Driver IRQ Forwarding (Phase 2)
Kernel SHALL forward IRQs to userland drivers via shared memory ring buffer. Driver blocks on sys_wait_irq(), kernel writes IRQ event to ring, driver reads and handles.

#### Scenario: Userland keyboard driver IRQ
- **WHEN** IRQ1 fires (keyboard)
- **THEN** kernel ISR writes scancode to shared ring buffer
- **AND** unblocks driver process waiting in sys_wait_irq()
- **AND** driver reads ring buffer, processes scancode
- **AND** calls sys_irq_ack(1) to acknowledge

