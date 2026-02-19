; =============================================================
; ProbablyFineOS — Stage 2 Bootloader
; Loaded by Stage 1 at 0x0500, runs in real mode.
;
; Responsibilities:
;   1. Enable A20 line (keyboard-controller method)
;   2. Optionally set VESA graphics mode (if VESA_ENABLE = 1)
;   3. Save VESA framebuffer info at VESA_INFO_ADDR
;   4. Load kernel binary from disk to KERNEL_LOAD_ADDR (0x10000)
;   5. Set up temporary GDT (null / code / data)
;   6. Enable protected mode (CR0.PE = 1)
;   7. Far-jump to kernel entry at 0x10000 in 32-bit PM
; =============================================================

format binary
use16
org 0x0500

include '../include/constants.inc'

; ---- Optional VESA (set to 1 to enable 800x600x32 graphics) --
if ~ defined VESA_ENABLE
    VESA_ENABLE = 0
end if

; ==============================================================
; Entry point
; ==============================================================
start16:
    cli
    xor     ax, ax
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     sp, 0x7BFF          ; safe stack below MBR
    sti

    mov     si, msg_stage2
    call    puts16

    ; ----------------------------------------------------------
    ; Step 1 — Enable A20 via keyboard controller
    ; ----------------------------------------------------------
    call    enable_a20

    ; ----------------------------------------------------------
    ; Step 2 — Set VESA mode (real mode, must be before PM)
    ; ----------------------------------------------------------
    if VESA_ENABLE = 1
        call    vesa_set_mode
    end if

    ; ----------------------------------------------------------
    ; Step 3 — Load kernel to 0x10000 using INT 13h ext. read
    ; ----------------------------------------------------------
    call    load_kernel

    ; ----------------------------------------------------------
    ; Step 4 — Set up temporary GDT
    ; ----------------------------------------------------------
    lgdt    [s2_gdt_desc]

    ; ----------------------------------------------------------
    ; Step 5 — Enter protected mode
    ; ----------------------------------------------------------
    cli
    mov     eax, cr0
    or      eax, 1              ; set PE bit
    mov     cr0, eax

    ; Far jump to flush instruction pipeline and load CS with PM selector
    jmp     BOOT_CODE_SEG : pm_entry

; ==============================================================
; Enable A20 — keyboard controller method
; ==============================================================
enable_a20:
    call    .kbd_wait
    mov     al, 0xAD            ; disable keyboard
    out     0x64, al

    call    .kbd_wait
    mov     al, 0xD0            ; read output port
    out     0x64, al

    call    .kbd_out_wait
    in      al, 0x60
    push    ax                  ; save output port value

    call    .kbd_wait
    mov     al, 0xD1            ; write output port
    out     0x64, al

    call    .kbd_wait
    pop     ax
    or      al, 0x02            ; set A20 bit
    out     0x60, al

    call    .kbd_wait
    mov     al, 0xAE            ; re-enable keyboard
    out     0x64, al

    call    .kbd_wait
    ret

.kbd_wait:                      ; wait for input buffer empty
    in      al, 0x64
    test    al, 0x02
    jnz     .kbd_wait
    ret

.kbd_out_wait:                  ; wait for output buffer full
    in      al, 0x64
    test    al, 0x01
    jz      .kbd_out_wait
    ret

; ==============================================================
; VESA: set mode 800x600x32bpp (LFB)
; Saves VBE Mode Info Block at VESA_INFO_ADDR
; ==============================================================
if VESA_ENABLE = 1
vesa_set_mode:
    ; --- Query mode info to get framebuffer address -----------
    mov     ax, 0x4F01          ; VBE get mode info
    mov     cx, VESA_MODE and 0x3FFF   ; mode number (without LFB flag)
    mov     di, VESA_INFO_ADDR  ; ES:DI → info buffer
    push    es
    xor     ax, ax
    mov     es, ax
    pop     es
    mov     di, VESA_INFO_ADDR and 0xFFFF
    push    es
    mov     ax, VESA_INFO_ADDR shr 4
    mov     es, ax
    xor     di, di
    mov     ax, 0x4F01
    mov     cx, VESA_MODE and 0x3FFF
    int     0x10
    pop     es
    cmp     ax, 0x004F
    jne     .vesa_fail

    ; --- Set mode (with linear framebuffer flag) --------------
    mov     ax, 0x4F02
    mov     bx, VESA_MODE       ; LFB flag 0x4000 already included
    int     0x10
    cmp     ax, 0x004F
    jne     .vesa_fail
    ret
