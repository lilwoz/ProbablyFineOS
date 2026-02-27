; =============================================================
; ProbablyFineOS — FPU/SSE Initialization
; Included into kernel/kernel.asm
;
; Initializes FPU and enables SSE/FXSR support if available
; =============================================================

; Global flag indicating FXSR availability
fxsr_available  db 0

; ==============================================================
; fpu_init — initialize FPU and enable SSE (if available)
; Checks CPUID for FXSR support before enabling
; ==============================================================
fpu_init:
    push    eax
    push    ebx
    push    ecx
    push    edx

    ; Clear EM (emulation) bit and set MP in CR0
    mov     eax, cr0
    and     eax, 0xFFFFFFFB         ; Clear CR0.EM (bit 2)
    or      eax, 0x02               ; Set CR0.MP (bit 1) - monitor coprocessor
    mov     cr0, eax

    ; Initialize FPU
    finit

    ; Check if CPUID is available
    pushfd
    pop     eax
    mov     ecx, eax
    xor     eax, 0x200000           ; Flip ID bit (bit 21)
    push    eax
    popfd
    pushfd
    pop     eax
    xor     eax, ecx                ; Check if bit was flipped
    jz      .no_cpuid               ; If not, CPUID not available

    ; Check for FXSR support (CPUID.01h:EDX.FXSR[bit 24])
    mov     eax, 1
    cpuid
    test    edx, 0x01000000         ; Test bit 24 (FXSR)
    jz      .no_fxsr                ; If not set, no FXSR support

    ; FXSR available, enable it in CR4
    mov     eax, cr4
    or      eax, 0x200              ; CR4.OSFXSR (bit 9)
    or      eax, 0x400              ; CR4.OSXMMEXCPT (bit 10)
    mov     cr4, eax

    ; Mark FXSR as available
    mov     byte [fxsr_available], 1
    jmp     .done

.no_cpuid:
.no_fxsr:
    ; FXSR not available, mark as unavailable
    mov     byte [fxsr_available], 0

.done:
    pop     edx
    pop     ecx
    pop     ebx
    pop     eax
    ret
