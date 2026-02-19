; =============================================================
; ProbablyFineOS — PS/2 Mouse Driver
; Included into kernel/kernel.asm
;
; IRQ12 → IDT vector 0x2C
; Standard PS/2 3-byte packet:
;   Byte 0: YO XO YS XS 1  M  R  L   (overflow, sign, buttons)
;   Byte 1: X movement delta (signed)
;   Byte 2: Y movement delta (signed, positive = up)
;
; Public state (read-only from other modules):
;   mouse_x       — signed 16-bit X coordinate [0, VESA_WIDTH-1]
;   mouse_y       — signed 16-bit Y coordinate [0, VESA_HEIGHT-1]
;   mouse_buttons — byte: bit0=L, bit1=R, bit2=M
; =============================================================

; ==============================================================
; mouse_init — enable PS/2 auxiliary device and IRQ12
; ==============================================================
mouse_init:
    ; ---- Enable auxiliary device ----------------------------
    ps2_wait_write
    mov     al, 0xA8            ; enable aux
    out     PS2_CMD_PORT, al

    ; ---- Enable IRQ12 in PS/2 controller config byte --------
    ps2_wait_write
    mov     al, 0x20            ; read config byte command
    out     PS2_CMD_PORT, al
    ps2_wait_read
    in      al, PS2_DATA_PORT   ; read current config
    or      al, 0x02            ; set AUX IRQ enable bit
    and     al, not 0x20        ; clear AUX clock disable bit
    push    eax                 ; save modified config
    ps2_wait_write
    mov     al, 0x60            ; write config byte command
    out     PS2_CMD_PORT, al
    ps2_wait_write
    pop     eax
    out     PS2_DATA_PORT, al   ; write modified config

    ; ---- Send "Enable Data Reporting" to mouse device -------
    ps2_wait_write
    mov     al, 0xD4            ; route next byte to aux device
    out     PS2_CMD_PORT, al
    ps2_wait_write
    mov     al, 0xF4            ; enable data reporting
    out     PS2_DATA_PORT, al

    ; Wait for ACK (0xFA) — ignore it
    ps2_wait_read
    in      al, PS2_DATA_PORT

    ; ---- Install IRQ12 handler in IDT vector 0x2C -----------
    lea     eax, [irq12_mouse_handler]
    mov     cl, IRQ_MOUSE           ; = 0x2C
    call    idt_set_gate

    ; ---- Unmask IRQ12 (on slave PIC, IRQ 12 = slave line 4) -
    mov     al, 12
    call    pic_unmask_irq

    ; ---- Home mouse to screen centre ------------------------
    mov     word [mouse_x], VESA_WIDTH  / 2
    mov     word [mouse_y], VESA_HEIGHT / 2

    ret

; ==============================================================
; IRQ12 Handler — called once per PS/2 byte
; Accumulates bytes into a 3-byte packet then decodes
; ==============================================================
irq12_mouse_handler:
    pushad
    push_segs
    set_kernel_segs

    in      al, PS2_DATA_PORT

    ; State machine: mouse_phase tracks which byte we're receiving
    movzx   ecx, byte [mouse_phase]
    cmp     ecx, 0
    je      .byte0
    cmp     ecx, 1
    je      .byte1
    ; else byte2
    jmp     .byte2

    ; ---- Byte 0: flags byte ---------------------------------
.byte0:
    ; Bit 3 must be set (always-1 bit); if not, resync
    test    al, 0x08
    jz      .eoi_mouse          ; ignore and stay in phase 0

    mov     [mouse_pkt + 0], al
    inc     byte [mouse_phase]
    jmp     .eoi_mouse

    ; ---- Byte 1: X delta ------------------------------------
.byte1:
    mov     [mouse_pkt + 1], al
    inc     byte [mouse_phase]
    jmp     .eoi_mouse

    ; ---- Byte 2: Y delta — decode full packet ---------------
.byte2:
    mov     [mouse_pkt + 2], al
    mov     byte [mouse_phase], 0   ; reset for next packet
    call    mouse_decode_packet
    jmp     .eoi_mouse

.eoi_mouse:
    eoi_slave           ; sends EOI to both slave and master
    pop_segs
    popad
    iret

; ==============================================================
; mouse_decode_packet — extract button/position from 3-byte pkt
; ==============================================================
mouse_decode_packet:
    push    eax
    push    ebx

    ; ---- Buttons (bits 0-2 of byte 0) ----------------------
    mov     al, [mouse_pkt + 0]
    and     al, 0x07
    mov     [mouse_buttons], al

    ; ---- X delta: 9-bit signed (bit 4 of byte 0 = sign) ----
    movsx   eax, byte [mouse_pkt + 1]   ; sign-extend 8-bit delta
    mov     bl, [mouse_pkt + 0]
    test    bl, 0x10                     ; X overflow bit
    jz      .no_x_ov
    ; if overflow — use clamped maximum
    mov     eax, 127                     ; or -128 depending on sign
.no_x_ov:
    ; apply delta to mouse_x
    movsx   ebx, word [mouse_x]
    add     ebx, eax
    ; clamp [0, VESA_WIDTH-1]
    cmp     ebx, 0
    jge     .clamp_x_max
    xor     ebx, ebx
.clamp_x_max:
    cmp     ebx, VESA_WIDTH - 1
    jle     .store_x
    mov     ebx, VESA_WIDTH - 1
.store_x:
    mov     [mouse_x], bx

    ; ---- Y delta: 9-bit signed (bit 5 of byte 0 = sign) ----
    ; PS/2 Y is inverted: positive delta = cursor up on screen
    movsx   eax, byte [mouse_pkt + 2]
    neg     eax                          ; invert Y axis
    mov     bl, [mouse_pkt + 0]
    test    bl, 0x20                     ; Y overflow
    jz      .no_y_ov
    mov     eax, 0
.no_y_ov:
    movsx   ebx, word [mouse_y]
    add     ebx, eax
    cmp     ebx, 0
    jge     .clamp_y_max
    xor     ebx, ebx
.clamp_y_max:
    cmp     ebx, VESA_HEIGHT - 1
    jle     .store_y
    mov     ebx, VESA_HEIGHT - 1
.store_y:
    mov     [mouse_y], bx

    pop     ebx
    pop     eax
    ret

; ==============================================================
; Driver State
; ==============================================================
mouse_x         dw 0            ; current X position
mouse_y         dw 0            ; current Y position
mouse_buttons   db 0            ; button bitmask (L=0, R=1, M=2)

; Packet assembly
mouse_phase     db 0            ; 0=expect byte0, 1=byte1, 2=byte2
mouse_pkt:      db 0, 0, 0      ; raw packet bytes
