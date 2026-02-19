; =============================================================================
; SimpleOS Kernel - VESA 640x480x256
; A simple operating system with GUI, file system, and text editor
; =============================================================================

org 0x1000
use16

; =============================================================================
; CONSTANTS
; =============================================================================

; Screen dimensions (VESA mode 0x101)
SCREEN_WIDTH    equ 640
SCREEN_HEIGHT   equ 480
VGA_MEMORY      equ 0xA000

; Colors (VGA palette)
COLOR_BLACK         equ 0
COLOR_BLUE          equ 1
COLOR_GREEN         equ 2
COLOR_CYAN          equ 3
COLOR_RED           equ 4
COLOR_MAGENTA       equ 5
COLOR_BROWN         equ 6
COLOR_LIGHT_GRAY    equ 7
COLOR_DARK_GRAY     equ 8
COLOR_LIGHT_BLUE    equ 9
COLOR_LIGHT_GREEN   equ 10
COLOR_LIGHT_CYAN    equ 11
COLOR_LIGHT_RED     equ 12
COLOR_LIGHT_MAGENTA equ 13
COLOR_YELLOW        equ 14
COLOR_WHITE         equ 15

; Desktop colors
COLOR_DESKTOP       equ 1
COLOR_TASKBAR       equ 7
COLOR_WINDOW_BG     equ 15
COLOR_WINDOW_TITLE  equ 9
COLOR_WINDOW_BORDER equ 8
COLOR_BUTTON        equ 7
COLOR_BUTTON_TEXT   equ 0
COLOR_ICON_BG       equ 1

; UI dimensions
TASKBAR_HEIGHT  equ 40
ICON_SIZE       equ 64
ICON_SPACING    equ 100

; Window states
WIN_CLOSED      equ 0
WIN_OPEN        equ 1
WIN_MINIMIZED   equ 2

; File system constants
MAX_FILES       equ 16
FILENAME_LEN    equ 12
FILE_CONTENT_SIZE equ 512
FS_ENTRY_SIZE   equ FILENAME_LEN + 2 + FILE_CONTENT_SIZE

; Mouse button states
MOUSE_LEFT      equ 1
MOUSE_RIGHT     equ 2

; =============================================================================
; KERNEL ENTRY POINT
; =============================================================================

kernel_start:
    ; Set up data segment (DL has boot drive from bootloader)
    mov ax, 0
    mov ds, ax
    mov [boot_drive], dl    ; Save boot drive before anything clobbers DL
    cld                     ; Clear direction flag for REP STOSB

    ; Set VESA mode 640x480x256 (mode 0x101)
    mov ax, 0x4F02
    mov bx, 0x0101
    int 0x10
    cmp ax, 0x004F
    jne vesa_fail

    ; Set up VGA segment
    mov ax, VGA_MEMORY
    mov es, ax

    ; Initialize bank tracking
    mov word [current_bank], 0

    ; Initialize mouse
    call mouse_init

    ; Initialize file system with sample files
    call fs_init

    ; Draw initial desktop and cursor
    call draw_desktop
    call draw_mouse_cursor

    ; Main event loop
main_loop:
    ; Save old cursor position
    mov ax, [mouse_x]
    mov [old_mouse_x], ax
    mov ax, [mouse_y]
    mov [old_mouse_y], ax

    ; --- Check mouse (updated by IRQ 12 handler) ---
    test byte [mouse_buttons], MOUSE_LEFT
    jz .mouse_released

    ; Button is down - debounce (only fire once per press)
    cmp byte [mouse_clicked], 1
    je .check_keyboard
    mov byte [mouse_clicked], 1
    call handle_click
    jmp .check_redraw

.mouse_released:
    mov byte [mouse_clicked], 0

    ; --- Check keyboard ---
.check_keyboard:
    mov ah, 1
    int 0x16
    jz .check_redraw

    ; Key available - process it
    call keyboard_handler

    ; --- Handle redraws ---
.check_redraw:
    cmp byte [need_redraw], 0
    je .check_cursor_move

    cmp byte [need_redraw], 2
    je .window_redraw

    ; Full redraw needed (need_redraw == 1)
    mov byte [need_redraw], 0
    call wait_vsync
    call draw_desktop
    call draw_mouse_cursor
    jmp .loop_end

.window_redraw:
    ; Window content redraw only (need_redraw == 2)
    mov byte [need_redraw], 0
    call wait_vsync
    call draw_windows
    call draw_mouse_cursor
    jmp .loop_end

.check_cursor_move:
    ; Check if cursor actually moved
    mov ax, [mouse_x]
    cmp ax, [old_mouse_x]
    jne .move_cursor
    mov ax, [mouse_y]
    cmp ax, [old_mouse_y]
    je .loop_end

.move_cursor:
    call wait_vsync
    call erase_old_cursor
    call draw_mouse_cursor

.loop_end:
    jmp main_loop

; VESA mode set failed - display error and halt
vesa_fail:
    mov si, str_vesa_fail
.vf_print:
    lodsb
    test al, al
    jz .vf_halt
    mov ah, 0x0E
    int 0x10
    jmp .vf_print
.vf_halt:
    jmp $

str_vesa_fail db 'VESA mode 0x101 not supported!', 0

old_mouse_x dw 320
old_mouse_y dw 240
need_redraw db 0
current_bank dw 0

; -----------------------------------------------------------------------------
; Erase cursor at old position using XOR (restores original pixels)
; -----------------------------------------------------------------------------
erase_old_cursor:
    pusha
    mov cx, [old_mouse_x]
    mov dx, [old_mouse_y]
    call draw_xor_cursor
    popa
    ret

; -----------------------------------------------------------------------------
; Wait for vertical retrace (reduces flicker)
; -----------------------------------------------------------------------------
wait_vsync:
    push ax
    push dx
    mov dx, 0x3DA
.wait1:
    in al, dx
    test al, 8
    jnz .wait1
.wait2:
    in al, dx
    test al, 8
    jz .wait2
    pop dx
    pop ax
    ret

; =============================================================================
; VESA BANK-SWITCHED GRAPHICS ROUTINES
; =============================================================================

; -----------------------------------------------------------------------------
; Switch VESA bank if needed
; Input: DX = desired bank number
; Clobbers: AX, BX (caller must save if needed)
; -----------------------------------------------------------------------------
switch_bank:
    cmp dx, [current_bank]
    je .done
    mov [current_bank], dx
    push ax
    push bx
    mov ax, 0x4F05
    xor bx, bx             ; BH=0 (set), BL=0 (window A)
    int 0x10
    pop bx
    pop ax
.done:
    ret

; -----------------------------------------------------------------------------
; Put pixel at (CX, DX) with color AL
; Uses bank switching for VESA 640x480
; -----------------------------------------------------------------------------
put_pixel:
    pusha
    mov [.color], al

    ; Calculate 32-bit offset: y * 640 + x
    mov ax, dx              ; AX = y
    mov bx, SCREEN_WIDTH
    mul bx                  ; DX:AX = y * 640
    add ax, cx              ; add x
    adc dx, 0               ; carry into bank

    ; DX = bank number, AX = offset within 64KB window
    call switch_bank

    mov di, ax
    mov al, [.color]
    mov [es:di], al
    popa
    ret

.color  db 0

; -----------------------------------------------------------------------------
; Draw filled rectangle (optimized with REP STOSB + bank handling)
; Input: CX=x, DX=y, SI=width, BP=height, AL=color
; -----------------------------------------------------------------------------
draw_rect:
    pusha
    mov [.color], al
    mov [.x], cx
    mov [.width], si
    mov [.rows_left], bp
    mov [.cur_y], dx

