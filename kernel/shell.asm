; =============================================================
; ProbablyFineOS — Demo Shell
; Included into kernel/kernel.asm
;
; Commands:
;   help   — list commands
;   clear  — clear screen
;   mouse  — print mouse X/Y and button state
; =============================================================

SHELL_BUF_SIZE  equ 128

; ==============================================================
; shell_main — interactive REPL (never returns)
; ==============================================================
shell_main:
    ; Cyan banner
    mov     al, (VGA_BLACK shl 4) or VGA_LCYAN
    call    vga_set_color
    lea     eax, [sh_banner1]
    push    eax
    call    vga_puts
    add     esp, 4

    lea     eax, [sh_banner2]
    push    eax
    call    vga_puts
    add     esp, 4

    lea     eax, [sh_banner3]
    push    eax
    call    vga_puts
    add     esp, 4

    lea     eax, [sh_banner4]
    push    eax
    call    vga_puts
    add     esp, 4

    ; Green version line
    mov     al, (VGA_BLACK shl 4) or VGA_LGREEN
    call    vga_set_color
    lea     eax, [sh_ver]
    push    eax
    call    vga_puts
    add     esp, 4

    ; Default colour + hint
    mov     al, VGA_DEFAULT_ATTR
    call    vga_set_color
    lea     eax, [sh_hint]
    push    eax
    call    vga_puts
    add     esp, 4

.repl:
    ; Yellow prompt
    mov     al, (VGA_BLACK shl 4) or VGA_YELLOW
    call    vga_set_color
    lea     eax, [sh_prompt]
    push    eax
    call    vga_puts
    add     esp, 4
    mov     al, VGA_DEFAULT_ATTR
    call    vga_set_color

    call    shell_readline
    call    shell_dispatch
    jmp     .repl

; ==============================================================
; shell_readline — read a line into shell_input_buf
; Echo characters, handle Backspace, terminate on Enter.
; ==============================================================
shell_readline:
    push    ecx
    push    edi
    lea     edi, [shell_input_buf]
    xor     ecx, ecx                ; byte count

.poll:
    call    keyboard_getc
    test    al, al
    jz      .poll

    cmp     al, 0x0D                ; Enter
    je      .enter

    cmp     al, 0x08                ; Backspace
    je      .bsp

    cmp     ecx, SHELL_BUF_SIZE - 1 ; buffer full?
    jge     .poll

    call    vga_putc                ; echo
    mov     [edi + ecx], al
    inc     ecx
    jmp     .poll

.bsp:
    test    ecx, ecx
    jz      .poll
    dec     ecx
    call    vga_putc                ; vga_putc handles BS
    jmp     .poll

.enter:
    mov     byte [edi + ecx], 0     ; null-terminate
    mov     al, 0x0A
    call    vga_putc                ; newline
    pop     edi
    pop     ecx
    ret

; ==============================================================
; shell_dispatch — execute command in shell_input_buf
; ==============================================================
shell_dispatch:
    push    esi
    lea     esi, [shell_input_buf]

    ; skip leading spaces
.trim:
    cmp     byte [esi], ' '
    jne     .chk
    inc     esi
    jmp     .trim

.chk:
    cmp     byte [esi], 0
    je      .out

    lea     edi, [sh_cmd_help]
    call    shell_strcmp
    jz      .cmd_help

    lea     edi, [sh_cmd_clear]
    call    shell_strcmp
    jz      .cmd_clear

    lea     edi, [sh_cmd_mouse]
    call    shell_strcmp
    jz      .cmd_mouse

    lea     edi, [sh_cmd_panic]
    call    shell_strcmp
    jz      .cmd_panic

    lea     edi, [sh_cmd_ticks]
    call    shell_strcmp
    jz      .cmd_ticks

    lea     edi, [sh_cmd_threads]
    call    shell_strcmp
    jz      .cmd_threads

    ; unknown
    lea     eax, [sh_unknown]
    push    eax
    call    vga_puts
    add     esp, 4
    jmp     .out

.cmd_help:
    lea     eax, [sh_helptext]
    push    eax
    call    vga_puts
    add     esp, 4
    jmp     .out

.cmd_clear:
    call    vga_clear
    mov     byte [vga_col], 0
    mov     byte [vga_row], 0
    jmp     .out

.cmd_mouse:
    lea     eax, [sh_mouse_x]   ; "Mouse X="
    push    eax
    call    vga_puts
    add     esp, 4

    movzx   eax, word [mouse_x]
    call    vga_print_dec

    lea     eax, [sh_mouse_y]   ; " Y="
    push    eax
    call    vga_puts
    add     esp, 4

    movzx   eax, word [mouse_y]
    call    vga_print_dec

    lea     eax, [sh_mouse_btn] ; " Btn=0x"
    push    eax
    call    vga_puts
    add     esp, 4

    movzx   eax, byte [mouse_buttons]
    call    vga_print_hex

    mov     al, 0x0A
    call    vga_putc
    jmp     .out

