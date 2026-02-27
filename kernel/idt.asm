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

    ; Exception handlers (0-31) installed by install_exception_handlers
    ; (from exceptions.asm, called after idt_init in kernel_entry)

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
; CPU Exception stubs (vectors 0-31)
; Moved to exceptions.asm
; ==============================================================

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