.row_loop:
    cmp word [.rows_left], 0
    je .done

    ; Bounds check Y
    mov ax, [.cur_y]
    cmp ax, SCREEN_HEIGHT
    jge .done

    ; Calculate row start offset: cur_y * 640 + x
    mov ax, [.cur_y]
    mov bx, SCREEN_WIDTH
    mul bx                  ; DX:AX = y * 640
    add ax, [.x]
    adc dx, 0

    ; Switch bank if needed
    call switch_bank

    mov di, ax
    mov cx, [.width]

    ; Clamp width to screen edge
    mov ax, [.x]
    add ax, cx
    cmp ax, SCREEN_WIDTH
    jle .no_clamp
    mov cx, SCREEN_WIDTH
    sub cx, [.x]
    cmp cx, 0
    jle .next_row
.no_clamp:

    ; Check if row crosses 64KB bank boundary
    mov ax, di
    add ax, cx
    jc .split_row

    ; No split - fill entire row
    mov al, [.color]
    rep stosb
    jmp .next_row

.split_row:
    ; First part: fill up to bank boundary
    mov bx, cx             ; save total count
    xor cx, cx
    sub cx, di             ; cx = 65536 - di = bytes until boundary
    sub bx, cx             ; bx = remaining bytes
    mov [.remain], bx

    mov al, [.color]
    rep stosb

    ; Switch to next bank
    inc word [current_bank]
    mov dx, [current_bank]
    mov ax, 0x4F05
    xor bx, bx
    int 0x10

    ; Fill remaining in new bank
    xor di, di
    mov cx, [.remain]
    mov al, [.color]
    rep stosb

.next_row:
    inc word [.cur_y]
    dec word [.rows_left]
    jmp .row_loop

.done:
    popa
    ret

.color      db 0
.x          dw 0
.width      dw 0
.rows_left  dw 0
.cur_y      dw 0
.remain     dw 0

; -----------------------------------------------------------------------------
; Draw horizontal line (optimized with REP STOSB + bank handling)
; Input: CX=x, DX=y, SI=length, AL=color
; -----------------------------------------------------------------------------
draw_hline:
    pusha
    mov [.color], al
    mov [.len], si

    ; Bounds check
    cmp dx, SCREEN_HEIGHT
    jge .done

    ; Calculate offset: y * 640 + x
    mov ax, dx
    mov bx, SCREEN_WIDTH
    mul bx                  ; DX:AX = y * 640
    add ax, cx
    adc dx, 0

    ; Switch bank if needed
    call switch_bank

    mov di, ax
    mov cx, [.len]
    mov al, [.color]

    ; Check if line crosses bank boundary
    mov bx, di
    add bx, cx
    jc .split

    ; No split
    rep stosb
    jmp .done

.split:
    ; First part
    mov bx, cx
    xor cx, cx
    sub cx, di             ; cx = bytes until boundary
    sub bx, cx
    mov [.remain], bx

    rep stosb

    ; Switch to next bank
    inc word [current_bank]
    mov dx, [current_bank]
    mov ax, 0x4F05
    xor bx, bx
    int 0x10

    xor di, di
    mov cx, [.remain]
    mov al, [.color]
    rep stosb

.done:
    popa
    ret

.color  db 0
.len    dw 0
.remain dw 0

; -----------------------------------------------------------------------------
; Draw vertical line
; Input: CX=x, DX=y, SI=length, AL=color
; -----------------------------------------------------------------------------
draw_vline:
    pusha
.loop:
    cmp si, 0
    je .done
    cmp dx, SCREEN_HEIGHT
    jge .done
    call put_pixel
    inc dx
    dec si
    jmp .loop
.done:
    popa
    ret

; -----------------------------------------------------------------------------
; Draw character at (CX, DX) with color AL
; BL = character
; -----------------------------------------------------------------------------
draw_char:
    pusha
    mov [.color], al
    mov [.char], bl
    mov [.start_x], cx

    ; Get character bitmap pointer
    xor bh, bh
    mov bl, [.char]
    sub bl, 32
    shl bx, 3
    add bx, font_data

    mov si, 8
.row_loop:
    mov al, [bx]
    mov [.row_data], al
    mov cx, [.start_x]

    mov di, 8
.col_loop:
    mov al, [.row_data]
    test al, 0x80
    jz .skip_pixel

    mov al, [.color]
    call put_pixel

.skip_pixel:
    shl byte [.row_data], 1
    inc cx
    dec di
    jnz .col_loop

    inc bx
    inc dx
    dec si
    jnz .row_loop

    popa
    ret

.color      db 0
.char       db 0
.start_x    dw 0
.row_data   db 0

; -----------------------------------------------------------------------------
; Draw string at (CX, DX) with color AL
; SI = pointer to null-terminated string
; -----------------------------------------------------------------------------
draw_string:
    pusha
    mov [.color], al

.loop:
    mov bl, [si]
    test bl, bl
    jz .done

    mov al, [.color]
    call draw_char

    add cx, 8
    inc si
    jmp .loop

.done:
    popa
    ret

.color db 0

; =============================================================================
; DESKTOP AND WALLPAPER
; =============================================================================

draw_desktop:
    pusha
    call draw_wallpaper
    call draw_taskbar
    call draw_icons
    call draw_windows
    popa
    ret

; -----------------------------------------------------------------------------
; Draw decorative wallpaper pattern (gradient + diamonds + circles)
; -----------------------------------------------------------------------------
draw_wallpaper:
    pusha

    ; Setup custom palette first
    call setup_palette

    ; Fill with gradient bands (each band 32 rows, colors 16-31)
    mov word [.cur_y], 0
    mov byte [.grad_color], 16

.gradient_loop:
    mov dx, [.cur_y]
    cmp dx, SCREEN_HEIGHT - TASKBAR_HEIGHT
    jge .pattern

    ; Calculate band height
    mov bp, 32
    mov ax, dx
    add ax, bp
    cmp ax, SCREEN_HEIGHT - TASKBAR_HEIGHT
    jle .no_clamp
    mov bp, SCREEN_HEIGHT - TASKBAR_HEIGHT
    sub bp, dx
.no_clamp:

    xor cx, cx
    mov si, SCREEN_WIDTH
    mov al, [.grad_color]
    call draw_rect

    add word [.cur_y], 32
    cmp byte [.grad_color], 31
    jge .gradient_loop
    inc byte [.grad_color]
    jmp .gradient_loop

.pattern:
    ; Draw diamond pattern overlay (doubled spacing: 80x60)
    mov dx, 20
.diamond_y:
    cmp dx, SCREEN_HEIGHT - TASKBAR_HEIGHT - 20
    jge .circles

    mov cx, 20
.diamond_x:
    cmp cx, SCREEN_WIDTH - 20
    jge .next_diamond_row

    ; Draw small diamond at grid intersections
    push cx
    push dx

    mov al, 23
    call put_pixel

    dec cx
    call put_pixel
    add cx, 2
    call put_pixel
    dec cx
    dec dx
    call put_pixel
    add dx, 2
    call put_pixel

    pop dx
    pop cx

    add cx, 80
    jmp .diamond_x

.next_diamond_row:
    add dx, 60
    jmp .diamond_y

.circles:
    ; Top-left circle
    mov cx, 60
    mov dx, 60
    mov si, 40
    mov al, 19
    call draw_circle_outline

    ; Top-right
    mov cx, 580
    mov dx, 60
    mov si, 40
    mov al, 19
    call draw_circle_outline

    ; Bottom-left
    mov cx, 60
    mov dx, 360
    mov si, 30
    mov al, 21
    call draw_circle_outline

    ; Bottom-right
    mov cx, 580
    mov dx, 360
    mov si, 30
    mov al, 21
    call draw_circle_outline

    popa
    ret

.cur_y      dw 0
.grad_color db 0

; -----------------------------------------------------------------------------
; Setup custom color palette for gradient
; -----------------------------------------------------------------------------
setup_palette:
    pusha

    mov dx, 0x3C8
    mov al, 16
    out dx, al

    mov dx, 0x3C9
    mov cx, 16

    mov bl, 0
    mov bh, 0
    mov ah, 20