.vesa_fail:
    ; VESA not supported — continue in text mode
    ret
end if

; ==============================================================
; Load kernel from disk using BIOS INT 13h extended read (LBA)
; Kernel target: physical 0x10000 (segment 0x1000, offset 0x0000)
; ==============================================================
load_kernel:
    mov     si, msg_kload
    call    puts16

    ; Fill Disk Address Packet (DAP) at s2_dap
    mov     word [s2_dap + 2], KERNEL_SECTORS   ; sector count
    mov     word [s2_dap + 4], 0x0000            ; dest offset
    mov     word [s2_dap + 6], 0x1000            ; dest segment → phys 0x10000
    mov     dword [s2_dap + 8], KERNEL_LBA       ; LBA lo
    mov     dword [s2_dap + 12], 0               ; LBA hi

    mov     ah, 0x42            ; extended read
    mov     dl, 0x80            ; first hard disk (stage1 saves dl, but QEMU uses 0x80)
    mov     si, s2_dap
    int     0x13
    jc      .kerr

    mov     si, msg_kloaded
    call    puts16
    ret
.kerr:
    mov     si, msg_kfail
    call    puts16
    ; halt — can't continue without kernel
.halt:
    hlt
    jmp     .halt

; ==============================================================
; Real-mode teletype print
; ==============================================================
puts16:
    lodsb
    test    al, al
    jz      .done
    mov     ah, 0x0E
    mov     bx, 0x0007
    int     0x10
    jmp     puts16
.done:
    ret

; ==============================================================
; Temporary GDT (used only until kernel loads its own)
; ==============================================================
align 8
s2_gdt:
    dq 0                        ; null descriptor
    ; Code: base=0 limit=4G DPL=0 32-bit code readable
    dw 0xFFFF, 0x0000, 0x9A00, 0x00CF
    ; Data: base=0 limit=4G DPL=0 32-bit data writable
    dw 0xFFFF, 0x0000, 0x9200, 0x00CF
s2_gdt_end:

s2_gdt_desc:
    dw s2_gdt_end - s2_gdt - 1 ; limit
    dd s2_gdt                   ; base (absolute linear, DS=0 so = offset)

; Disk Address Packet (16 bytes)
s2_dap:
    db 0x10         ; packet size
    db 0x00         ; reserved
    dw 0            ; sector count   (filled at runtime)
    dw 0            ; dest offset    (filled at runtime)
    dw 0            ; dest segment   (filled at runtime)
    dq 0            ; 64-bit LBA     (filled at runtime)

; Messages
msg_stage2  db 'Stage 2 OK', 0x0D, 0x0A, 0
msg_kload   db 'Loading kernel...', 0x0D, 0x0A, 0
msg_kloaded db 'Kernel loaded.', 0x0D, 0x0A, 0
msg_kfail   db 'Kernel load FAILED!', 0x0D, 0x0A, 0

; ==============================================================
; Protected Mode entry (32-bit)
; CS = BOOT_CODE_SEG (0x08), still running at physical 0x0500+
; ==============================================================
use32
pm_entry:
    mov     ax, BOOT_DATA_SEG
    mov     ds, ax
    mov     es, ax
    mov     fs, ax
    mov     gs, ax
    mov     ss, ax
    mov     esp, KERNEL_STACK_TOP   ; temporary stack

    ; Jump to kernel
    jmp     KERNEL_LOAD_ADDR
