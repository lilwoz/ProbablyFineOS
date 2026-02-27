; =============================================================
; ProbablyFineOS — Kernel Entry Point
; Assembled as a flat binary loaded at KERNEL_LOAD_ADDR (0x10000).
;
; Build:  fasm kernel/kernel.asm build/kernel.bin [-d ARCH=64]
; Link:   see Makefile (dd into disk image at LBA 17)
; =============================================================

format binary
use32

; ---- Includes first so all symbols are defined before 'org' ----
include '../include/constants.inc'
include '../include/macros.inc'
include '../include/structs.inc'

org KERNEL_LOAD_ADDR            ; = 0x10000

; ==============================================================
; kernel_entry — first instruction executed after Stage 2 jump
; ==============================================================
kernel_entry:
    ; Stage 2 already set CS/DS/ES/SS to flat segments.
    ; Reload with our own GDT after gdt_init, but first set up
    ; a proper stack so we can call functions.
    mov     ax, BOOT_DATA_SEG       ; use stage2 data seg until gdt loaded
    mov     ds, ax
    mov     es, ax
    mov     fs, ax
    mov     gs, ax
    mov     ss, ax
    mov     esp, KERNEL_STACK_TOP   ; kernel stack (grows down from 0x90000)

    ; ---- GDT (install kernel's own descriptor table) ---------
    call    gdt_init                ; kernel/gdt.asm
    ; After gdt_init: CS=GDT_KCODE_SEG, DS/ES/...=GDT_KDATA_SEG

    ; ---- FPU (initialize FPU and check for FXSR support) ----
    call    fpu_init                ; kernel/fpu.asm

    ; ---- IDT (set up interrupt/exception handlers) -----------
    call    idt_init                ; kernel/idt.asm
    call    install_exception_handlers ; kernel/exceptions.asm (CPU exceptions 0-31)
    ; After idt_init: STI is called — interrupts enabled

    ; ---- PIC (remap IRQs, mask all) --------------------------
    call    pic_init                ; kernel/pic.asm

    ; ---- Thread subsystem (create idle thread) ---------------
    ; MUST be initialized BEFORE PIT to avoid timer interrupts before ready
    call    thread_init             ; kernel/thread.asm

    ; ---- Scheduler (initialize ready queue) ------------------
    call    scheduler_init          ; kernel/scheduler.asm

    ; ---- PIT (system timer, 100 Hz) -------------------------
    ; Initialize AFTER threads/scheduler are ready
    mov     eax, 100                ; 100 Hz = 10ms interval
    call    pit_init                ; kernel/pit.asm

    ; ---- Video (clear screen, show banner) -------------------
    call    vga_init                ; drivers/video/vga.asm

    ; ---- Input devices ---------------------------------------
    call    keyboard_init           ; drivers/input/keyboard.asm
    call    mouse_init              ; drivers/input/mouse.asm

    ; ---- Main loop -------------------------------------------
    call    shell_main              ; kernel/shell.asm

    ; Should never return; if it does — halt safely
.hang:
    cli
    hlt
    jmp     .hang

; ==============================================================
; Sub-system modules (included in one flat binary)
; ==============================================================
include 'gdt.asm'
include 'fpu.asm'
include 'idt.asm'
include 'exceptions.asm'
include 'pic.asm'
include '../drivers/video/vga.asm'
include '../drivers/video/vesa.asm'
include 'pit.asm'
include 'thread.asm'
include 'scheduler.asm'
include '../drivers/input/keyboard.asm'
include '../drivers/input/mouse.asm'
include 'shell.asm'
