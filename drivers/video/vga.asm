; =============================================================
; ProbablyFineOS — VGA Text Mode Driver  (80×25, Mode 3)
; Included into kernel/kernel.asm
;
; Public API:
;   vga_init        — clear screen, set default colour, home cursor
;   vga_clear       — fill screen with spaces (current colour)
;   vga_putc        — write char in AL at cursor, advance cursor
;   vga_puts        — print null-terminated string (cdecl: push ptr, call)
;   vga_set_color   — set attribute byte (AH = new attribute)
;   vga_set_cursor  — move cursor (DH = row, DL = col)
;   vga_scroll      — scroll text area up one line
; =============================================================

; ---- Private state ------------------------------------------
vga_col    db 0             ; current cursor column (0-79)
vga_row    db 0             ; current cursor row    (0-24)
vga_attr   db VGA_DEFAULT_ATTR   ; current text attribute

; ==============================================================
; vga_init — initialise driver, clear screen
; ==============================================================
vga_init:
    mov     byte [vga_col],  0
    mov     byte [vga_row],  0
    mov     byte [vga_attr], VGA_DEFAULT_ATTR
    call    vga_clear
    ret

; ==============================================================
; vga_clear — fill text buffer with spaces using current attr
; ==============================================================
vga_clear:
    push    eax
    push    ecx
    push    edi

    mov     edi, VGA_TEXT_BASE
    movzx   eax, byte [vga_attr]
    shl     eax, 8
    or      al, 0x20            ; space character
    ; AX = (attr << 8) | 0x20 — one VGA cell
    mov     ah, al              ; duplicate for dword fill
    ; EAX = AX repeated: build word then duplicate
    movzx   eax, ax
    mov     ecx, eax
    shl     ecx, 16
    or      eax, ecx            ; EAX = two identical cells
    mov     ecx, VGA_SIZE / 2   ; 2000 cells / 2 = 1000 dwords
    rep     stosd

    pop     edi
    pop     ecx
    pop     eax
    ret

; ==============================================================
; vga_putc — output one character
; Input: AL = ASCII character
; Clobbers: none (pushes/pops all used registers)
; ==============================================================
vga_putc:
    push    eax
    push    ebx
    push    ecx
    push    edi

    cmp     al, 0x0A            ; newline?
    je      .newline
    cmp     al, 0x0D            ; carriage return?
    je      .cr
    cmp     al, 0x08            ; backspace?
    je      .backspace

    ; ---- Print printable character --------------------------
    call    .calc_offset        ; EDI = byte offset in VGA buffer
    mov     ah, [vga_attr]
    mov     [VGA_TEXT_BASE + edi], ax   ; write char + attr

    ; Advance column
    movzx   ecx, byte [vga_col]
    inc     ecx
    cmp     ecx, VGA_COLS
    jl      .store_col
    ; Column wrapped to 80 — reset to 0 BEFORE calling .next_row
    ; because .next_row uses ecx internally (overwrites it with row value)
    mov     byte [vga_col], 0
    call    .next_row
    jmp     .update_hw
.store_col:
    mov     [vga_col], cl
    jmp     .update_hw

.newline:
    mov     byte [vga_col], 0
    call    .next_row
    jmp     .update_hw

.cr:
    mov     byte [vga_col], 0
    jmp     .update_hw

.backspace:
    movzx   ecx, byte [vga_col]
    test    ecx, ecx
    jz      .update_hw          ; already at column 0
    dec     ecx
    mov     [vga_col], cl
    ; overwrite character with space
    call    .calc_offset
    mov     ah, [vga_attr]
    mov     al, 0x20
    mov     [VGA_TEXT_BASE + edi], ax
    jmp     .update_hw

.update_hw:
    call    .hw_cursor
    pop     edi
    pop     ecx
    pop     ebx
    pop     eax
    ret

; ---- Private: move to next row, scroll if needed ------
.next_row:
    movzx   ecx, byte [vga_row]
    inc     ecx
    cmp     ecx, VGA_ROWS
    jl      .store_row
    ; at last row — scroll
    call    vga_scroll
    mov     ecx, VGA_ROWS - 1
.store_row:
    mov     [vga_row], cl
    ret

; ---- Private: compute EDI = (row*80 + col)*2 ----------
.calc_offset:
    movzx   edi, byte [vga_row]
    imul    edi, edi, VGA_COLS
    movzx   ecx, byte [vga_col]
    add     edi, ecx
    shl     edi, 1              ; × 2 (each cell = 2 bytes)
    ret

