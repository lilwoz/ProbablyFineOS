; =============================================================
; ProbablyFineOS — Stage 1 Bootloader (MBR)
; Assembled to exactly 512 bytes by FASM.
;
; Disk layout (all LBA, 512-byte sectors):
;   LBA  0       This file (MBR, 512 bytes)
;   LBA  1-16    Stage 2   (up to 8 KB)
;   LBA 17+      Kernel    (up to 32 KB)
;
; BIOS loads us at physical 0x7C00 (CS:IP = 0000:7C00).
; We read Stage 2 into 0x0500 and jump there.
; =============================================================

format binary
use16
org 0x7C00

; ---- Entry --------------------------------------------------------
start:
    cli
    xor     ax, ax
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     sp, 0x7C00          ; stack below MBR
    sti

    mov     [boot_drive], dl    ; BIOS passes drive # in DL

    ; ---- Print splash ----------------------------------------
    mov     si, msg_loading
    call    puts

    ; ---- Load Stage 2 using INT 13h (CHS mode) ---------------
    ; Stage 2 starts at LBA 1  (cylinder 0, head 0, sector 2 in CHS)
    ; We load STAGE2_SECTORS sectors to 0x0500.
    ;
    ; CHS conversion for floppy (18 sec/track, 2 heads, 80 cyl):
    ;   LBA 1 = C=0, H=0, S=2
    ;   LBA 16 (last of stage2) = C=0, H=0, S=17  — still track 0
    ;
    STAGE2_SECTORS = 16
    mov     ah, 0x02            ; INT 13h: read sectors
    mov     al, STAGE2_SECTORS  ; sector count
    mov     ch, 0               ; cylinder 0
    mov     cl, 2               ; sector 2 (CHS sector count starts at 1)
    mov     dh, 0               ; head 0
    mov     dl, [boot_drive]
    mov     bx, 0x0500          ; ES:BX = 0000:0500
    int     0x13
    jc      .disk_error

    ; ---- Jump to Stage 2 -------------------------------------
    jmp     0x0000:0x0500

; ---- Disk error handler ----------------------------------
.disk_error:
    mov     si, msg_disk_err
    call    puts
.halt:
    hlt
    jmp     .halt

; ---- Real-mode teletype print (BIOS INT 10h / AH=0Eh) ----
; Input: SI → null-terminated string
puts:
    lodsb
    test    al, al
    jz      .done
    mov     ah, 0x0E
    mov     bx, 0x0007          ; page 0, light-grey attribute
    int     0x10
    jmp     puts
.done:
    ret

; ---- Data ------------------------------------------------
msg_loading  db 'ProbablyFineOS loading...', 0x0D, 0x0A, 0
msg_disk_err db 'Stage 2 read error!', 0x0D, 0x0A, 0
boot_drive   db 0

; ---- Pad to 510 bytes, append boot signature -------------
times 510 - ($ - $$) db 0
dw 0xAA55
