; =============================================================
; ProbablyFineOS — Thread Management and Context Switching
; Included into kernel/kernel.asm
;
; Implements:
; - Thread Control Block (TCB) management
; - Context switching with full CPU and FPU state preservation
; - Idle thread
; =============================================================

; Thread configuration
MAX_THREADS         equ 8           ; Maximum number of threads
THREAD_QUANTUM      equ 100         ; Default quantum: 100 ticks (1 second at 100Hz)
KSTACK_SIZE         equ 16384       ; 16 KB kernel stack per thread (as per spec)

; ==============================================================
; Thread table and storage
; ==============================================================
align 16
thread_table:
    rb (MAX_THREADS * TCB_SIZE)

; Kernel stacks for threads at fixed high memory address
; Placed at 0x200000 (2 MB) to avoid conflicts
thread_stacks equ 0x200000

; Current running thread pointer
current_thread      dd 0            ; Pointer to current TCB

; Next TID to allocate
next_tid            dd 1            ; Start from 1 (TID 0 reserved for idle)

; ==============================================================
; thread_init — initialize thread subsystem and create idle thread
; Called from kernel_entry during initialization
; ==============================================================
thread_init:
    push    eax
    push    ebx
    push    ecx
    push    edi

    cli                             ; Disable interrupts during init

    ; Initialize thread_table to zeros
    mov     edi, thread_table
    mov     ecx, (MAX_THREADS * TCB_SIZE) / 4
    xor     eax, eax
    cld
    rep     stosd

    ; Create idle thread (TID 0)
    xor     eax, eax                ; TID 0
    lea     ebx, [idle_thread_entry]
    call    thread_create_internal

    ; Leave current_thread as NULL initially
    ; The boot context will continue until first thread is created
    mov     dword [current_thread], 0

    sti                             ; Re-enable interrupts

    pop     edi
    pop     ecx
    pop     ebx
    pop     eax
    ret

; ==============================================================
; thread_create_internal — create a new thread
; Input:
;   eax = TID (0 for idle, or next_tid for regular threads)
;   ebx = entry point address
; Returns:
;   eax = pointer to TCB, or 0 if failed
; Clobbers: eax, ebx, ecx, edx, edi
; ==============================================================
thread_create_internal:
    push    esi
    push    edi

    ; Calculate TCB address: thread_table + (TID * TCB_SIZE)
    mov     edi, eax
    imul    edi, TCB_SIZE
    add     edi, thread_table

    ; Initialize TCB fields
    mov     [edi + TCB_TID], eax
    mov     dword [edi + TCB_STATE], THREAD_STATE_READY
    mov     dword [edi + TCB_QUANTUM], THREAD_QUANTUM

    ; Calculate kernel stack: thread_stacks + (TID * KSTACK_SIZE)
    mov     esi, eax
    imul    esi, KSTACK_SIZE
    add     esi, thread_stacks
    mov     [edi + TCB_KSTACK_BASE], esi
    mov     dword [edi + TCB_KSTACK_SIZE], KSTACK_SIZE

    ; Set stack pointer to top of stack (grows down) and push entry point
    add     esi, KSTACK_SIZE        ; ESI = top of stack

    ; Push entry point onto stack (so ret will jump to it)
    sub     esi, 4
    mov     dword [esi], ebx        ; Push entry point address onto stack

    ; Save stack pointer (now points to entry point on stack)
    mov     [edi + TCB_ESP], esi

    ; Initialize saved context for first run
    mov     dword [edi + TCB_EFLAGS], 0x0202  ; IF=1 (interrupts enabled)

    ; Segment registers not saved/restored, so no need to initialize them
    ; General purpose registers start at 0
    mov     dword [edi + TCB_EAX], 0
    mov     dword [edi + TCB_EBX], 0
    mov     dword [edi + TCB_ECX], 0
    mov     dword [edi + TCB_EDX], 0
    mov     dword [edi + TCB_ESI], 0
    mov     dword [edi + TCB_EDI], 0
    mov     dword [edi + TCB_EBP], 0

    ; Initialize FPU state (clear to zeros, will be set on first use)
    lea     eax, [edi + TCB_FPU_STATE]
    mov     ecx, 512 / 4            ; 512 bytes / 4 = 128 dwords
    xor     ebx, ebx
.clear_fpu:
    mov     [eax], ebx
    add     eax, 4
    loop    .clear_fpu

    ; Return TCB pointer
    mov     eax, edi

    pop     edi
    pop     esi
    ret

; ==============================================================
; context_switch — switch from old thread to new thread
; Input:
;   eax = pointer to old thread TCB (current thread, can be NULL)
;   ebx = pointer to new thread TCB (next thread)
; Clobbers: none (all registers saved/restored)
; ==============================================================
context_switch:
    ; If old thread is NULL, skip save (first switch)
    test    eax, eax
    jz      .load_new

    ; Save old thread context
    ; Save general purpose registers
    mov     [eax + TCB_EAX], eax    ; Will be overwritten, but we restore it
    mov     [eax + TCB_ECX], ecx
    mov     [eax + TCB_EDX], edx
    mov     [eax + TCB_EBX], ebx
    mov     [eax + TCB_ESI], esi
    mov     [eax + TCB_EDI], edi
    mov     [eax + TCB_EBP], ebp

    ; Save stack pointer (with return address already on it)
    mov     [eax + TCB_ESP], esp

    ; Save EFLAGS
    pushfd
    pop     ecx
    mov     [eax + TCB_EFLAGS], ecx

    ; Note: We don't save EIP separately - it's already on the stack
    ; that ESP points to. When we restore ESP and do popfd/popad/ret,
    ; we'll return to the right place.

    ; Save FPU/SSE state using FXSAVE (if available)
    cmp     byte [fxsr_available], 1
    jne     .load_new
    lea     ecx, [eax + TCB_FPU_STATE]
    fxsave  [ecx]