.palette_loop:
    mov al, bl
    out dx, al
    mov al, bh
    out dx, al
    mov al, ah
    out dx, al

    add ah, 2
    add bh, 1

    loop .palette_loop

    popa
    ret

; -----------------------------------------------------------------------------
; Draw circle outline (midpoint circle algorithm)
; Input: CX=center_x, DX=center_y, SI=radius, AL=color
; -----------------------------------------------------------------------------
draw_circle_outline:
    pusha
    mov [.color], al
    mov [.cx], cx
    mov [.cy], dx

    mov ax, si
    mov [.x], ax
    xor bx, bx
    mov [.y], bx
    mov word [.d], 1
    sub [.d], si

.circle_loop:
    mov ax, [.x]
    cmp ax, [.y]
    jl .done

    call .draw_8_points

    inc word [.y]

    mov ax, [.d]
    test ax, ax
    jle .d_negative

    dec word [.x]
    mov ax, [.y]
    sub ax, [.x]
    shl ax, 1
    add ax, 1
    add [.d], ax
    jmp .circle_loop

.d_negative:
    mov ax, [.y]
    shl ax, 1
    add ax, 1
    add [.d], ax
    jmp .circle_loop

.done:
    popa
    ret

.draw_8_points:
    push bx
    push cx
    push dx

    mov al, [.color]

    mov cx, [.cx]
    add cx, [.x]
    mov dx, [.cy]
    add dx, [.y]
    call put_pixel

    mov cx, [.cx]
    sub cx, [.x]
    mov dx, [.cy]
    add dx, [.y]
    call put_pixel

    mov cx, [.cx]
    add cx, [.x]
    mov dx, [.cy]
    sub dx, [.y]
    call put_pixel

    mov cx, [.cx]
    sub cx, [.x]
    mov dx, [.cy]
    sub dx, [.y]
    call put_pixel

    mov cx, [.cx]
    add cx, [.y]
    mov dx, [.cy]
    add dx, [.x]
    call put_pixel

    mov cx, [.cx]
    sub cx, [.y]
    mov dx, [.cy]
    add dx, [.x]
    call put_pixel

    mov cx, [.cx]
    add cx, [.y]
    mov dx, [.cy]
    sub dx, [.x]
    call put_pixel

    mov cx, [.cx]
    sub cx, [.y]
    mov dx, [.cy]
    sub dx, [.x]
    call put_pixel

    pop dx
    pop cx
    pop bx
    ret

.color  db 0
.cx     dw 0
.cy     dw 0
.x      dw 0
.y      dw 0
.d      dw 0

; =============================================================================
; TASKBAR (doubled dimensions)
; =============================================================================

draw_taskbar:
    pusha

    ; Taskbar background
    xor cx, cx
    mov dx, SCREEN_HEIGHT - TASKBAR_HEIGHT
    mov si, SCREEN_WIDTH
    mov bp, TASKBAR_HEIGHT
    mov al, COLOR_TASKBAR
    call draw_rect

    ; Taskbar top border (3D effect)
    xor cx, cx
    mov dx, SCREEN_HEIGHT - TASKBAR_HEIGHT
    mov si, SCREEN_WIDTH
    mov al, COLOR_WHITE
    call draw_hline

    ; "Start" button (80x32)
    mov cx, 4
    mov dx, SCREEN_HEIGHT - TASKBAR_HEIGHT + 4
    mov si, 80
    mov bp, 32
    mov al, COLOR_BUTTON
    call draw_rect

    ; Button highlight
    mov cx, 4
    mov dx, SCREEN_HEIGHT - TASKBAR_HEIGHT + 4
    mov si, 80
    mov al, COLOR_WHITE
    call draw_hline
    mov cx, 4
    mov dx, SCREEN_HEIGHT - TASKBAR_HEIGHT + 4
    mov si, 32
    call draw_vline

    ; Button shadow
    mov cx, 84
    mov dx, SCREEN_HEIGHT - TASKBAR_HEIGHT + 4
    mov si, 32
    mov al, COLOR_DARK_GRAY
    call draw_vline
    mov cx, 4
    mov dx, SCREEN_HEIGHT - TASKBAR_HEIGHT + 35
    mov si, 81
    call draw_hline

    ; "Start" text (centered in 80x32 button)
    mov cx, 24
    mov dx, SCREEN_HEIGHT - TASKBAR_HEIGHT + 16
    mov si, str_start
    mov al, COLOR_BLACK
    call draw_string

    ; Clock area (96x32)
    mov cx, SCREEN_WIDTH - 100
    mov dx, SCREEN_HEIGHT - TASKBAR_HEIGHT + 4
    mov si, 96
    mov bp, 32
    mov al, COLOR_BUTTON
    call draw_rect

    ; Clock text
    mov cx, SCREEN_WIDTH - 92
    mov dx, SCREEN_HEIGHT - TASKBAR_HEIGHT + 16
    mov si, str_clock
    mov al, COLOR_BLACK
    call draw_string

    popa
    ret

str_start   db 'Start', 0
str_clock   db '12:00', 0

; =============================================================================
; DESKTOP ICONS (doubled positions and sizes)
; =============================================================================

draw_icons:
    pusha

    ; Draw "Text Editor" icon at (40, 40)
    mov cx, 40
    mov dx, 40
    call draw_editor_icon
    mov cx, 20
    mov dx, 110
    mov si, str_editor
    mov al, COLOR_WHITE
    call draw_string

    ; Draw "Files" icon at (40, 180)
    mov cx, 40
    mov dx, 180
    call draw_folder_icon
    mov cx, 28
    mov dx, 250
    mov si, str_files
    mov al, COLOR_WHITE
    call draw_string

    popa
    ret

str_editor  db 'Editor', 0
str_files   db 'Files', 0

; -----------------------------------------------------------------------------
; Draw text editor icon at (CX, DX) - doubled to 56x64
; -----------------------------------------------------------------------------
draw_editor_icon:
    pusha
    mov [.x], cx
    mov [.y], dx

    ; White page background (56x64)
    mov si, 56
    mov bp, 64
    mov al, COLOR_WHITE
    call draw_rect

    ; Page fold (top right corner, 12x12)
    mov cx, [.x]
    add cx, 44
    mov dx, [.y]
    mov si, 12
    mov bp, 12
    mov al, COLOR_LIGHT_GRAY
    call draw_rect

    ; Border
    mov cx, [.x]
    mov dx, [.y]
    mov si, 56
    mov al, COLOR_DARK_GRAY
    call draw_hline
    mov dx, [.y]
    add dx, 63
    call draw_hline
    mov cx, [.x]
    mov dx, [.y]
    mov si, 64
    call draw_vline
    mov cx, [.x]
    add cx, 55
    call draw_vline

    ; Text lines (decorative)
    mov cx, [.x]
    add cx, 8
    mov dx, [.y]
    add dx, 16
    mov si, 36
    mov al, COLOR_DARK_GRAY
    call draw_hline
    add dx, 10
    mov si, 30
    call draw_hline
    add dx, 10
    mov si, 40
    call draw_hline
    add dx, 10
    mov si, 24
    call draw_hline

    popa
    ret

.x  dw 0
.y  dw 0

; -----------------------------------------------------------------------------
; Draw folder icon at (CX, DX) - doubled to 56x56
; -----------------------------------------------------------------------------
draw_folder_icon:
    pusha
    mov [.x], cx
    mov [.y], dx

    ; Folder tab (24x12)
    mov si, 24
    mov bp, 12
    mov al, COLOR_YELLOW
    call draw_rect

    ; Folder body (56x48)
    mov cx, [.x]
    mov dx, [.y]
    add dx, 8
    mov si, 56
    mov bp, 48
    mov al, COLOR_YELLOW
    call draw_rect

    ; Folder highlight
    mov cx, [.x]
    add cx, 2
    mov dx, [.y]
    add dx, 10
    mov si, 52
    mov al, COLOR_WHITE
    call draw_hline

    ; Folder shadow/border
    mov cx, [.x]
    mov dx, [.y]
    add dx, 55
    mov si, 56
    mov al, COLOR_BROWN
    call draw_hline
    mov cx, [.x]
    add cx, 55
    mov dx, [.y]
    add dx, 8
    mov si, 48
    call draw_vline

    popa
    ret

