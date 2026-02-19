; =============================================================
; ProbablyFineOS — 8259A PIC Initialization
; Remaps IRQ0-7  → INT vectors 0x20-0x27
;         IRQ8-15 → INT vectors 0x28-0x2F
; All IRQs are masked after init; drivers unmask their own IRQ.
; =============================================================

; ==============================================================
; pic_init — remap and mask all IRQs
; ==============================================================
pic_init:
    ; ICW1 — start initialisation sequence (cascade, ICW4 needed)
    mov     al, 0x11
    out     PIC_MASTER_CMD, al
    io_delay
    out     PIC_SLAVE_CMD, al
    io_delay

    ; ICW2 — interrupt vector offsets
    mov     al, IRQ_BASE_MASTER         ; master → 0x20
    out     PIC_MASTER_DATA, al
    io_delay
    mov     al, IRQ_BASE_SLAVE          ; slave  → 0x28
    out     PIC_SLAVE_DATA, al
    io_delay

    ; ICW3 — cascade wiring
    mov     al, 0x04                    ; master: slave on IRQ2
    out     PIC_MASTER_DATA, al
    io_delay
    mov     al, 0x02                    ; slave: cascade identity = 2
    out     PIC_SLAVE_DATA, al
    io_delay

    ; ICW4 — 8086 mode
    mov     al, 0x01
    out     PIC_MASTER_DATA, al
    io_delay
    out     PIC_SLAVE_DATA, al
    io_delay

    ; Mask all IRQs (0xFF); drivers call pic_unmask_irq to enable theirs
    mov     al, 0xFF
    out     PIC_MASTER_DATA, al
    io_delay
    out     PIC_SLAVE_DATA, al
    io_delay

    ret

; ==============================================================
; pic_unmask_irq — enable a single IRQ line
; Input: al = IRQ number (0-15)
; ==============================================================
pic_unmask_irq:
    cmp     al, 8
    jge     .slave

    ; IRQ 0-7: master PIC
    mov     cl, al
    in      al, PIC_MASTER_DATA
    btr     eax, ecx            ; clear bit cl (enable)
    out     PIC_MASTER_DATA, al
    ret

.slave:
    ; IRQ 8-15: slave PIC  (also unmask IRQ2 on master for cascade)
    sub     al, 8
    mov     cl, al
    in      al, PIC_SLAVE_DATA
    btr     eax, ecx
    out     PIC_SLAVE_DATA, al
    ; ensure IRQ2 cascade is unmasked on master
    in      al, PIC_MASTER_DATA
    and     al, not (1 shl 2)
    out     PIC_MASTER_DATA, al
    ret

; ==============================================================
; pic_mask_irq — disable a single IRQ line
; Input: al = IRQ number (0-15)
; ==============================================================
pic_mask_irq:
    cmp     al, 8
    jge     .slave

    mov     cl, al
    in      al, PIC_MASTER_DATA
    bts     eax, ecx            ; set bit cl (mask)
    out     PIC_MASTER_DATA, al
    ret

.slave:
    sub     al, 8
    mov     cl, al
    in      al, PIC_SLAVE_DATA
    bts     eax, ecx
    out     PIC_SLAVE_DATA, al
    ret
