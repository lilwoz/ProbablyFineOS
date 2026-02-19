; =============================================================
; ProbablyFineOS — Common Macros  (32-bit protected mode only)
; Include AFTER constants.inc
; =============================================================

; -------------------------------------------------------------
; I/O helpers
; Clobbers: nothing (saves/restores eax, edx)
; -------------------------------------------------------------

; Write byte _val to I/O port _port
macro outb _port, _val {
    push eax
    push edx
    mov  edx, _port
    mov  al,  _val
    out  dx,  al
    pop  edx
    pop  eax
}

; Read byte from I/O port _port into AL
; (caller must save AL / EAX if needed)
macro inb _port {
    push edx
    mov  edx, _port
    in   al,  dx
    pop  edx
}

; Short I/O delay: write to POST diagnostic port 0x80
macro io_delay {
    push eax
    push edx
    mov  edx, IO_DELAY_PORT
    xor  al,  al
    out  dx,  al
    pop  edx
    pop  eax
}

; Wait until PS/2 controller input buffer is empty (bit 1 of status = 0)
macro ps2_wait_write {
    local .wait
  .wait:
    in   al, PS2_STATUS_PORT
    test al, 0x02
    jnz  .wait
}

; Wait until PS/2 controller output buffer is full (bit 0 of status = 1)
macro ps2_wait_read {
    local .wait
  .wait:
    in   al, PS2_STATUS_PORT
    test al, 0x01
    jz   .wait
}

; Send EOI to PIC master (and slave if IRQ was from slave)
macro eoi_master {
    push eax
    mov  al, PIC_EOI
    out  PIC_MASTER_CMD, al
    pop  eax
}

macro eoi_slave {
    push eax
    mov  al, PIC_EOI
    out  PIC_SLAVE_CMD,  al
    out  PIC_MASTER_CMD, al
    pop  eax
}

; -------------------------------------------------------------
; VGA convenience macro — print a literal string at compile time
; Usage:  vga_print "Hello world"
; Pushes the string address and calls vga_puts; cleans stack.
; -------------------------------------------------------------
macro vga_print _str {
    local .str_data, .str_end
    jmp  .str_end
  .str_data db _str, 0
  .str_end:
    push .str_data
    call vga_puts
    add  esp, 4
}

; -------------------------------------------------------------
; Halt forever (interrupts disabled)
; -------------------------------------------------------------
macro freeze {
    local .loop
    cli
  .loop:
    hlt
    jmp .loop
}

; -------------------------------------------------------------
; Push all segment registers (for ISR prologues)
; -------------------------------------------------------------
macro push_segs {
    push ds
    push es
    push fs
    push gs
}

macro pop_segs {
    pop  gs
    pop  fs
    pop  es
    pop  ds
}

; -------------------------------------------------------------
; Set kernel data segment registers inside an ISR
; (After pushad + push_segs)
; -------------------------------------------------------------
macro set_kernel_segs {
    mov  ax, GDT_KDATA_SEG
    mov  ds, ax
    mov  es, ax
    mov  fs, ax
    mov  gs, ax
}