.x  dw 0
.y  dw 0

; =============================================================================
; WINDOW MANAGER
; =============================================================================

draw_windows:
    pusha

    cmp byte [editor_state], WIN_OPEN
    jne .check_files
    call draw_editor_window

.check_files:
    cmp byte [files_state], WIN_OPEN
    jne .done
    call draw_files_window

.done:
    popa
    ret

; -----------------------------------------------------------------------------
; Draw a window frame
; Input: CX=x, DX=y, SI=width, BP=height, DI=title string
; Title bar = 32px, close button = 24x24
; -----------------------------------------------------------------------------
draw_window:
    pusha
    mov [.x], cx
    mov [.y], dx
    mov [.w], si
    mov [.h], bp
    mov [.title], di

    ; Window background
    mov al, COLOR_WINDOW_BG
    call draw_rect

    ; Title bar (32px tall)
    mov cx, [.x]
    mov dx, [.y]
    mov si, [.w]
    mov bp, 32
    mov al, COLOR_WINDOW_TITLE
    call draw_rect

    ; Title text (centered vertically in 32px bar)
    mov cx, [.x]
    add cx, 8
    mov dx, [.y]
    add dx, 12
    mov si, [.title]
    mov al, COLOR_WHITE
    call draw_string

    ; Close button (24x24)
    mov cx, [.x]
    add cx, [.w]
    sub cx, 28
    mov dx, [.y]
    add dx, 4
    mov si, 24
    mov bp, 24
    mov al, COLOR_RED
    call draw_rect

    ; X on close button
    mov cx, [.x]
    add cx, [.w]
    sub cx, 24
    mov dx, [.y]
    add dx, 12
    mov bl, 'X'
    mov al, COLOR_WHITE
    call draw_char

    ; Window border
    mov cx, [.x]
    mov dx, [.y]
    mov si, [.w]
    mov al, COLOR_WINDOW_BORDER
    call draw_hline
    mov cx, [.x]
    mov dx, [.y]
    add dx, [.h]
    dec dx
    call draw_hline
    mov cx, [.x]
    mov dx, [.y]
    mov si, [.h]
    call draw_vline
    mov cx, [.x]
    add cx, [.w]
    dec cx
    mov dx, [.y]
    call draw_vline

    popa
    ret

.x      dw 0
.y      dw 0
.w      dw 0
.h      dw 0
.title  dw 0

; =============================================================================
; TEXT EDITOR (doubled: 400x240 window)
; =============================================================================

draw_editor_window:
    pusha

    ; Draw window frame (400x240)
    mov cx, [editor_x]
    mov dx, [editor_y]
    mov si, 400
    mov bp, 240
    mov di, str_editor_title
    call draw_window

    ; Draw text area background (384x160 at +8, +40)
    mov cx, [editor_x]
    add cx, 8
    mov dx, [editor_y]
    add dx, 40
    mov si, 384
    mov bp, 160
    mov al, COLOR_WHITE
    call draw_rect

    ; Draw text area border
    mov cx, [editor_x]
    add cx, 8
    mov dx, [editor_y]
    add dx, 40
    mov si, 384
    mov al, COLOR_DARK_GRAY
    call draw_hline
    mov dx, [editor_y]
    add dx, 199
    call draw_hline
    mov cx, [editor_x]
    add cx, 8
    mov dx, [editor_y]
    add dx, 40
    mov si, 160
    call draw_vline
    mov cx, [editor_x]
    add cx, 391
    call draw_vline

    ; Draw text content
    mov cx, [editor_x]
    add cx, 16
    mov dx, [editor_y]
    add dx, 48
    mov si, editor_buffer
    mov al, COLOR_BLACK
    call draw_editor_text

    ; Draw cursor
    call draw_editor_cursor

    ; Draw "Save" button (80x24)
    mov cx, [editor_x]
    add cx, 20
    mov dx, [editor_y]
    add dx, 208
    mov si, 80
    mov bp, 24
    mov al, COLOR_BUTTON
    call draw_rect
    mov cx, [editor_x]
    add cx, 40
    mov dx, [editor_y]
    add dx, 216
    mov si, str_save
    mov al, COLOR_BLACK
    call draw_string

    ; Draw "Clear" button (88x24)
    mov cx, [editor_x]
    add cx, 120
    mov dx, [editor_y]
    add dx, 208
    mov si, 88
    mov bp, 24
    mov al, COLOR_BUTTON
    call draw_rect
    mov cx, [editor_x]
    add cx, 136
    mov dx, [editor_y]
    add dx, 216
    mov si, str_clear
    mov al, COLOR_BLACK
    call draw_string

    popa
    ret

str_editor_title    db 'Text Editor', 0
str_save            db 'Save', 0
str_clear           db 'Clear', 0

; -----------------------------------------------------------------------------
; Draw editor text with word wrap
; Input: CX=x, DX=y, SI=buffer
; Wrap at editor_x + 380, line height = 10
; -----------------------------------------------------------------------------
draw_editor_text:
    pusha
    mov [.x], cx
    mov [.start_x], cx
    mov [.y], dx

.loop:
    mov bl, [si]
    test bl, bl
    jz .done

    cmp bl, 10
    je .newline
    cmp bl, 13
    je .skip_char

    mov cx, [.x]
    mov dx, [.y]
    mov al, COLOR_BLACK
    call draw_char

    add word [.x], 8

    ; Check for wrap
    mov ax, [.x]
    mov bx, [editor_x]
    add bx, 380
    cmp ax, bx
    jl .next

.newline:
    mov ax, [.start_x]
    mov [.x], ax
    add word [.y], 10

    ; Check if past text area
    mov ax, [.y]
    mov bx, [editor_y]
    add bx, 190
    cmp ax, bx
    jge .done

.skip_char:
.next:
    inc si
    jmp .loop

.done:
    popa
    ret

.x          dw 0
.y          dw 0
.start_x    dw 0

; -----------------------------------------------------------------------------
; Draw editor cursor
; Starting position (editor_x+16, editor_y+48), wrap at editor_x+380
; -----------------------------------------------------------------------------
draw_editor_cursor:
    pusha

    mov cx, [editor_x]
    add cx, 16
    mov dx, [editor_y]
    add dx, 48

    mov si, editor_buffer
    mov bx, [editor_cursor]

.count_loop:
    test bx, bx
    jz .draw

    mov al, [si]
    test al, al
    jz .draw

    cmp al, 10
    jne .not_newline

    mov cx, [editor_x]
    add cx, 16
    add dx, 10
    jmp .next_char

.not_newline:
    add cx, 8

    ; Wrap check
    mov ax, cx
    mov di, [editor_x]
    add di, 380
    cmp ax, di
    jl .next_char
    mov cx, [editor_x]
    add cx, 16
    add dx, 10

.next_char:
    inc si
    dec bx
    jmp .count_loop

.draw:
    mov si, 10
    mov al, COLOR_BLACK
    call draw_vline

    popa
    ret

; =============================================================================
; FILE MANAGER (doubled: 360x280 window)
; =============================================================================

draw_files_window:
    pusha

    ; Draw window frame (360x280)
    mov cx, [files_x]
    mov dx, [files_y]
    mov si, 360
    mov bp, 280
    mov di, str_files_title
    call draw_window

    ; Draw file list starting at (files_x+20, files_y+44)
    mov cx, [files_x]
    add cx, 20
    mov dx, [files_y]
    add dx, 44

    xor bx, bx