.load_new:
    ; Update current_thread pointer
    mov     [current_thread], ebx

    ; Reset quantum for new thread
    mov     dword [ebx + TCB_QUANTUM], THREAD_QUANTUM

    ; Load new thread context
    ; Restore FPU/SSE state using FXRSTOR (if available)
    cmp     byte [fxsr_available], 1
    jne     .skip_fxrstor
    lea     ecx, [ebx + TCB_FPU_STATE]
    fxrstor [ecx]

.skip_fxrstor:
    ; Restore stack pointer (return address already on it)
    mov     esp, [ebx + TCB_ESP]

    ; Restore EFLAGS
    mov     ecx, [ebx + TCB_EFLAGS]
    push    ecx
    popfd

    ; Restore general purpose registers
    mov     eax, [ebx + TCB_EAX]
    mov     ecx, [ebx + TCB_ECX]
    mov     edx, [ebx + TCB_EDX]
    mov     esi, [ebx + TCB_ESI]
    mov     edi, [ebx + TCB_EDI]
    mov     ebp, [ebx + TCB_EBP]
    mov     ebx, [ebx + TCB_EBX]    ; Restore EBX last

    ; Return to address on stack (which is where context_switch was called from)
    ret

; ==============================================================
; idle_thread_entry — idle thread main loop
; Runs when no other threads are ready
; Executes HLT to save power until next interrupt
; ==============================================================
idle_thread_entry:
.loop:
    hlt                             ; Halt until interrupt
    jmp     .loop                   ; Loop forever

; ==============================================================
; Test thread functions (for demonstration)
; ==============================================================
test_thread_a:
    mov     ecx, 3                  ; Print 3 times
.loop:
    push    ecx
    lea     eax, [test_msg_a]
    push    eax
    call    vga_puts
    add     esp, 4
    call    thread_yield            ; Yield to other threads
    pop     ecx
    loop    .loop
    ; Done - just halt (scheduler will skip us)
.done:
    cli
    hlt
    jmp     .done

test_thread_b:
    mov     ecx, 3                  ; Print 3 times
.loop:
    push    ecx
    lea     eax, [test_msg_b]
    push    eax
    call    vga_puts
    add     esp, 4
    call    thread_yield            ; Yield to other threads
    pop     ecx
    loop    .loop
    ; Done - just halt (scheduler will skip us)
.done:
    cli
    hlt
    jmp     .done

test_msg_a db 'Thread A running', 0x0A, 0
test_msg_b db 'Thread B running', 0x0A, 0

; ==============================================================
; thread_get_current — get pointer to current thread TCB
; Returns: eax = current thread TCB pointer
; ==============================================================
thread_get_current:
    mov     eax, [current_thread]
    ret

; ==============================================================
; PUBLIC THREAD API
; ==============================================================

; ==============================================================
; thread_create — create a new thread and add to ready queue
; Input: eax = entry point address
; Returns: eax = TID of new thread, or -1 if failed
; ==============================================================
thread_create:
    push    ebx
    push    ecx
    push    edx

    ; Check if we have free thread slots
    mov     ecx, [next_tid]
    cmp     ecx, MAX_THREADS
    jge     .error                  ; No free slots

    ; Save entry point
    mov     ebx, eax

    ; Allocate new TID
    mov     eax, ecx
    inc     dword [next_tid]

    ; Create thread
    call    thread_create_internal
    test    eax, eax
    jz      .error                  ; Creation failed

    ; Add to ready queue
    call    ready_queue_enqueue

    ; Return TID
    mov     eax, ecx

    pop     edx
    pop     ecx
    pop     ebx
    ret

.error:
    mov     eax, -1
    pop     edx
    pop     ecx
    pop     ebx
    ret

; ==============================================================
; thread_yield — voluntarily give up CPU and reschedule
; Puts current thread at end of ready queue and switches to next
; ==============================================================
thread_yield:
    push    eax
    push    ebx
    push    ecx

    cli                             ; Disable interrupts during switch

    ; Get current thread
    mov     eax, [current_thread]
    test    eax, eax
    jz      .done                   ; No current thread

    ; Don't yield if idle thread
    cmp     dword [eax + TCB_TID], 0
    je      .done

    ; Add current thread to ready queue
    call    ready_queue_enqueue

    ; Select next thread
    call    schedule
    mov     ebx, eax                ; New thread

    ; Get current thread again (was modified by enqueue)
    mov     eax, [current_thread]

    ; Check if new thread is different
    cmp     eax, ebx
    je      .done                   ; Same thread, no switch

    ; Context switch
    call    context_switch

.done:
    sti                             ; Re-enable interrupts
    pop     ecx
    pop     ebx
    pop     eax
    ret

; ==============================================================
; thread_exit — terminate current thread
; Removes thread from scheduler and switches to next thread
; NOTE: This function never returns!
; ==============================================================
thread_exit:
    cli                             ; Disable interrupts

    ; Get current thread
    mov     eax, [current_thread]
    test    eax, eax
    jz      .hang                   ; No current thread (shouldn't happen)

    ; Set thread state to DEAD
    mov     dword [eax + TCB_STATE], THREAD_STATE_DEAD

    ; Select next thread (don't add current to ready queue!)
    call    schedule
    mov     ebx, eax                ; New thread

    ; Context switch (with NULL old thread to avoid saving dead thread)
    xor     eax, eax                ; Old thread = NULL
    call    context_switch

    ; Should never reach here
.hang:
    cli
    hlt
    jmp     .hang
