; =============================================================
; ProbablyFineOS — Programmable Interval Timer (PIT)
; Included into kernel/kernel.asm
;
; Configures PIT channel 0 to generate IRQ0 at configurable frequency
; Default: 100 Hz (10ms interval) for scheduler quantum
; =============================================================

; PIT I/O ports
PIT_CH0_DATA    equ 0x40    ; Channel 0 data port
PIT_CH1_DATA    equ 0x41    ; Channel 1 data port
PIT_CH2_DATA    equ 0x42    ; Channel 2 data port
PIT_COMMAND     equ 0x43    ; Mode/Command register

; PIT command byte format:
; Bits 7-6: Channel (00=ch0, 01=ch1, 10=ch2)
; Bits 5-4: Access mode (11=lo/hi byte)
; Bits 3-1: Operating mode (011=mode 3, square wave)
; Bit 0:    Binary/BCD (0=binary)
PIT_CMD_CH0     equ 0x36    ; 00 11 011 0 = ch0, lo/hi, mode3, binary

; PIT base frequency (Hz)
PIT_BASE_FREQ   equ 1193182

; Global tick counter
timer_ticks     dd 0

; ==============================================================
; pit_init — initialize PIT channel 0 for IRQ0 timer interrupts
; Input: eax = desired frequency in Hz (e.g., 100 for 10ms ticks)
; Clobbers: eax, edx
; ==============================================================
pit_init:
    push    eax
    push    edx
    push    ecx

    ; Calculate divisor: PIT_BASE_FREQ / frequency
    ; For 100 Hz: 1193182 / 100 = 11932 (0x2E9C)
    mov     edx, 0
    mov     ecx, eax                ; Save frequency
    mov     eax, PIT_BASE_FREQ
    div     ecx                     ; EAX = divisor
    mov     ecx, eax                ; ECX = divisor

    ; Send command byte to PIT
    mov     al, PIT_CMD_CH0
    out     PIT_COMMAND, al
    io_delay

    ; Send divisor low byte
    mov     al, cl                  ; Low byte
    out     PIT_CH0_DATA, al
    io_delay

    ; Send divisor high byte
    mov     al, ch                  ; High byte
    out     PIT_CH0_DATA, al
    io_delay

    ; Install IRQ0 handler in IDT
    lea     eax, [irq0_timer_handler]
    mov     cl, 0x20                ; IDT vector 32 (IRQ0)
    call    idt_set_gate

    ; Unmask IRQ0 in PIC
    mov     al, 0
    call    pic_unmask_irq

    pop     ecx
    pop     edx
    pop     eax
    ret

; ==============================================================
; irq0_timer_handler — PIT timer IRQ0 interrupt handler
; Called 100 times per second (every 10ms)
; ==============================================================
irq0_timer_handler:
    pushad
    push_segs
    set_kernel_segs

    ; Call C-style timer_tick function
    call    timer_tick

    ; Send EOI to master PIC
    eoi_master

    pop_segs
    popad
    iret

; ==============================================================
; timer_tick — called on every timer interrupt
; Increments global tick counter and calls scheduler
; ==============================================================
timer_tick:
    push    eax

    ; Increment tick counter
    inc     dword [timer_ticks]

    ; Call scheduler to check quantum expiration and possibly context switch
    call    scheduler_tick

    pop     eax
    ret

; ==============================================================
; timer_get_ticks — return current tick count
; Returns: eax = tick count
; ==============================================================
timer_get_ticks:
    mov     eax, [timer_ticks]
    ret