; ---- Private: update hardware cursor via CRTC ---------
.hw_cursor:
    push    eax
    push    edx
    movzx   eax, byte [vga_row]
    imul    eax, eax, VGA_COLS
    movzx   edx, byte [vga_col]
    add     eax, edx            ; linear position
    ; High byte
    mov     dx, VGA_CRTC_ADDR
    mov     al, 0x0E
    out     dx, al
    mov     dx, VGA_CRTC_DATA
    mov     eax, eax
    movzx   eax, byte [vga_row]
    imul    eax, eax, VGA_COLS
    movzx   edx, byte [vga_col]
    add     eax, edx
    mov     ebx, eax
    shr     eax, 8
    mov     dx, VGA_CRTC_DATA
    out     dx, al
    ; Low byte
    mov     dx, VGA_CRTC_ADDR
    mov     al, 0x0F
    out     dx, al
    mov     dx, VGA_CRTC_DATA
    mov     al, bl
    out     dx, al
    pop     edx
    pop     eax
    ret

; ==============================================================
; vga_scroll — scroll text buffer up by 1 row
; Bottom row is filled with spaces.
; ==============================================================
vga_scroll:
    push    eax
    push    ecx
    push    edi
    push    esi

    ; Copy rows 1-24 → rows 0-23 (memmove upward)
    mov     esi, VGA_TEXT_BASE + VGA_COLS * 2  ; source: row 1
    mov     edi, VGA_TEXT_BASE                  ; dest: row 0
    mov     ecx, (VGA_ROWS - 1) * VGA_COLS     ; cells to move
    rep     movsw

    ; Clear last row with spaces + current attribute
    movzx   eax, byte [vga_attr]
    shl     eax, 8
    or      al, 0x20
    mov     ecx, VGA_COLS
    rep     stosw

    pop     esi
    pop     edi
    pop     ecx
    pop     eax
    ret

; ==============================================================
; vga_puts — print null-terminated string
; Calling convention: cdecl — push string pointer, call, add esp,4
; ==============================================================
vga_puts:
    push    ebp
    mov     ebp, esp
    push    esi

    mov     esi, [ebp + 8]      ; string pointer argument
.loop:
    lodsb
    test    al, al
    jz      .done
    call    vga_putc
    jmp     .loop
.done:
    pop     esi
    pop     ebp
    ret

; ==============================================================
; vga_set_color — change text attribute
; Input: AL = attribute byte  (fg | bg<<4)
; ==============================================================
vga_set_color:
    mov     [vga_attr], al
    ret

; ==============================================================
; vga_set_cursor — move cursor to given row/column
; Input: DH = row (0-24), DL = col (0-79)
; ==============================================================
vga_set_cursor:
    mov     [vga_row], dh
    mov     [vga_col], dl
    call    vga_putc.hw_cursor
    ret

; ==============================================================
; vga_print_hex — print EAX as 8 hex digits (debug helper)
; ==============================================================
vga_print_hex:
    push    eax
    push    ecx
    push    edx
    mov     ecx, 8
    mov     edx, eax
.hex_loop:
    rol     edx, 4
    mov     al, dl
    and     al, 0x0F
    cmp     al, 10
    jl      .digit
    add     al, 'A' - 10
    jmp     .emit
.digit:
    add     al, '0'
.emit:
    call    vga_putc
    loop    .hex_loop
    pop     edx
    pop     ecx
    pop     eax
    ret

; ==============================================================
; vga_print_dec — print EAX as decimal (unsigned, no leading zeros)
; ==============================================================
vga_print_dec:
    push    eax
    push    ebx
    push    ecx
    push    edx

    mov     ecx, 0              ; digit counter
    mov     ebx, 10
    test    eax, eax
    jnz     .divide
    ; special case: zero
    mov     al, '0'
    call    vga_putc
    jmp     .done_dec

.divide:
    test    eax, eax
    jz      .print_digits
    xor     edx, edx
    div     ebx
    push    edx                 ; save remainder (digit)
    inc     ecx
    jmp     .divide

.print_digits:
    test    ecx, ecx
    jz      .done_dec
    pop     edx
    mov     al, dl
    add     al, '0'
    call    vga_putc
    dec     ecx
    jmp     .print_digits

.done_dec:
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret
