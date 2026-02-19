; =============================================================
; ProbablyFineOS — Global Descriptor Table
; Included into kernel/kernel.asm
; =============================================================

; ==============================================================
; gdt_init — install kernel GDT and reload all segment registers
; Clobbers: eax, ecx (preserved by caller via pushad in kernel.asm)
; ==============================================================
gdt_init:
    lgdt    [gdt_descriptor]

    ; Reload code segment via far return trick
    ; Push new CS selector and the address of .reload_cs, then retf
    push    GDT_KCODE_SEG
    lea     eax, [.reload_cs]
    push    eax
    retf

.reload_cs:
    ; Reload data segment registers
    mov     ax, GDT_KDATA_SEG
    mov     ds, ax
    mov     es, ax
    mov     fs, ax
    mov     gs, ax
    mov     ss, ax
    ret

; ==============================================================
; GDT Table
; ==============================================================
align 8
gdt_table:
    ; Descriptor 0: Null (required by x86 spec)
    gdt_null_entry

    ; Descriptor 1 — Kernel Code (0x08)
    ; Base=0, Limit=4GB, DPL=0, 32-bit code, readable, non-conforming
    gdt_code_entry 0, 0xFFFFF, 0x9A, 0xCF

    ; Descriptor 2 — Kernel Data (0x10)
    ; Base=0, Limit=4GB, DPL=0, 32-bit data, writable, expand-up
    gdt_code_entry 0, 0xFFFFF, 0x92, 0xCF

    ; Descriptor 3 — User Code (0x18)  [future ring-3 use]
    ; DPL=3: access byte bit 5-6 set
    gdt_code_entry 0, 0xFFFFF, 0xFA, 0xCF

    ; Descriptor 4 — User Data (0x20)  [future ring-3 use]
    gdt_code_entry 0, 0xFFFFF, 0xF2, 0xCF

gdt_end:

; GDTR pseudo-descriptor
gdt_descriptor:
    dw  gdt_end - gdt_table - 1    ; limit (size in bytes - 1)
    dd  gdt_table                   ; linear base address
