; =============================================================
; ProbablyFineOS — CPU Exception Handlers (FASM syntax)
; Included into kernel/kernel.asm
;
; Exceptions 0-31: CPU-defined exceptions
; ISRs save registers and call C exception handler
; =============================================================

; -------------------------------------------------------------
; Exception stub macro — no error code
; CPU does NOT push error code, so we push dummy 0
; -------------------------------------------------------------
macro exception_stub_no_error num {
  isr#num:
    cli
    push dword 0              ; Dummy error code
    push dword num            ; Exception number
    jmp exception_common
}

; -------------------------------------------------------------
; Exception stub macro — with error code
; CPU already pushed error code
; -------------------------------------------------------------
macro exception_stub_error num {
  isr#num:
    cli
    push dword num            ; Exception number
    jmp exception_common
}

; -------------------------------------------------------------
; Common exception handler
; Stack at entry (top to bottom):
;   [ESP+0]  = exception number (pushed by stub)
;   [ESP+4]  = error code (real or dummy 0)
;   [ESP+8]  = EIP (pushed by CPU)
;   [ESP+12] = CS (pushed by CPU)
;   [ESP+16] = EFLAGS (pushed by CPU)
; -------------------------------------------------------------
exception_common:
    pushad                    ; Save EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI
    push_segs                 ; Save DS, ES, FS, GS
    set_kernel_segs           ; Reload kernel segments

    ; Call C exception handler: exception_handler(exc_num, error_code, eip, regs)
    ; Stack layout at this point (ESP points here):
    ; [ESP+0]  = GS, FS, ES, DS (push_segs = 16 bytes)
    ; [ESP+16] = pushad (32 bytes)
    ; [ESP+48] = exception number (4 bytes)
    ; [ESP+52] = error code (4 bytes)
    ; [ESP+56] = EIP (4 bytes, pushed by CPU)
    ; [ESP+60] = CS (4 bytes, pushed by CPU)
    ; [ESP+64] = EFLAGS (4 bytes, pushed by CPU)

    ; Push arguments in reverse order (cdecl)
    mov eax, esp
    push eax                  ; arg4: regs* - now ESP -= 4

    mov eax, [esp + 4 + 56]   ; EIP (adjust for previous push)
    push eax                  ; arg3: eip - now ESP -= 4

    mov eax, [esp + 8 + 52]   ; Error code (adjust for 2 pushes)
    push eax                  ; arg2: error_code - now ESP -= 4

    mov eax, [esp + 12 + 48]  ; Exception number (adjust for 3 pushes)
    push eax                  ; arg1: exc_num - now ESP -= 4

    call exception_handler_asm ; Assembly handler (below)
    add esp, 16                ; Clean up arguments

    ; Exception handler should not return (calls freeze)
    ; But if it does, freeze here
    freeze

; -------------------------------------------------------------
; Exception handler (assembly implementation)
; Args: exc_num, error_code, eip, regs*
; -------------------------------------------------------------
exception_handler_asm:
    push ebp
    mov ebp, esp

    ; Set red background for panic
    push eax
    mov al, 0x4F              ; Red background, white foreground
    call vga_set_color
    pop eax

    ; Print panic header
    push panic_header
    call vga_puts
    add esp, 4

    ; Print exception number
    mov eax, [ebp + 8]        ; exc_num
    cmp eax, 31
    ja .unknown_exception

    ; Print exception name from table
    lea ebx, [exception_names]
    mov ecx, eax
    shl ecx, 2                ; ecx = exc_num * 4 (pointer size)
    add ebx, ecx
    push dword [ebx]
    call vga_puts
    add esp, 4
    jmp .print_details

.unknown_exception:
    push unknown_exc_msg
    call vga_puts
    add esp, 4

.print_details:
    ; Newline
    push newline
    call vga_puts
    add esp, 4

    ; Print EIP
    push eip_label
    call vga_puts
    add esp, 4
    mov eax, [ebp + 16]       ; eip
    call vga_print_hex
    push newline
    call vga_puts
    add esp, 4

    ; Print error code
    push error_label
    call vga_puts
    add esp, 4
    mov eax, [ebp + 12]       ; error_code
    call vga_print_hex
    push newline
    call vga_puts
    add esp, 4

    ; For page fault (exc_num == 14), print CR2
    cmp dword [ebp + 8], 14
    jne .skip_cr2
    push cr2_label
    call vga_puts
    add esp, 4
    mov eax, cr2
    call vga_print_hex
    push newline
    call vga_puts
    add esp, 4

.skip_cr2:
    ; Print halting message
    push halt_msg
    call vga_puts
    add esp, 4

    pop ebp
    ret

; -------------------------------------------------------------
; Exception messages
; -------------------------------------------------------------
panic_header     db 10, '*** KERNEL PANIC ***', 10, 'Exception: ', 0
unknown_exc_msg  db 'Unknown Exception', 0
eip_label        db 'EIP: 0x', 0
error_label      db 'Error Code: 0x', 0
cr2_label        db 'CR2 (fault addr): 0x', 0
halt_msg         db 'System halted.', 10, 0
newline          db 10, 0

