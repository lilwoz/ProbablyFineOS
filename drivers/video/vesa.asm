; =============================================================
; ProbablyFineOS — VESA Linear Framebuffer Driver  (800×600×32bpp)
; Included into kernel/kernel.asm
;
; The VESA mode is SET by Stage 2 (real mode, BIOS INT 10h).
; Stage 2 saves the VBE Mode Info Block at VESA_INFO_ADDR.
; This driver reads the framebuffer base address from that block
; and provides pixel / rectangle / text drawing primitives.
;
; Public API:
;   vesa_init       — read fb base from saved VBE info block
;   vesa_clear      — fill framebuffer with 32-bit BGRA colour
;   vesa_put_pixel  — draw one pixel at (x, y)
;   vesa_fill_rect  — fill axis-aligned rectangle
;   vesa_puts       — render null-terminated string with bitmap font
; =============================================================

; ---- Private state ------------------------------------------
vesa_fb_base    dd 0        ; physical base of linear framebuffer
vesa_pitch      dd 0        ; bytes per scan line
vesa_gfx_x      dd 0        ; graphics text cursor X (pixels)
vesa_gfx_y      dd 0        ; graphics text cursor Y (pixels)
vesa_fg_color   dd 0x00FFFFFF  ; foreground colour (BGRA: B G R 00)
vesa_bg_color   dd 0x00000000  ; background colour

; ==============================================================
; vesa_init — read framebuffer info from VBE block saved by stage2
; Call only when VESA_ENABLE = 1; safe to call anyway (nops if fb=0)
; ==============================================================
vesa_init:
    ; VBE Mode Info Block was saved at VESA_INFO_ADDR by Stage 2
    ; PhysBasePtr is at offset VBE_PhysBasePtr (40) in the block
    mov     eax, [VESA_INFO_ADDR + VBE_PhysBasePtr]
    mov     [vesa_fb_base], eax

    ; Bytes-per-line is at offset VBE_LinBytesPerLine (16)
    movzx   eax, word [VESA_INFO_ADDR + VBE_LinBytesPerLine]
    mov     [vesa_pitch], eax

    ; Home the graphics cursor
    mov     dword [vesa_gfx_x], 0
    mov     dword [vesa_gfx_y], 0
    ret

; ==============================================================
; vesa_clear — fill entire framebuffer with one colour
; Input: EAX = 32-bit BGRA colour
; ==============================================================
vesa_clear:
    push    ecx
    push    edi

    mov     edi, [vesa_fb_base]
    mov     ecx, VESA_WIDTH * VESA_HEIGHT
    rep     stosd               ; write EAX to every pixel (stosd uses EAX)

    pop     edi
    pop     ecx
    ret

; ==============================================================
; vesa_put_pixel — draw one pixel
; Input: EBX = x, ECX = y, EAX = 32-bit colour
; Clobbers: EDI, EDX
; ==============================================================
vesa_put_pixel:
    push    edi
    push    edx

    ; bounds check
    cmp     ebx, VESA_WIDTH
    jge     .skip
    cmp     ecx, VESA_HEIGHT
    jge     .skip

    ; offset = y * pitch + x * 4
    mov     edi, [vesa_fb_base]
    mov     edx, ecx
    imul    edx, [vesa_pitch]
    add     edi, edx
    lea     edi, [edi + ebx * 4]
    mov     [edi], eax

.skip:
    pop     edx
    pop     edi
    ret

; ==============================================================
; vesa_fill_rect — fill rectangle with solid colour
; Input: EAX=colour, EBX=x, ECX=y, ESI=width, EDI=height
; Clobbers: none (full save/restore)
; ==============================================================
vesa_fill_rect:
    push    eax
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi
    push    ebp

    mov     ebp, edi            ; save height
    ; row loop
.row:
    test    ebp, ebp
    jz      .done_rect
    push    ecx                 ; save current y
    push    ebx                 ; save x
    push    esi                 ; save width
    ; draw one horizontal span
    mov     edx, esi            ; pixel count = width
.col:
    test    edx, edx
    jz      .next_row
    call    vesa_put_pixel      ; eax=colour, ebx=x, ecx=y
    inc     ebx
    dec     edx
    jmp     .col
.next_row:
    pop     esi
    pop     ebx
    pop     ecx
    inc     ecx                 ; next row
    dec     ebp
    jmp     .row

.done_rect:
    pop     ebp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret

; ==============================================================
; vesa_puts — render null-terminated ASCII string using 8×16 font
; Input: ESI = pointer to string
; Uses vesa_gfx_x/y for position, vesa_fg_color / vesa_bg_color
; ==============================================================
vesa_puts:
    push    eax
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi

.char_loop:
    lodsb                       ; AL = next character
    test    al, al
    jz      .done_puts

    cmp     al, 0x0A            ; newline
    je      .newline_gfx
    cmp     al, 0x0D
    je      .cr_gfx

    ; render glyph: 8 columns × 16 rows
    sub     al, 0x20            ; font_data starts at 0x20
    jl      .skip_char          ; below space — skip
    cmp     al, 0x5E            ; above '~' — skip
    jg      .skip_char

    movzx   eax, al
    imul    eax, eax, FONT_HEIGHT   ; byte offset = char_idx * 16
    add     eax, font_data           ; EAX → first row byte of glyph
    mov     edx, eax                 ; EDX = glyph pointer

    mov     edi, FONT_HEIGHT
.row_loop:
    test    edi, edi
    jz      .next_char
    mov     al, [edx]           ; one row of 8 pixels
    inc     edx
    push    ecx                 ; save col counter
    mov     ecx, FONT_WIDTH
.pixel_loop:
    test    ecx, ecx
    jz      .end_pixel
    test    al, 0x80            ; MSB = leftmost pixel
    jz      .bg_pixel
    ; foreground pixel
    push    eax
    push    ebx
    push    ecx
    mov     eax, [vesa_fg_color]
    mov     ebx, [vesa_gfx_x]
    add     ebx, FONT_WIDTH
    sub     ebx, ecx
    mov     ecx, [vesa_gfx_y]
    add     ecx, FONT_HEIGHT
    sub     ecx, edi
    call    vesa_put_pixel
    pop     ecx
    pop     ebx
    pop     eax
    jmp     .bg_pixel_done
.bg_pixel:
    push    eax
    push    ebx
    push    ecx
    mov     eax, [vesa_bg_color]
    mov     ebx, [vesa_gfx_x]
    add     ebx, FONT_WIDTH
    sub     ebx, ecx
    mov     ecx, [vesa_gfx_y]
    add     ecx, FONT_HEIGHT
    sub     ecx, edi
    call    vesa_put_pixel
    pop     ecx
    pop     ebx
    pop     eax
.bg_pixel_done:
    shl     al, 1
    dec     ecx
    jmp     .pixel_loop
.end_pixel:
    pop     ecx
    dec     edi
    jmp     .row_loop

.next_char:
    add     dword [vesa_gfx_x], FONT_WIDTH
    ; wrap line
    mov     eax, [vesa_gfx_x]
    cmp     eax, VESA_WIDTH - FONT_WIDTH
    jle     .char_loop
.newline_gfx:
    mov     dword [vesa_gfx_x], 0
    add     dword [vesa_gfx_y], FONT_HEIGHT
    jmp     .char_loop
.cr_gfx:
    mov     dword [vesa_gfx_x], 0
    jmp     .char_loop
.skip_char:
    add     dword [vesa_gfx_x], FONT_WIDTH
    jmp     .char_loop

.done_puts:
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret

; Embed font data
include 'font.inc'
