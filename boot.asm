; =============================================================================
; SimpleOS Bootloader
; Loads kernel from disk and jumps to it
; =============================================================================

org 0x7C00
use16

KERNEL_OFFSET equ 0x1000    ; Where we load the kernel

start:
    ; Set up segments
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    mov [BOOT_DRIVE], dl    ; BIOS passes boot drive in DL

    ; Print loading message
    mov si, MSG_LOADING
    call print_string

    ; Debug: print 1
    mov al, '1'
    call print_char

    ; Load kernel from disk
    call load_kernel

    ; Debug: print 2
    mov al, '2'
    call print_char

    ; Reset segments before jumping
    xor ax, ax
    mov ds, ax
    mov es, ax

    ; Jump to kernel (kernel will set video mode)
    ; Debug: print 3
    mov al, '3'
    call print_char

    mov dl, [BOOT_DRIVE]    ; Pass boot drive to kernel in DL
    jmp 0x0000:KERNEL_OFFSET

print_char:
    mov ah, 0x0E
    int 0x10
    ret

; -----------------------------------------------------------------------------
; Load kernel sectors from disk (48 sectors = 24KB)
; SeaBIOS handles cross-track reads automatically
; -----------------------------------------------------------------------------
load_kernel:
    ; Reset disk system first
    xor ax, ax
    mov dl, [BOOT_DRIVE]
    int 0x13

    ; Read 48 sectors starting from sector 2
    mov ah, 0x02            ; BIOS read sectors
    mov al, 48              ; 48 sectors = 24KB
    mov ch, 0               ; Cylinder 0
    mov cl, 2               ; Start from sector 2
    mov dh, 0               ; Head 0
    mov dl, [BOOT_DRIVE]
    mov bx, KERNEL_OFFSET   ; Load to ES:BX
    int 0x13
    jc disk_error
    ret

disk_error:
    mov si, MSG_DISK_ERR
    call print_string
    jmp $

print_string:
    pusha
.loop:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp .loop
.done:
    popa
    ret

BOOT_DRIVE      db 0
MSG_LOADING     db 'Loading SimpleOS...', 13, 10, 0
MSG_DISK_ERR    db 'Disk Error!', 0

times 510 - ($ - $$) db 0
dw 0xAA55
