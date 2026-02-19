; =============================================================
; ProbablyFineOS — System Constants
; Included by bootloader (use16) and kernel (use32).
; All numeric constants only — no instructions or data.
; =============================================================

; -------------------------------------------------------------
; Architecture selector (override via -d ARCH=64 on FASM CLI)
; -------------------------------------------------------------
if ~ defined ARCH
    ARCH = 32
end if

; -------------------------------------------------------------
; Disk layout (LBA sector numbers, 0-indexed)
; -------------------------------------------------------------
STAGE2_LBA      equ 1       ; stage2 starts at LBA 1
STAGE2_SECTORS  equ 16      ; up to 16 sectors (8 KB)
KERNEL_LBA      equ 17      ; kernel starts at LBA 17
KERNEL_SECTORS  equ 64      ; load up to 32 KB of kernel

; -------------------------------------------------------------
; Memory map (physical addresses)
; -------------------------------------------------------------
STAGE2_LOAD_ADDR   equ 0x00000500   ; stage2 entry point
KERNEL_LOAD_ADDR   equ 0x00010000   ; kernel binary base
KERNEL_STACK_TOP   equ 0x00090000   ; kernel stack grows down from here
VGA_TEXT_BASE      equ 0x000B8000   ; VGA text-mode frame buffer
VGA_GFX_BASE       equ 0x000A0000   ; VGA graphics frame buffer (VESA)

; -------------------------------------------------------------
; GDT selectors (byte offset into the kernel GDT)
; -------------------------------------------------------------
GDT_NULL_SEG    equ 0x00    ; null descriptor
GDT_KCODE_SEG   equ 0x08    ; kernel code, DPL=0
GDT_KDATA_SEG   equ 0x10    ; kernel data, DPL=0
GDT_UCODE_SEG   equ 0x18    ; user code,   DPL=3
GDT_UDATA_SEG   equ 0x20    ; user data,   DPL=3

; Convenience alias used in stage2 minimal GDT (same values)
BOOT_CODE_SEG   equ 0x08
BOOT_DATA_SEG   equ 0x10

; -------------------------------------------------------------
; IDT vector base after PIC remapping
; -------------------------------------------------------------
IRQ_BASE_MASTER equ 0x20    ; IRQ 0-7  → vectors 0x20-0x27
IRQ_BASE_SLAVE  equ 0x28    ; IRQ 8-15 → vectors 0x28-0x2F

IRQ_KEYBOARD    equ 0x21    ; IRQ1 keyboard
IRQ_MOUSE       equ 0x2C    ; IRQ12 PS/2 mouse

; -------------------------------------------------------------
; I/O Ports
; -------------------------------------------------------------
; 8259A PIC
PIC_MASTER_CMD  equ 0x20
PIC_MASTER_DATA equ 0x21
PIC_SLAVE_CMD   equ 0xA0
PIC_SLAVE_DATA  equ 0xA1
PIC_EOI         equ 0x20    ; End-of-Interrupt command

; PS/2 Controller
PS2_DATA_PORT   equ 0x60    ; read/write data
PS2_STATUS_PORT equ 0x64    ; read  status register
PS2_CMD_PORT    equ 0x64    ; write command register

; PS/2 Keyboard (same port as PS2_DATA_PORT)
KBD_DATA_PORT   equ 0x60

; VGA CRTC
VGA_CRTC_ADDR   equ 0x3D4   ; CRTC index register
VGA_CRTC_DATA   equ 0x3D5   ; CRTC data  register

; IO delay port (POST diagnostic)
IO_DELAY_PORT   equ 0x80

; -------------------------------------------------------------
; VGA Text Mode geometry
; -------------------------------------------------------------
VGA_COLS        equ 80
VGA_ROWS        equ 25
VGA_SIZE        equ VGA_COLS * VGA_ROWS   ; 2000 cells

; VGA colour attribute constants (foreground, background)
VGA_BLACK       equ 0x0
VGA_BLUE        equ 0x1
VGA_GREEN       equ 0x2
VGA_CYAN        equ 0x3
VGA_RED         equ 0x4
VGA_MAGENTA     equ 0x5
VGA_BROWN       equ 0x6
VGA_LGRAY       equ 0x7
VGA_DGRAY       equ 0x8
VGA_LBLUE       equ 0x9
VGA_LGREEN      equ 0xA
VGA_LCYAN       equ 0xB
VGA_LRED        equ 0xC
VGA_LMAGENTA    equ 0xD
VGA_YELLOW      equ 0xE
VGA_WHITE       equ 0xF

; Default text attribute: light grey on black
VGA_DEFAULT_ATTR equ (VGA_BLACK shl 4) or VGA_LGRAY

; -------------------------------------------------------------
; VESA / Linear Framebuffer (800×600×32bpp)
; -------------------------------------------------------------
VESA_WIDTH      equ 800
VESA_HEIGHT     equ 600
VESA_BPP        equ 32
VESA_MODE       equ 0x4114  ; VESA mode 800x600x32 (0x114) + linear-fb flag (0x4000)
FONT_WIDTH      equ 8
FONT_HEIGHT     equ 16
