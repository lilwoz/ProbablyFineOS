; =============================================================
; ProbablyFineOS — PS/2 Keyboard Driver
; Included into kernel/kernel.asm
;
; IRQ1 → IDT vector 0x21
; Scancode set 1 → ASCII translation.
;
; Public API:
;   keyboard_init   — flush port, install IRQ1 handler, unmask IRQ1
;   keyboard_getc   — return next char from ring buffer (0 = empty)
; =============================================================

; ---- Key modifier flags (bit field in key_modifiers) --------
KM_SHIFT    equ 0x01
KM_CTRL     equ 0x02
KM_ALT      equ 0x04
KM_CAPSLOCK equ 0x08

; ---- Scancodes for modifiers (make codes) -------------------
SC_LSHIFT   equ 0x2A
SC_RSHIFT   equ 0x36
SC_CTRL     equ 0x1D
SC_ALT      equ 0x38
SC_CAPS     equ 0x3A

; ---- Break-code bit -----------------------------------------
SC_BREAK    equ 0x80

; ==============================================================
; keyboard_init — set up keyboard driver
; ==============================================================
keyboard_init:
    push    eax

    ; Flush any stale bytes in the PS/2 output buffer
    .flush:
        in      al, PS2_STATUS_PORT
        test    al, 0x01            ; output buffer full?
        jz      .flush_done
        in      al, PS2_DATA_PORT
        jmp     .flush
    .flush_done:

    ; --- Step 1: configure i8042 command byte -------------------
    ; Read (cmd 0x20), then write back (cmd 0x60) with:
    ;   bit 0 = 1  keyboard IRQ enabled
    ;   bit 4 = 0  keyboard clock enabled  (1 = disabled)
    ;   bit 6 = 0  i8042 translation OFF   (we use native set 1 below)
    ; NOTE: ps2_wait_write / ps2_wait_read CLOBBER AL.
    ps2_wait_write
    mov     al, 0x20                ; read i8042 command byte
    out     PS2_CMD_PORT, al
    ps2_wait_read
    in      al, PS2_DATA_PORT       ; AL = current command byte
    or      al, 0x01                ; bit 0 ON  (kbd IRQ)
    and     al, 0xAF                ; bit 4 OFF (clock), bit 6 OFF (translation)
    push    eax                     ; save
    ps2_wait_write
    mov     al, 0x60                ; write i8042 command byte
    out     PS2_CMD_PORT, al
    ps2_wait_write
    pop     eax                     ; restore modified byte into AL
    out     PS2_DATA_PORT, al

    ; --- Step 2: tell keyboard to use scan code SET 1 natively --
    ; With i8042 translation disabled (bit 6 = 0 above), the
    ; keyboard must send set 1 itself.  Command 0xF0 0x01 does this.
    ps2_wait_write
    mov     al, 0xF0                ; "select scan code set" command
    out     KBD_DATA_PORT, al
    ps2_wait_read
    in      al, PS2_DATA_PORT       ; discard ACK (0xFA)

    ps2_wait_write
    mov     al, 0x01                ; select set 1
    out     KBD_DATA_PORT, al
    ps2_wait_read
    in      al, PS2_DATA_PORT       ; discard ACK (0xFA)

    ; Flush buffer one more time to clear any leftover ACKs
    .flush2:
        in      al, PS2_STATUS_PORT
        test    al, 0x01
        jz      .flush2_done
        in      al, PS2_DATA_PORT
        jmp     .flush2
    .flush2_done:

    ; Install IRQ1 handler into IDT vector 0x21
    lea     eax, [irq1_keyboard_handler]
    mov     cl, IRQ_KEYBOARD        ; = 0x21
    call    idt_set_gate

    ; Unmask IRQ1 on master PIC
    mov     al, 1                   ; IRQ 1
    call    pic_unmask_irq

    pop     eax
    ret

; ==============================================================
; keyboard_getc — dequeue one character from ring buffer
; Return: AL = ASCII char, or 0 if buffer empty
; ==============================================================
keyboard_getc:
    push    ebx
    mov     ebx, [key_buf_head]
    cmp     ebx, [key_buf_tail]
    je      .empty

    movzx   eax, byte [key_buffer + ebx]
    inc     ebx
    and     ebx, 0xFF           ; wrap 256-byte buffer
    mov     [key_buf_head], ebx

    pop     ebx
    ret

.empty:
    xor     eax, eax
    pop     ebx
    ret

; ==============================================================
; IRQ1 Handler — invoked on each PS/2 keyboard event
; ==============================================================
irq1_keyboard_handler:
    pushad
    push_segs
    set_kernel_segs

    in      al, KBD_DATA_PORT   ; read scancode

    ; ---- Check for break code (key release) -----------------
    test    al, SC_BREAK
    jnz     .release

    ; ---- Handle modifier make codes -------------------------
    cmp     al, SC_LSHIFT
    je      .set_shift
    cmp     al, SC_RSHIFT
    je      .set_shift
    cmp     al, SC_CTRL
    je      .set_ctrl
    cmp     al, SC_ALT
    je      .set_alt
    cmp     al, SC_CAPS
    je      .toggle_caps

    ; ---- Translate scancode to ASCII ------------------------
    call    kbd_translate       ; AL = scancode in, AL = ASCII out
    test    al, al
    jz      .eoi                ; untranslatable — discard

    ; ---- Push ASCII into ring buffer ------------------------
    call    kbd_buf_write

    jmp     .eoi

.set_shift:
    or      byte [key_modifiers], KM_SHIFT
    jmp     .eoi

.set_ctrl:
    or      byte [key_modifiers], KM_CTRL
    jmp     .eoi

.set_alt:
    or      byte [key_modifiers], KM_ALT
    jmp     .eoi

.toggle_caps:
    xor     byte [key_modifiers], KM_CAPSLOCK
    jmp     .eoi

    ; ---- Key release: clear modifier bits if applicable -----
.release:
    and     al, not SC_BREAK    ; strip break bit
    cmp     al, SC_LSHIFT
    je      .clr_shift
    cmp     al, SC_RSHIFT
    je      .clr_shift
    cmp     al, SC_CTRL
    je      .clr_ctrl
    cmp     al, SC_ALT
    je      .clr_alt
    jmp     .eoi

.clr_shift:
    and     byte [key_modifiers], not KM_SHIFT
    jmp     .eoi
.clr_ctrl:
    and     byte [key_modifiers], not KM_CTRL
    jmp     .eoi
.clr_alt:
    and     byte [key_modifiers], not KM_ALT
    jmp     .eoi

.eoi:
    eoi_master
    pop_segs
    popad
    iret

; ==============================================================
; kbd_translate — scancode set 1 → ASCII
; Input:  AL = scancode (make code, no break bit)
; Output: AL = ASCII character, 0 if not translatable
; ==============================================================
kbd_translate:
    ; EBX = table index, ECX = modifier flags (keep EAX clean for return)
    push    ebx
    push    ecx

    ; Scancodes 1-57 are mapped (57 = Space); outside that range → 0
    cmp     al, 1
    jl      .no_translate
    cmp     al, 57
    jg      .no_translate

    movzx   ebx, al
    dec     ebx                     ; 0-indexed table offset

    movzx   ecx, byte [key_modifiers]

    test    ecx, KM_SHIFT
    jnz     .use_shift

    ; No Shift — check CapsLock (affects letters only)
    test    ecx, KM_CAPSLOCK
    jz      .use_normal

    ; CapsLock active: look up, then uppercase if letter
    movzx   eax, byte [kbd_table_normal + ebx]
    cmp     al, 'a'
    jl      .done_translate
    cmp     al, 'z'
    jg      .done_translate
    sub     al, 0x20                ; a-z → A-Z
    jmp     .done_translate

.use_normal:
    movzx   eax, byte [kbd_table_normal + ebx]
    jmp     .done_translate

.use_shift:
    movzx   eax, byte [kbd_table_shift + ebx]

.done_translate:
    pop     ecx
    pop     ebx
    ret

.no_translate:
    xor     eax, eax
    pop     ecx
    pop     ebx
    ret

; ==============================================================
; kbd_buf_write — write AL to ring buffer (overwrites on overflow)
; ==============================================================
kbd_buf_write:
    push    ebx
    mov     ebx, [key_buf_tail]
    mov     [key_buffer + ebx], al
    inc     ebx
    and     ebx, 0xFF
    mov     [key_buf_tail], ebx
    pop     ebx
    ret

; ==============================================================
; Scancode Set 1 → ASCII tables (index = scancode - 1)
; 0x00 = untranslatable / special key
; ==============================================================
kbd_table_normal:
;         SC  1     2     3     4     5     6     7     8     9    10    11    12    13    14    15
    db 0x1B, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 0x08, 0x09, 'q'
;         16    17    18    19    20    21    22    23    24    25    26    27    28    29    30    31
    db 'w',  'e',  'r',  't',  'y',  'u',  'i',  'o',  'p',  '[',  ']',  0x0D, 0x00, 'a',  's',  'd'
;         32    33    34    35    36    37    38    39    40    41    42    43    44    45    46    47
    db 'f',  'g',  'h',  'j',  'k',  'l',  ';',  0x27, '`',  0x00, '\',  'z',  'x',  'c',  'v',  'b'
;         48    49    50    51    52    53    54(RShift) 55(Num*) 56(LAlt) 57(Space)
    db 'n',  'm',  ',',  '.',  '/',  0x00, 0x00,    '*',     0x00,    ' '

kbd_table_shift:
;         SC  1     2     3     4     5     6     7     8     9    10    11    12    13    14    15
    db 0x1B, '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', 0x08, 0x09, 'Q'
;         16    17    18    19    20    21    22    23    24    25    26    27    28    29    30    31
    db 'W',  'E',  'R',  'T',  'Y',  'U',  'I',  'O',  'P',  '{',  '}',  0x0D, 0x00, 'A',  'S',  'D'
;         32    33    34    35    36    37    38    39    40    41    42    43    44    45    46    47
    db 'F',  'G',  'H',  'J',  'K',  'L',  ':',  '"',  '~',  0x00, '|',  'Z',  'X',  'C',  'V',  'B'
;         48    49    50    51    52    53    54(RShift) 55(Num*) 56(LAlt) 57(Space)
    db 'N',  'M',  '<',  '>',  '?',  0x00, 0x00,    '*',     0x00,    ' '

; ==============================================================
; Driver State
; ==============================================================
key_modifiers   db 0            ; current modifier bitmask

; 256-byte circular ring buffer
key_buffer      rb 256
key_buf_head    dd 0            ; dequeue index
key_buf_tail    dd 0            ; enqueue index
