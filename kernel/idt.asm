; =============================================================
; ProbablyFineOS — Interrupt Descriptor Table
; Fills all 256 IDT entries with isr_default, then installs
; specific exception handlers for vectors 0-7.
; Drivers install their own IRQ handlers via idt_set_gate.
; =============================================================

; ==============================================================
; idt_init — build IDT and load IDTR
; ==============================================================
idt_init:
    ; Fill every entry with the default handler
    mov     ecx, 256
    lea     edi, [idt_table]
    lea     eax, [isr_default]

.fill_loop:
    mov     word  [edi],     ax             ; handler offset[15:0]
    mov     word  [edi + 2], GDT_KCODE_SEG ; code selector
    mov     byte  [edi + 4], 0              ; reserved
    mov     byte  [edi + 5], IDT_KERNEL_INT ; type/attr
    shr     eax, 16
    mov     word  [edi + 6], ax             ; handler offset[31:16]
    shr     eax, 16                         ; restore eax
    add     edi, 8
    loop    .fill_loop

    ; Install CPU exception stubs (0-7)
    lea     eax, [isr0]  ;  0 — divide-by-zero
    mov     cl, 0
    call    idt_set_gate

    lea     eax, [isr1]  ;  1 — debug
    mov     cl, 1
    call    idt_set_gate

    lea     eax, [isr2]  ;  2 — NMI
    mov     cl, 2
    call    idt_set_gate

    lea     eax, [isr3]  ;  3 — breakpoint
    mov     cl, 3
    call    idt_set_gate

    lea     eax, [isr4]  ;  4 — overflow
    mov     cl, 4
    call    idt_set_gate

    lea     eax, [isr5]  ;  5 — bound range exceeded
    mov     cl, 5
    call    idt_set_gate

    lea     eax, [isr6]  ;  6 — invalid opcode
    mov     cl, 6
    call    idt_set_gate

    lea     eax, [isr7]  ;  7 — device not available (FPU)
    mov     cl, 7
    call    idt_set_gate

    lidt    [idt_descriptor]
    sti
    ret

; ==============================================================
; idt_set_gate — install one IDT entry
; Input:
;   eax = handler 32-bit offset
;   cl  = vector number (0-255)
; Clobbers: eax, ecx, edi
; ==============================================================
idt_set_gate:
    push    eax
    movzx   edi, cl
    imul    edi, edi, 8             ; byte offset into idt_table
    add     edi, idt_table

    mov     word  [edi],     ax     ; handler low 16
    mov     word  [edi + 2], GDT_KCODE_SEG
    mov     byte  [edi + 4], 0
    mov     byte  [edi + 5], IDT_KERNEL_INT
    shr     eax, 16
    mov     word  [edi + 6], ax     ; handler high 16
    pop     eax
    ret

; ==============================================================
; Default ISR — prints exception number, halts
; ==============================================================
isr_default:
    pushad
    push_segs
    set_kernel_segs

    vga_print 'EXCEPTION: unhandled interrupt'
    ; TODO: print vector number from stack frame

    pop_segs
    popad
    freeze                          ; halt

; ==============================================================
; CPU Exception stubs (vectors 0-7)
; Each saves minimal context, prints a message, then halts.
; ==============================================================
macro exception_stub num, msg_sym {
  isr#num:
    pushad
    push_segs
    set_kernel_segs
    push msg_sym        ; push pointer to the pre-defined message string
    call vga_puts
    add  esp, 4
    pop_segs
    popad
    freeze
}

exc_msg0  db 'EXC #0  Divide By Zero', 0
exc_msg1  db 'EXC #1  Debug', 0
exc_msg2  db 'EXC #2  NMI', 0
exc_msg3  db 'EXC #3  Breakpoint', 0
exc_msg4  db 'EXC #4  Overflow', 0
exc_msg5  db 'EXC #5  Bound Range', 0
exc_msg6  db 'EXC #6  Invalid Opcode', 0
exc_msg7  db 'EXC #7  Device Not Available', 0

exception_stub 0, exc_msg0
exception_stub 1, exc_msg1
exception_stub 2, exc_msg2
exception_stub 3, exc_msg3
exception_stub 4, exc_msg4
exception_stub 5, exc_msg5
exception_stub 6, exc_msg6
exception_stub 7, exc_msg7

; ==============================================================
; IDT table (256 × 8 bytes = 2048 bytes, zero-initialised here,
; filled at runtime by idt_init)
; ==============================================================
align 8
idt_table:
    times 256 dq 0

; IDTR pseudo-descriptor
idt_descriptor:
    dw  256 * 8 - 1         ; limit
    dd  idt_table           ; linear base
