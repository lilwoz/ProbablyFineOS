; =============================================================
; ProbablyFineOS — Data Structure Macros
; Include AFTER constants.inc
; =============================================================

; -------------------------------------------------------------
; GDT entry (8 bytes)
;   base     — 32-bit segment base address
;   limit    — 20-bit segment limit (page or byte granularity)
;   access   — access byte  (P DPL S Type)
;   gran     — granularity  (G D/B L AVL limit[19:16])
;
; Example: gdt_code_entry 0, 0xFFFFF, 0x9A, 0xCF
; -------------------------------------------------------------
macro gdt_code_entry base, limit, access, gran {
    dw  (limit) and 0xFFFF                          ; limit[15:0]
    dw  (base)  and 0xFFFF                          ; base[15:0]
    db  ((base) shr 16) and 0xFF                    ; base[23:16]
    db  access                                      ; access byte
    db  (((limit) shr 16) and 0x0F) or ((gran) and 0xF0) ; gran + limit[19:16]
    db  ((base) shr 24) and 0xFF                    ; base[31:24]
}

; Null descriptor (8 zero bytes)
macro gdt_null_entry {
    dq 0
}

; -------------------------------------------------------------
; IDT gate (8 bytes) — 32-bit interrupt gate
;   handler  — 32-bit handler offset
;   sel      — code segment selector
;   attr     — type + attributes (e.g. 0x8E for kernel int gate)
; -------------------------------------------------------------
macro idt_gate_entry handler, sel, attr {
    dw  (handler) and 0xFFFF                        ; offset[15:0]
    dw  sel                                         ; segment selector
    db  0                                           ; reserved
    db  attr                                        ; type + attributes
    dw  ((handler) shr 16) and 0xFFFF               ; offset[31:16]
}

; IDT type/attribute constants
IDT_KERNEL_INT  equ 0x8E    ; Present, DPL=0, 32-bit interrupt gate
IDT_KERNEL_TRAP equ 0x8F    ; Present, DPL=0, 32-bit trap gate
IDT_USER_INT    equ 0xEE    ; Present, DPL=3, 32-bit interrupt gate

; -------------------------------------------------------------
; PS/2 Mouse packet (3 bytes, decoded into this record)
; Layout in memory: 3 consecutive bytes
;   +0  flags   bit0=L btn, bit1=R btn, bit2=M btn, bit4=X sign, bit5=Y sign
;   +1  dx      X delta (8-bit signed, sign in flags.bit4)
;   +2  dy      Y delta (8-bit signed, sign in flags.bit5, note: Y inverted)
; -------------------------------------------------------------
; (Used as labels in mouse.asm, defined as simple byte fields there)

; -------------------------------------------------------------
; VESA VBE Mode Info Block (partial — fields we need)
; Physical address passed from stage2 to kernel (at a fixed location)
; -------------------------------------------------------------
; Offsets within the VBE ModeInfoBlock (INT 10h/AX=4F01h):
VBE_WinA_Segment    equ 4     ; (unused in linear mode)
VBE_LinBytesPerLine equ 16    ; bytes per scan line (linear)
VBE_XResolution     equ 18    ; horizontal resolution
VBE_YResolution     equ 20    ; vertical resolution
VBE_BitsPerPixel    equ 25    ; bits per pixel
VBE_PhysBasePtr     equ 40    ; physical address of linear framebuffer

; VESA info is saved at this fixed address by stage2 (below kernel load)
VESA_INFO_ADDR      equ 0x00008000