.cmd_panic:
    lea     eax, [sh_panic_msg]
    push    eax
    call    vga_puts
    add     esp, 4
    ; Trigger divide by zero exception
    xor     edx, edx
    xor     eax, eax
    div     edx                 ; Divide by zero!
    jmp     .out

.cmd_ticks:
    lea     eax, [sh_ticks_msg]
    push    eax
    call    vga_puts
    add     esp, 4

    call    timer_get_ticks
    call    vga_print_dec

    lea     eax, [sh_ticks_suffix]
    push    eax
    call    vga_puts
    add     esp, 4
    jmp     .out

.cmd_threads:
    lea     eax, [sh_threads_msg]
    push    eax
    call    vga_puts
    add     esp, 4

    ; Create test thread A
    lea     eax, [test_thread_a]
    call    thread_create
    cmp     eax, -1
    je      .thread_error

    ; Create test thread B
    lea     eax, [test_thread_b]
    call    thread_create
    cmp     eax, -1
    je      .thread_error

    lea     eax, [sh_threads_ok]
    push    eax
    call    vga_puts
    add     esp, 4
    jmp     .out

.thread_error:
    lea     eax, [sh_threads_err]
    push    eax
    call    vga_puts
    add     esp, 4
    jmp     .out

.out:
    pop     esi
    ret

; ==============================================================
; shell_strcmp — compare [ESI] (input token) with [EDI] (keyword)
; Comparison stops at first space or NUL in ESI.
; Returns: ZF=1 if match, ZF=0 if not.
; Does NOT modify ESI or EDI.
; ==============================================================
shell_strcmp:
    push    esi
    push    edi
    push    eax
    push    ecx
.loop:
    mov     al,  [esi]
    mov     cl,  [edi]
    cmp     al,  ' '
    je      .esi_end
    cmp     al,  0
    je      .esi_end
    cmp     al,  cl
    jne     .ne
    inc     esi
    inc     edi
    jmp     .loop
.esi_end:
    ; ESI ended — keyword must also end here
    test    cl, cl
    jz      .eq
.ne:
    pop     ecx
    pop     eax
    pop     edi
    pop     esi
    cmp     al, al          ; ZF=1 temporarily…
    mov     al, 1
    cmp     al, 0           ; ZF=0
    ret
.eq:
    pop     ecx
    pop     eax
    pop     edi
    pop     esi
    xor     al, al
    cmp     al, 0           ; ZF=1
    ret

; ==============================================================
; String constants
; ==============================================================
sh_banner1  db '  ____           _           _     _       ___  ____', 0x0A, 0
sh_banner2  db ' |  _ \ _ __ ___| |__   __ _| |__ | |_   / _ \/ ___|', 0x0A, 0
sh_banner3  db ' | |_) | `__/ _ \ `_ \ / _` | `_ \| | | | | | \___ \', 0x0A, 0
sh_banner4  db ' |____/|_|  \___/_.__/ \__,_|_.__/|_|\___\___/|____/', 0x0A, 0
sh_ver      db '  v0.1.0  |  FASM  |  x86 Protected Mode  |  2026', 0x0A, 0
sh_hint     db '  Type "help" for commands.', 0x0A, 0x0A, 0
sh_prompt   db 'PFineOS> ', 0
sh_unknown  db 'Unknown command. Try "help".', 0x0A, 0
sh_helptext db 'Commands:', 0x0A
            db '  help    show this list', 0x0A
            db '  clear   clear the screen', 0x0A
            db '  mouse   print mouse position and buttons', 0x0A
            db '  ticks   show system timer ticks (10ms each)', 0x0A
            db '  threads spawn test threads (multitasking demo)', 0x0A
            db '  panic   test exception handler (div by zero)', 0x0A, 0
sh_mouse_x  db 'Mouse X=', 0
sh_mouse_y  db ' Y=', 0
sh_mouse_btn db ' Btn=0x', 0
sh_panic_msg db 'Testing exception handler...', 0x0A, 0
sh_ticks_msg db 'Timer ticks: ', 0
sh_ticks_suffix db ' (100 Hz, 10ms each)', 0x0A, 0
sh_threads_msg db 'Creating test threads...', 0x0A, 0
sh_threads_ok db 'Test threads created successfully.', 0x0A, 0
sh_threads_err db 'Failed to create threads!', 0x0A, 0

sh_cmd_help    db 'help',  0
sh_cmd_clear   db 'clear', 0
sh_cmd_mouse   db 'mouse', 0
sh_cmd_ticks   db 'ticks', 0
sh_cmd_threads db 'threads', 0
sh_cmd_panic   db 'panic', 0

; Input buffer
shell_input_buf: rb SHELL_BUF_SIZE