; Exception name strings
exc_name_0   db 'Divide by Zero', 0
exc_name_1   db 'Debug', 0
exc_name_2   db 'Non-Maskable Interrupt', 0
exc_name_3   db 'Breakpoint', 0
exc_name_4   db 'Overflow', 0
exc_name_5   db 'Bound Range Exceeded', 0
exc_name_6   db 'Invalid Opcode', 0
exc_name_7   db 'Device Not Available', 0
exc_name_8   db 'Double Fault', 0
exc_name_9   db 'Coprocessor Segment Overrun', 0
exc_name_10  db 'Invalid TSS', 0
exc_name_11  db 'Segment Not Present', 0
exc_name_12  db 'Stack-Segment Fault', 0
exc_name_13  db 'General Protection Fault', 0
exc_name_14  db 'Page Fault', 0
exc_name_15  db '(Reserved)', 0
exc_name_16  db 'x87 FPU Error', 0
exc_name_17  db 'Alignment Check', 0
exc_name_18  db 'Machine Check', 0
exc_name_19  db 'SIMD Floating-Point Exception', 0
exc_name_20  db '(Reserved)', 0
exc_name_21  db '(Reserved)', 0
exc_name_22  db '(Reserved)', 0
exc_name_23  db '(Reserved)', 0
exc_name_24  db '(Reserved)', 0
exc_name_25  db '(Reserved)', 0
exc_name_26  db '(Reserved)', 0
exc_name_27  db '(Reserved)', 0
exc_name_28  db '(Reserved)', 0
exc_name_29  db '(Reserved)', 0
exc_name_30  db '(Reserved)', 0
exc_name_31  db '(Reserved)', 0

; Exception names table (array of pointers)
exception_names:
    dd exc_name_0, exc_name_1, exc_name_2, exc_name_3
    dd exc_name_4, exc_name_5, exc_name_6, exc_name_7
    dd exc_name_8, exc_name_9, exc_name_10, exc_name_11
    dd exc_name_12, exc_name_13, exc_name_14, exc_name_15
    dd exc_name_16, exc_name_17, exc_name_18, exc_name_19
    dd exc_name_20, exc_name_21, exc_name_22, exc_name_23
    dd exc_name_24, exc_name_25, exc_name_26, exc_name_27
    dd exc_name_28, exc_name_29, exc_name_30, exc_name_31

; -------------------------------------------------------------
; Generate exception ISRs
; Exceptions with error code: 8, 10, 11, 12, 13, 14, 17
; All others: no error code
; -------------------------------------------------------------
exception_stub_no_error 0     ; Divide by Zero
exception_stub_no_error 1     ; Debug
exception_stub_no_error 2     ; NMI
exception_stub_no_error 3     ; Breakpoint
exception_stub_no_error 4     ; Overflow
exception_stub_no_error 5     ; Bound Range Exceeded
exception_stub_no_error 6     ; Invalid Opcode
exception_stub_no_error 7     ; Device Not Available
exception_stub_error 8        ; Double Fault
exception_stub_no_error 9     ; Coprocessor Segment Overrun
exception_stub_error 10       ; Invalid TSS
exception_stub_error 11       ; Segment Not Present
exception_stub_error 12       ; Stack-Segment Fault
exception_stub_error 13       ; General Protection Fault
exception_stub_error 14       ; Page Fault
exception_stub_no_error 15    ; Reserved
exception_stub_no_error 16    ; x87 FPU Error
exception_stub_error 17       ; Alignment Check
exception_stub_no_error 18    ; Machine Check
exception_stub_no_error 19    ; SIMD FP Exception
exception_stub_no_error 20    ; Reserved
exception_stub_no_error 21    ; Reserved
exception_stub_no_error 22    ; Reserved
exception_stub_no_error 23    ; Reserved
exception_stub_no_error 24    ; Reserved
exception_stub_no_error 25    ; Reserved
exception_stub_no_error 26    ; Reserved
exception_stub_no_error 27    ; Reserved
exception_stub_no_error 28    ; Reserved
exception_stub_no_error 29    ; Reserved
exception_stub_no_error 30    ; Reserved
exception_stub_no_error 31    ; Reserved

; -------------------------------------------------------------
; Exception handler installation
; Called from kernel_entry to install all ISRs into IDT
; -------------------------------------------------------------
install_exception_handlers:
    push eax
    push ecx

    macro install_isr num {
        lea eax, [isr#num]
        mov cl, num
        call idt_set_gate
    }

    install_isr 0
    install_isr 1
    install_isr 2
    install_isr 3
    install_isr 4
    install_isr 5
    install_isr 6
    install_isr 7
    install_isr 8
    install_isr 9
    install_isr 10
    install_isr 11
    install_isr 12
    install_isr 13
    install_isr 14
    install_isr 15
    install_isr 16
    install_isr 17
    install_isr 18
    install_isr 19
    install_isr 20
    install_isr 21
    install_isr 22
    install_isr 23
    install_isr 24
    install_isr 25
    install_isr 26
    install_isr 27
    install_isr 28
    install_isr 29
    install_isr 30
    install_isr 31

    purge install_isr

    pop ecx
    pop eax
    ret