.file_loop:
    cmp bx, MAX_FILES
    jge .done

    ; Check if file exists
    push bx
    call fs_get_entry
    mov al, [di]
    pop bx
    test al, al
    jz .next_file

    ; Draw file icon (24x20)
    push cx
    push dx
    push bx

    mov si, 24
    mov bp, 20
    mov al, COLOR_WHITE
    call draw_rect
    mov al, COLOR_DARK_GRAY
    call draw_hline
    add dx, 19
    call draw_hline
    sub dx, 19
    mov si, 20
    call draw_vline
    add cx, 23
    call draw_vline

    pop bx
    pop dx
    pop cx

    ; Draw filename
    push cx
    push bx
    add cx, 32
    call fs_get_entry
    mov si, di
    mov al, COLOR_BLACK
    call draw_string
    pop bx
    pop cx

.next_file:
    add dx, 28
    inc bx
    jmp .file_loop

.done:
    popa
    ret

str_files_title db 'Files', 0

; =============================================================================
; FILE SYSTEM (disk-backed, persistent across reboots)
; FS stored on floppy at LBA 49 (CHS 1/0/14), 17 sectors
; =============================================================================

; -----------------------------------------------------------------------------
; Read file system table from disk into RAM
; -----------------------------------------------------------------------------
disk_read_fs:
    pusha
    push es

    xor ax, ax
    mov es, ax              ; ES = 0 (data segment for fs_table)

    mov ah, 0x02            ; Read sectors
    mov al, 17              ; 17 sectors (covers 8416-byte fs_table)
    mov ch, 1               ; Cylinder 1
    mov cl, 14              ; Sector 14 (LBA 49)
    mov dh, 0               ; Head 0
    mov dl, [boot_drive]
    mov bx, fs_table
    int 0x13
    ; Ignore errors on read (first boot has empty sectors)

    pop es
    popa
    ret

; -----------------------------------------------------------------------------
; Write file system table from RAM to disk
; -----------------------------------------------------------------------------
disk_write_fs:
    pusha
    push es

    xor ax, ax
    mov es, ax              ; ES = 0 (data segment for fs_table)

    mov ah, 0x03            ; Write sectors
    mov al, 17              ; 17 sectors
    mov ch, 1               ; Cylinder 1
    mov cl, 14              ; Sector 14 (LBA 49)
    mov dh, 0               ; Head 0
    mov dl, [boot_drive]
    mov bx, fs_table
    int 0x13
    ; Ignore errors on write

    pop es
    popa
    ret

; -----------------------------------------------------------------------------
; Initialize file system: load from disk, create defaults on first boot
; -----------------------------------------------------------------------------
fs_init:
    pusha

    ; Load file system from disk
    call disk_read_fs

    ; Check if FS has been initialized (first filename not empty)
    cmp byte [fs_table], 0
    jne .done

    ; First boot: create sample files in RAM
    ; rep movsb writes to ES:DI, so temporarily set ES=0 (data segment)
    push es
    xor ax, ax
    mov es, ax

    mov di, fs_table
    mov si, sample_file1_name
    mov cx, FILENAME_LEN
    rep movsb
    mov word [di], 28
    add di, 2
    mov si, sample_file1_data
    mov cx, 28
    rep movsb

    mov di, fs_table + FS_ENTRY_SIZE
    mov si, sample_file2_name
    mov cx, FILENAME_LEN
    rep movsb
    mov word [di], 19
    add di, 2
    mov si, sample_file2_data
    mov cx, 19
    rep movsb

    pop es                  ; Restore ES = VGA_MEMORY

    ; Persist initial files to disk
    call disk_write_fs

.done:
    popa
    ret

sample_file1_name   db 'readme.txt', 0, 0
sample_file1_data   db 'Welcome to SimpleOS!', 13, 10, 'Enjoy!', 0

sample_file2_name   db 'notes.txt', 0, 0, 0
sample_file2_data   db 'This is a note.', 13, 10, 0

; -----------------------------------------------------------------------------
; Get file system entry pointer
; Input: BX = file index, Output: DI = pointer to entry
; -----------------------------------------------------------------------------
fs_get_entry:
    push ax
    push bx

    mov ax, FS_ENTRY_SIZE
    mul bx
    mov di, fs_table
    add di, ax

    pop bx
    pop ax
    ret

; -----------------------------------------------------------------------------
; Save editor content to file and persist to disk
; Input: BX = file index
; -----------------------------------------------------------------------------
fs_save_file:
    pusha

    call fs_get_entry

    add di, FILENAME_LEN

    mov si, editor_buffer
    xor cx, cx
.count:
    lodsb
    test al, al
    jz .copy
    inc cx
    jmp .count

.copy:
    mov [di], cx
    add di, 2

    ; rep movsb writes to ES:DI, temporarily set ES=0
    push es
    xor ax, ax
    mov es, ax

    mov si, editor_buffer
    rep movsb
    mov byte [es:di], 0

    pop es                  ; Restore ES = VGA_MEMORY

    ; Persist entire FS table to disk
    call disk_write_fs

    popa
    ret

; =============================================================================
; PS/2 MOUSE DRIVER (IRQ 12 based)
; =============================================================================

; -----------------------------------------------------------------------------
; Wait until 8042 input buffer is empty (ready to accept command)
; -----------------------------------------------------------------------------
mouse_wait_input:
    in al, 0x64
    test al, 2
    jnz mouse_wait_input
    ret

; -----------------------------------------------------------------------------
; Wait until 8042 output buffer has data (ready to read)
; -----------------------------------------------------------------------------
mouse_wait_output:
    in al, 0x64
    test al, 1
    jz mouse_wait_output
    ret

; -----------------------------------------------------------------------------
; Send command byte (in BL) to mouse via 8042 controller
; -----------------------------------------------------------------------------
mouse_send_cmd:
    call mouse_wait_input
    mov al, 0xD4            ; Tell 8042: forward next byte to mouse
    out 0x64, al
    call mouse_wait_input
    mov al, bl
    out 0x60, al
    call mouse_wait_output
    in al, 0x60             ; Read ACK (0xFA)
    ret

; -----------------------------------------------------------------------------
; Initialize PS/2 mouse
; -----------------------------------------------------------------------------
mouse_init:
    pusha
    cli

    ; Install IRQ 12 handler at INT 0x74 (DS=0, so direct IVT access)
    mov word [0x74*4], mouse_irq_handler
    mov word [0x74*4+2], 0x0000

    ; Enable auxiliary (mouse) device on 8042 controller
    call mouse_wait_input
    mov al, 0xA8
    out 0x64, al

    ; Read 8042 command byte
    call mouse_wait_input
    mov al, 0x20
    out 0x64, al
    call mouse_wait_output
    in al, 0x60
    or al, 0x02             ; Enable IRQ 12 (bit 1)
    and al, 0xDF            ; Clear "disable mouse" (bit 5)
    push ax

    ; Write 8042 command byte back
    call mouse_wait_input
    mov al, 0x60
    out 0x64, al
    call mouse_wait_input
    pop ax
    out 0x60, al

    ; Send "set defaults" command to mouse
    mov bl, 0xF6
    call mouse_send_cmd

    ; Enable mouse data reporting
    mov bl, 0xF4
    call mouse_send_cmd

    ; Unmask IRQ 12 on slave PIC (clear bit 4)
    in al, 0xA1
    and al, 0xEF
    out 0xA1, al

    ; Ensure cascade IRQ 2 is unmasked on master PIC (clear bit 2)
    in al, 0x21
    and al, 0xFB
    out 0x21, al

    ; Init packet tracking
    mov byte [mouse_packet_idx], 0

    sti
    popa
    ret

; -----------------------------------------------------------------------------
; PS/2 Mouse IRQ 12 handler (INT 0x74)
; Receives 3-byte packets, updates mouse_x/y/buttons
; Packet format:
;   Byte 0: [Yov Xov Ysign Xsign 1 Mid Right Left]
;   Byte 1: X movement
;   Byte 2: Y movement
; -----------------------------------------------------------------------------
mouse_irq_handler:
    pusha
    push ds

    ; Set DS=0 for data access
    xor ax, ax
    mov ds, ax

    ; Read byte from mouse port
    in al, 0x60

    xor bh, bh
    mov bl, [mouse_packet_idx]

    ; Sync check: first byte must have bit 3 set
    test bl, bl
    jnz .store
    test al, 0x08
    jz .eoi                  ; Out of sync - discard byte

.store:
    mov [mouse_packet + bx], al
    inc bl

    cmp bl, 3
    jne .save_idx

    ; --- Full 3-byte packet received ---
    xor bl, bl               ; Reset packet index

    ; Update button state (bits 0-2: left, right, middle)
    mov al, [mouse_packet]
    and al, 0x07
    mov byte [mouse_buttons], al

    ; --- X movement (sign-extended) ---
    xor ah, ah
    mov al, [mouse_packet + 1]
    test byte [mouse_packet], 0x10   ; X sign bit
    jz .x_pos
    mov ah, 0xFF             ; Sign-extend negative
.x_pos:
    add word [mouse_x], ax

    ; Clamp X to 0..639
    cmp word [mouse_x], 0
    jge .x_min_ok
    mov word [mouse_x], 0
.x_min_ok:
    cmp word [mouse_x], SCREEN_WIDTH - 1
    jle .x_max_ok
    mov word [mouse_x], SCREEN_WIDTH - 1
.x_max_ok:

    ; --- Y movement (sign-extended, INVERTED: PS/2 Y-up is positive) ---
    xor ah, ah
    mov al, [mouse_packet + 2]
    test byte [mouse_packet], 0x20   ; Y sign bit
    jz .y_pos
    mov ah, 0xFF
.y_pos:
    sub word [mouse_y], ax   ; Subtract: PS/2 Y is inverted from screen Y

    ; Clamp Y to 0..479
    cmp word [mouse_y], 0
    jge .y_min_ok
    mov word [mouse_y], 0
.y_min_ok:
    cmp word [mouse_y], SCREEN_HEIGHT - 1
    jle .y_max_ok
    mov word [mouse_y], SCREEN_HEIGHT - 1
.y_max_ok:

.save_idx:
    mov [mouse_packet_idx], bl

.eoi:
    ; Send EOI to slave PIC then master PIC
    mov al, 0x20
    out 0xA0, al
    out 0x20, al

    pop ds
    popa
    iret

mouse_packet     db 0, 0, 0
mouse_packet_idx db 0

; -----------------------------------------------------------------------------
; Handle mouse click at current position (all coords doubled)
; -----------------------------------------------------------------------------
handle_click:
    pusha

    mov cx, [mouse_x]
    mov dx, [mouse_y]

    ; Check editor icon click area (20..100, 40..140)
    cmp cx, 20
    jl .check_files_icon
    cmp cx, 100
    jg .check_files_icon
    cmp dx, 40
    jl .check_files_icon
    cmp dx, 140
    jg .check_files_icon

    mov byte [editor_state], WIN_OPEN
    mov byte [need_redraw], 1
    jmp .done

.check_files_icon:
    ; Check files icon click area (20..100, 180..280)
    cmp cx, 20
    jl .check_windows
    cmp cx, 100
    jg .check_windows
    cmp dx, 180
    jl .check_windows
    cmp dx, 280
    jg .check_windows

    mov byte [files_state], WIN_OPEN
    mov byte [need_redraw], 1
    jmp .done

.check_windows:
    ; Check editor window close button (24x24 at x+w-28, y+4)
    cmp byte [editor_state], WIN_OPEN
    jne .check_files_close

    mov ax, [editor_x]
    add ax, 372             ; 400 - 28
    cmp cx, ax
    jl .check_editor_buttons
    add ax, 24
    cmp cx, ax
    jg .check_editor_buttons
    mov ax, [editor_y]
    add ax, 4
    cmp dx, ax
    jl .check_editor_buttons
    add ax, 24
    cmp dx, ax
    jg .check_editor_buttons

    mov byte [editor_state], WIN_CLOSED
    mov byte [need_redraw], 1
    jmp .done

.check_editor_buttons:
    ; Check Save button (80x24 at editor_x+20, editor_y+208)
    mov ax, [editor_x]
    add ax, 20
    cmp cx, ax
    jl .check_clear
    add ax, 80
    cmp cx, ax
    jg .check_clear
    mov ax, [editor_y]
    add ax, 208
    cmp dx, ax
    jl .check_clear
    add ax, 24
    cmp dx, ax
    jg .check_clear

    mov bx, [current_file]
    call fs_save_file
    jmp .done

.check_clear:
    ; Check Clear button (88x24 at editor_x+120, editor_y+208)
    mov ax, [editor_x]
    add ax, 120
    cmp cx, ax
    jl .check_files_close
    add ax, 88
    cmp cx, ax
    jg .check_files_close
    mov ax, [editor_y]
    add ax, 208
    cmp dx, ax
    jl .check_files_close
    add ax, 24
    cmp dx, ax
    jg .check_files_close

    mov byte [editor_buffer], 0
    mov word [editor_cursor], 0
    jmp .done

.check_files_close:
    ; Check file manager close button (24x24 at files_x+332, files_y+4)
    cmp byte [files_state], WIN_OPEN
    jne .done

    mov ax, [files_x]
    add ax, 332             ; 360 - 28
    cmp cx, ax
    jl .check_file_click
    add ax, 24
    cmp cx, ax
    jg .check_file_click
    mov ax, [files_y]
    add ax, 4
    cmp dx, ax
    jl .check_file_click
    add ax, 24
    cmp dx, ax
    jg .check_file_click

    mov byte [files_state], WIN_CLOSED
    mov byte [need_redraw], 1
    jmp .done

.check_file_click:
    ; Check if clicking on a file in the list
    mov ax, [files_x]
    add ax, 20
    cmp cx, ax
    jl .done
    add ax, 320
    cmp cx, ax
    jg .done

    mov ax, [files_y]
    add ax, 44
    cmp dx, ax
    jl .done

    ; Calculate which file was clicked (28px spacing)
    sub dx, ax
    mov ax, dx
    xor dx, dx
    mov bx, 28
    div bx

    cmp ax, MAX_FILES
    jge .done

    ; Load file into editor
    mov bx, ax
    call fs_get_entry

    mov al, [di]
    test al, al
    jz .done

    ; Copy content to editor
    add di, FILENAME_LEN + 2
    mov si, di
    mov di, editor_buffer
    mov cx, FILE_CONTENT_SIZE
.copy_file:
    lodsb
    mov [di], al            ; Use DS:DI (not stosb which uses ES:DI)
    inc di
    test al, al
    jz .open_editor
    loop .copy_file

.open_editor:
    mov [current_file], bx  ; Track which file is being edited
    mov byte [editor_state], WIN_OPEN
    mov word [editor_cursor], 0
    mov byte [need_redraw], 1

.done:
    popa
    ret

; -----------------------------------------------------------------------------
; Draw mouse cursor using XOR
; -----------------------------------------------------------------------------
draw_mouse_cursor:
    pusha
    mov cx, [mouse_x]
    mov dx, [mouse_y]
    call draw_xor_cursor
    popa
    ret

; -----------------------------------------------------------------------------
; Draw XOR cursor at CX, DX - calling twice erases it
; -----------------------------------------------------------------------------
draw_xor_cursor:
    pusha

    ; Row 0: X
    call xor_pixel

    ; Row 1: XX
    inc dx
    call xor_pixel
    inc cx
    call xor_pixel
    dec cx

    ; Row 2: XXX
    inc dx
    call xor_pixel
    inc cx
    call xor_pixel
    inc cx
    call xor_pixel
    sub cx, 2

    ; Row 3: XXXX
    inc dx
    call xor_pixel
    inc cx
    call xor_pixel
    inc cx
    call xor_pixel
    inc cx
    call xor_pixel
    sub cx, 3

    ; Row 4: XXXXX
    inc dx
    call xor_pixel
    inc cx
    call xor_pixel
    inc cx
    call xor_pixel
    inc cx
    call xor_pixel
    inc cx
    call xor_pixel
    sub cx, 4

    ; Row 5: XX
    inc dx
    call xor_pixel
    inc cx
    call xor_pixel
    dec cx

    ; Row 6: X X
    inc dx
    call xor_pixel
    add cx, 2
    call xor_pixel
    sub cx, 2

    ; Row 7:   X
    inc dx
    add cx, 2
    call xor_pixel

    popa
    ret

; -----------------------------------------------------------------------------
; XOR a pixel at CX, DX with 0x0F (inverts color) - bank-switched
; -----------------------------------------------------------------------------
xor_pixel:
    pusha

    ; Calculate 32-bit offset: y * 640 + x
    mov ax, dx
    mov bx, SCREEN_WIDTH
    mul bx
    add ax, cx
    adc dx, 0

    ; Switch bank if needed
    call switch_bank

    mov di, ax
    xor byte [es:di], 0xFF

    popa
    ret

; =============================================================================
; KEYBOARD HANDLING
; =============================================================================

keyboard_handler:
    pusha

    mov ah, 0
    int 0x16

    ; Handle arrow keys for cursor movement
    cmp ah, 0x48
    je .cursor_up
    cmp ah, 0x50
    je .cursor_down
    cmp ah, 0x4B
    je .cursor_left
    cmp ah, 0x4D
    je .cursor_right
    cmp ah, 0x1C
    jne .check_editor
    cmp byte [editor_state], WIN_OPEN
    je .check_editor
    call handle_click
    jmp .done

.cursor_up:
    cmp word [mouse_y], 5
    jl .done
    sub word [mouse_y], 5
    jmp .done

.cursor_down:
    cmp word [mouse_y], SCREEN_HEIGHT - 5
    jge .done
    add word [mouse_y], 5
    jmp .done

.cursor_left:
    cmp word [mouse_x], 5
    jl .done
    sub word [mouse_x], 5
    jmp .done

.cursor_right:
    cmp word [mouse_x], SCREEN_WIDTH - 5
    jge .done
    add word [mouse_x], 5
    jmp .done

.check_editor:
    cmp byte [editor_state], WIN_OPEN
    jne .done

    cmp ah, 0x0E
    je .backspace
    cmp ah, 0x1C
    je .enter
    cmp al, 0
    je .done

    ; Regular character
    mov bx, [editor_cursor]
    cmp bx, 500
    jge .done

    mov di, editor_buffer
    add di, bx
    mov [di], al
    inc bx
    mov byte [di+1], 0
    mov [editor_cursor], bx
    mov byte [need_redraw], 2
    jmp .done

.backspace:
    mov bx, [editor_cursor]
    test bx, bx
    jz .done
    dec bx
    mov [editor_cursor], bx
    mov di, editor_buffer
    add di, bx
    mov byte [di], 0
    mov byte [need_redraw], 2
    jmp .done

.enter:
    mov bx, [editor_cursor]
    cmp bx, 500
    jge .done
    mov di, editor_buffer
    add di, bx
    mov byte [di], 10
    inc bx
    mov byte [di+1], 0
    mov [editor_cursor], bx
    mov byte [need_redraw], 2

.done:
    popa
    ret

; =============================================================================
; FONT DATA (8x8 bitmap font for printable ASCII)
; =============================================================================

