# abi-userland Specification

## Purpose
TBD - created by archiving change os-architecture-contract. Update Purpose after archive.
## Requirements
### Requirement: ELF64 Executable Format
Userland programs SHALL be ELF64 binaries. Kernel SHALL load PT_LOAD segments into process address space.

#### Scenario: ELF64 loading
- **WHEN** Kernel executes sys_exec("/bin/hello")
- **THEN** it parses ELF64 headers, maps PT_LOAD segments
- **AND** sets RIP=e_entry, RSP=stack_top
- **AND** transfers control to userland

### Requirement: SYSCALL/SYSRET Interface
Userland SHALL invoke syscalls via SYSCALL instruction (number in RAX, args in RDI/RSI/RDX/R10/R8/R9). Kernel returns value in RAX (negative=-errno).

#### Scenario: sys_write syscall
- **WHEN** Userland executes SYSCALL with RAX=1 (write), RDI=fd, RSI=buf, RDX=count
- **THEN** kernel switches to ring0, dispatches to sys_write
- **AND** returns bytes written in RAX
- **AND** executes SYSRET to return to userland