font_data:
    ; Space (32)
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; ! (33)
    db 0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x18, 0x00
    ; " (34)
    db 0x6C, 0x6C, 0x24, 0x00, 0x00, 0x00, 0x00, 0x00
    ; # (35)
    db 0x6C, 0x6C, 0xFE, 0x6C, 0xFE, 0x6C, 0x6C, 0x00
    ; $ (36)
    db 0x18, 0x3E, 0x60, 0x3C, 0x06, 0x7C, 0x18, 0x00
    ; % (37)
    db 0x00, 0x66, 0xAC, 0xD8, 0x36, 0x6A, 0xCC, 0x00
    ; & (38)
    db 0x38, 0x6C, 0x68, 0x76, 0xDC, 0xCC, 0x76, 0x00
    ; ' (39)
    db 0x18, 0x18, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00
    ; ( (40)
    db 0x0C, 0x18, 0x30, 0x30, 0x30, 0x18, 0x0C, 0x00
    ; ) (41)
    db 0x30, 0x18, 0x0C, 0x0C, 0x0C, 0x18, 0x30, 0x00
    ; * (42)
    db 0x00, 0x66, 0x3C, 0xFF, 0x3C, 0x66, 0x00, 0x00
    ; + (43)
    db 0x00, 0x18, 0x18, 0x7E, 0x18, 0x18, 0x00, 0x00
    ; , (44)
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x30
    ; - (45)
    db 0x00, 0x00, 0x00, 0x7E, 0x00, 0x00, 0x00, 0x00
    ; . (46)
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00
    ; / (47)
    db 0x06, 0x0C, 0x18, 0x30, 0x60, 0xC0, 0x80, 0x00
    ; 0 (48)
    db 0x7C, 0xC6, 0xCE, 0xD6, 0xE6, 0xC6, 0x7C, 0x00
    ; 1 (49)
    db 0x18, 0x38, 0x18, 0x18, 0x18, 0x18, 0x7E, 0x00
    ; 2 (50)
    db 0x7C, 0xC6, 0x06, 0x1C, 0x70, 0xC6, 0xFE, 0x00
    ; 3 (51)
    db 0x7C, 0xC6, 0x06, 0x3C, 0x06, 0xC6, 0x7C, 0x00
    ; 4 (52)
    db 0x1C, 0x3C, 0x6C, 0xCC, 0xFE, 0x0C, 0x1E, 0x00
    ; 5 (53)
    db 0xFE, 0xC0, 0xFC, 0x06, 0x06, 0xC6, 0x7C, 0x00
    ; 6 (54)
    db 0x38, 0x60, 0xC0, 0xFC, 0xC6, 0xC6, 0x7C, 0x00
    ; 7 (55)
    db 0xFE, 0xC6, 0x0C, 0x18, 0x30, 0x30, 0x30, 0x00
    ; 8 (56)
    db 0x7C, 0xC6, 0xC6, 0x7C, 0xC6, 0xC6, 0x7C, 0x00
    ; 9 (57)
    db 0x7C, 0xC6, 0xC6, 0x7E, 0x06, 0x0C, 0x78, 0x00
    ; : (58)
    db 0x00, 0x18, 0x18, 0x00, 0x00, 0x18, 0x18, 0x00
    ; ; (59)
    db 0x00, 0x18, 0x18, 0x00, 0x00, 0x18, 0x18, 0x30
    ; < (60)
    db 0x0C, 0x18, 0x30, 0x60, 0x30, 0x18, 0x0C, 0x00
    ; = (61)
    db 0x00, 0x00, 0x7E, 0x00, 0x7E, 0x00, 0x00, 0x00
    ; > (62)
    db 0x30, 0x18, 0x0C, 0x06, 0x0C, 0x18, 0x30, 0x00
    ; ? (63)
    db 0x7C, 0xC6, 0x0C, 0x18, 0x18, 0x00, 0x18, 0x00
    ; @ (64)
    db 0x7C, 0xC6, 0xDE, 0xDE, 0xDE, 0xC0, 0x78, 0x00
    ; A (65)
    db 0x38, 0x6C, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0x00
    ; B (66)
    db 0xFC, 0xC6, 0xC6, 0xFC, 0xC6, 0xC6, 0xFC, 0x00
    ; C (67)
    db 0x7C, 0xC6, 0xC0, 0xC0, 0xC0, 0xC6, 0x7C, 0x00
    ; D (68)
    db 0xF8, 0xCC, 0xC6, 0xC6, 0xC6, 0xCC, 0xF8, 0x00
    ; E (69)
    db 0xFE, 0xC0, 0xC0, 0xF8, 0xC0, 0xC0, 0xFE, 0x00
    ; F (70)
    db 0xFE, 0xC0, 0xC0, 0xF8, 0xC0, 0xC0, 0xC0, 0x00
    ; G (71)
    db 0x7C, 0xC6, 0xC0, 0xCE, 0xC6, 0xC6, 0x7E, 0x00
    ; H (72)
    db 0xC6, 0xC6, 0xC6, 0xFE, 0xC6, 0xC6, 0xC6, 0x00
    ; I (73)
    db 0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x7E, 0x00
    ; J (74)
    db 0x1E, 0x06, 0x06, 0x06, 0xC6, 0xC6, 0x7C, 0x00
    ; K (75)
    db 0xC6, 0xCC, 0xD8, 0xF0, 0xD8, 0xCC, 0xC6, 0x00
    ; L (76)
    db 0xC0, 0xC0, 0xC0, 0xC0, 0xC0, 0xC0, 0xFE, 0x00
    ; M (77)
    db 0xC6, 0xEE, 0xFE, 0xFE, 0xD6, 0xC6, 0xC6, 0x00
    ; N (78)
    db 0xC6, 0xE6, 0xF6, 0xDE, 0xCE, 0xC6, 0xC6, 0x00
    ; O (79)
    db 0x7C, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00
    ; P (80)
    db 0xFC, 0xC6, 0xC6, 0xFC, 0xC0, 0xC0, 0xC0, 0x00
    ; Q (81)
    db 0x7C, 0xC6, 0xC6, 0xC6, 0xD6, 0xDE, 0x7C, 0x06
    ; R (82)
    db 0xFC, 0xC6, 0xC6, 0xFC, 0xD8, 0xCC, 0xC6, 0x00
    ; S (83)
    db 0x7C, 0xC6, 0x60, 0x38, 0x0C, 0xC6, 0x7C, 0x00
    ; T (84)
    db 0xFF, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00
    ; U (85)
    db 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0xC6, 0x7C, 0x00
    ; V (86)
    db 0xC6, 0xC6, 0xC6, 0xC6, 0x6C, 0x38, 0x10, 0x00
    ; W (87)
    db 0xC6, 0xC6, 0xD6, 0xFE, 0xFE, 0xEE, 0xC6, 0x00
    ; X (88)
    db 0xC6, 0x6C, 0x38, 0x38, 0x38, 0x6C, 0xC6, 0x00
    ; Y (89)
    db 0xC3, 0x66, 0x3C, 0x18, 0x18, 0x18, 0x18, 0x00
    ; Z (90)
    db 0xFE, 0x0C, 0x18, 0x30, 0x60, 0xC0, 0xFE, 0x00
    ; [ (91)
    db 0x3C, 0x30, 0x30, 0x30, 0x30, 0x30, 0x3C, 0x00
    ; \ (92)
    db 0xC0, 0x60, 0x30, 0x18, 0x0C, 0x06, 0x02, 0x00
    ; ] (93)
    db 0x3C, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x3C, 0x00
    ; ^ (94)
    db 0x10, 0x38, 0x6C, 0xC6, 0x00, 0x00, 0x00, 0x00
    ; _ (95)
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF
    ; ` (96)
    db 0x30, 0x18, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00
    ; a (97)
    db 0x00, 0x00, 0x7C, 0x06, 0x7E, 0xC6, 0x7E, 0x00
    ; b (98)
    db 0xC0, 0xC0, 0xFC, 0xC6, 0xC6, 0xC6, 0xFC, 0x00
    ; c (99)
    db 0x00, 0x00, 0x7C, 0xC6, 0xC0, 0xC6, 0x7C, 0x00
    ; d (100)
    db 0x06, 0x06, 0x7E, 0xC6, 0xC6, 0xC6, 0x7E, 0x00
    ; e (101)
    db 0x00, 0x00, 0x7C, 0xC6, 0xFE, 0xC0, 0x7C, 0x00
    ; f (102)
    db 0x1C, 0x36, 0x30, 0x78, 0x30, 0x30, 0x30, 0x00
    ; g (103)
    db 0x00, 0x00, 0x7E, 0xC6, 0xC6, 0x7E, 0x06, 0x7C
    ; h (104)
    db 0xC0, 0xC0, 0xFC, 0xC6, 0xC6, 0xC6, 0xC6, 0x00
    ; i (105)
    db 0x18, 0x00, 0x38, 0x18, 0x18, 0x18, 0x3C, 0x00
    ; j (106)
    db 0x06, 0x00, 0x06, 0x06, 0x06, 0x06, 0xC6, 0x7C
    ; k (107)
    db 0xC0, 0xC0, 0xCC, 0xD8, 0xF0, 0xD8, 0xCC, 0x00
    ; l (108)
    db 0x38, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00
    ; m (109)
    db 0x00, 0x00, 0xEC, 0xFE, 0xD6, 0xC6, 0xC6, 0x00
    ; n (110)
    db 0x00, 0x00, 0xFC, 0xC6, 0xC6, 0xC6, 0xC6, 0x00
    ; o (111)
    db 0x00, 0x00, 0x7C, 0xC6, 0xC6, 0xC6, 0x7C, 0x00
    ; p (112)
    db 0x00, 0x00, 0xFC, 0xC6, 0xC6, 0xFC, 0xC0, 0xC0
    ; q (113)
    db 0x00, 0x00, 0x7E, 0xC6, 0xC6, 0x7E, 0x06, 0x06
    ; r (114)
    db 0x00, 0x00, 0xDC, 0xE6, 0xC0, 0xC0, 0xC0, 0x00
    ; s (115)
    db 0x00, 0x00, 0x7E, 0xC0, 0x7C, 0x06, 0xFC, 0x00
    ; t (116)
    db 0x30, 0x30, 0x7C, 0x30, 0x30, 0x36, 0x1C, 0x00
    ; u (117)
    db 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0xC6, 0x7E, 0x00
    ; v (118)
    db 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0x6C, 0x38, 0x00
    ; w (119)
    db 0x00, 0x00, 0xC6, 0xC6, 0xD6, 0xFE, 0x6C, 0x00
    ; x (120)
    db 0x00, 0x00, 0xC6, 0x6C, 0x38, 0x6C, 0xC6, 0x00
    ; y (121)
    db 0x00, 0x00, 0xC6, 0xC6, 0xC6, 0x7E, 0x06, 0x7C
    ; z (122)
    db 0x00, 0x00, 0xFE, 0x0C, 0x38, 0x60, 0xFE, 0x00
    ; { (123)
    db 0x0E, 0x18, 0x18, 0x70, 0x18, 0x18, 0x0E, 0x00
    ; | (124)
    db 0x18, 0x18, 0x18, 0x00, 0x18, 0x18, 0x18, 0x00
    ; } (125)
    db 0x70, 0x18, 0x18, 0x0E, 0x18, 0x18, 0x70, 0x00
    ; ~ (126)
    db 0x76, 0xDC, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

; =============================================================================
; DATA SECTION
; =============================================================================

; Window states
editor_state    db WIN_CLOSED
files_state     db WIN_CLOSED

; Window positions (doubled)
editor_x        dw 120
editor_y        dw 60
files_x         dw 160
files_y         dw 40

; Mouse state (initial position centered)
mouse_x         dw 320
mouse_y         dw 240
mouse_buttons   db 0
mouse_clicked   db 0

; Editor data
editor_cursor   dw 0
current_file    dw 0
editor_buffer   db 512 dup(0)

; Boot drive (saved from bootloader)
boot_drive      db 0

; File system table
fs_table        db (FS_ENTRY_SIZE * MAX_FILES) dup(0)

; Padding to 48 sectors (24576 bytes)
kernel_end:
db (24576 - (kernel_end - $$)) dup(0)
